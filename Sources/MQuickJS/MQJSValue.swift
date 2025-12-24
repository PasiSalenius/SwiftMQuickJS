import Foundation
import CMQuickJS

/// A JavaScript value wrapper with automatic GC reference management.
///
/// MQJSValue wraps a JavaScript value and ensures it remains valid throughout its lifetime
/// by maintaining a GC reference. This is critical because mquickjs uses a moving garbage
/// collector that can relocate objects during allocation.
///
/// ## GC Safety
/// Each MQJSValue holds a JSGCRef that prevents the underlying JavaScript value from being
/// collected or moved. The reference is automatically managed through the value's lifecycle.
///
/// ## Usage
/// ```swift
/// let value = try context.eval("({ x: 42 })")
/// print(value.isObject) // true
/// let x = value["x"]
/// print(try x?.toInt32()) // 42
/// ```
public final class MQJSValue {
    // MARK: - Internal State

    /// Weak reference to context (context owns values)
    internal weak var context: MQJSContext?

    /// The actual JavaScript value
    internal private(set) var jsValue: JSValue

    /// GC reference to prevent value from being collected/moved
    /// CRITICAL: Must be managed via JS_AddGCRef/JS_DeleteGCRef
    private var gcRef: JSGCRef

    /// Pointer to the gcRef for GC system
    private var gcRefPtr: UnsafeMutablePointer<JSGCRef>?

    /// Track if value is still valid
    private var isValid: Bool = true

    // MARK: - Initialization (Internal)

    /// Creates a new JavaScript value wrapper.
    ///
    /// - Parameters:
    ///   - context: The JavaScript context
    ///   - jsValue: The underlying JSValue
    ///
    /// This initializer is internal and should only be called by MQJSContext or other
    /// internal APIs. It automatically registers the value with the GC system.
    internal init(context: MQJSContext, jsValue: JSValue) {
        self.context = context
        self.jsValue = jsValue

        // Initialize gcRef (value will be overwritten by JS_AddGCRef)
        self.gcRef = JSGCRef(val: 0, prev: nil)

        // Allocate stable pointer for gcRef
        self.gcRefPtr = UnsafeMutablePointer<JSGCRef>.allocate(capacity: 1)
        self.gcRefPtr!.initialize(to: self.gcRef)

        // Register with GC system - returns pointer to ref->val which was set to JS_UNDEFINED
        // CRITICAL: We must assign the actual value to the returned pointer!
        let valuePtr = JS_AddGCRef(context.ctx, self.gcRefPtr!)

        // Assign the actual JSValue to the GC ref (this is the key step!)
        valuePtr!.pointee = jsValue

        // Register with context for lifecycle tracking
        context.registerValue(self)
    }

    deinit {
        invalidate()
    }

    // MARK: - Invalidation

    /// Invalidate this value (called when context is freed or value is destroyed)
    internal func invalidate() {
        guard isValid, let ctx = context else { return }
        isValid = false

        // CRITICAL: Must remove GC ref before context is freed
        if let ptr = gcRefPtr {
            JS_DeleteGCRef(ctx.ctx, ptr)
            ptr.deinitialize(count: 1)
            ptr.deallocate()
            gcRefPtr = nil
        }

        context?.unregisterValue(self)
    }

    // MARK: - Type Checking

    /// Returns true if the value is undefined
    public var isUndefined: Bool {
        guard checkValid() else { return false }
        return JS_IsUndefined(jsValue) != 0
    }

    /// Returns true if the value is null
    public var isNull: Bool {
        guard checkValid() else { return false }
        return JS_IsNull(jsValue) != 0
    }

    /// Returns true if the value is a boolean
    public var isBool: Bool {
        guard checkValid() else { return false }
        return JS_IsBool(jsValue) != 0
    }

    /// Returns true if the value is a number
    public var isNumber: Bool {
        guard checkValid(), let ctx = context else { return false }
        return JS_IsNumber(ctx.ctx, jsValue) != 0
    }

    /// Returns true if the value is a string
    public var isString: Bool {
        guard checkValid(), let ctx = context else { return false }
        return JS_IsString(ctx.ctx, jsValue) != 0
    }

    /// Returns true if the value is an object
    public var isObject: Bool {
        guard checkValid() else { return false }
        // Objects are pointers, but strings are also pointers
        return JS_IsPtr(jsValue) != 0 && !isString
    }

    /// Returns true if the value is a function
    public var isFunction: Bool {
        guard checkValid(), let ctx = context else { return false }
        return JS_IsFunction(ctx.ctx, jsValue) != 0
    }

    // MARK: - Value Conversion

    /// Converts the value to a Swift Int32.
    ///
    /// - Throws: MQJSError if conversion fails or value is invalid
    /// - Returns: The value as Int32
    public func toInt32() throws -> Int32 {
        let ctx = try checkedContext()
        var result: Int32 = 0
        if JS_ToInt32(ctx.ctx, &result, jsValue) != 0 {
            throw try ctx.extractError()
        }
        return result
    }

    /// Converts the value to a Swift Double.
    ///
    /// - Throws: MQJSError if conversion fails or value is invalid
    /// - Returns: The value as Double
    public func toDouble() throws -> Double {
        let ctx = try checkedContext()
        var result: Double = 0
        if JS_ToNumber(ctx.ctx, &result, jsValue) != 0 {
            throw try ctx.extractError()
        }
        return result
    }

    /// Converts the value to a Swift String.
    ///
    /// - Throws: MQJSError if conversion fails or value is invalid
    /// - Returns: The value as String
    public func toString() throws -> String {
        let ctx = try checkedContext()
        var buf = JSCStringBuf()
        var length: Int = 0

        guard let cString = JS_ToCStringLen(ctx.ctx, &length, jsValue, &buf) else {
            throw try ctx.extractError()
        }

        // Copy to Swift String immediately (C string may be temporary)
        // Try UTF-8 first, fall back to ISO Latin1 if that fails
        return String(cString: cString, encoding: .utf8)
            ?? String(cString: cString, encoding: .isoLatin1)
            ?? String(cString: cString)
    }

    /// Converts the value to a Swift Bool.
    ///
    /// - Returns: The value as Bool, or nil if not a boolean
    public func toBool() -> Bool? {
        guard checkValid(), isBool else { return nil }
        return jsValue == mqjs_get_true()
    }

    // MARK: - Property Access

    /// Access properties by name (subscript).
    ///
    /// ```swift
    /// let obj = try context.eval("({ name: 'John', age: 30 })")
    /// print(try obj["name"]?.toString()) // "John"
    /// obj["city"] = try "NYC".toJSValue(in: context)
    /// ```
    public subscript(propertyName: String) -> MQJSValue? {
        get {
            guard checkValid(), let ctx = context else { return nil }

            let result = JS_GetPropertyStr(ctx.ctx, jsValue, propertyName)

            // Check for exception
            if JS_IsException(result) != 0 {
                return nil
            }

            return MQJSValue(context: ctx, jsValue: result)
        }
        set {
            guard checkValid(), let ctx = context else { return }

            let valueToSet = newValue?.jsValue ?? mqjs_get_undefined()
            _ = JS_SetPropertyStr(ctx.ctx, jsValue, propertyName, valueToSet)
        }
    }

    /// Access properties by index (subscript for arrays).
    ///
    /// ```swift
    /// let arr = try context.eval("[1, 2, 3]")
    /// print(try arr[0]?.toInt32()) // 1
    /// arr[3] = try 4.toJSValue(in: context)
    /// ```
    public subscript(index: Int) -> MQJSValue? {
        get {
            guard checkValid(), let ctx = context else { return nil }
            guard index >= 0 else { return nil }

            let result = JS_GetPropertyUint32(ctx.ctx, jsValue, UInt32(index))

            if JS_IsException(result) != 0 {
                return nil
            }

            return MQJSValue(context: ctx, jsValue: result)
        }
        set {
            guard checkValid(), let ctx = context else { return }
            guard index >= 0 else { return }

            let valueToSet = newValue?.jsValue ?? mqjs_get_undefined()
            _ = JS_SetPropertyUint32(ctx.ctx, jsValue, UInt32(index), valueToSet)
        }
    }

    // MARK: - Function Calling (JSC-compatible)

    /// Calls this value as a JavaScript function.
    ///
    /// This method is compatible with JavaScriptCore's `JSValue.call(withArguments:)`.
    ///
    /// ```swift
    /// let add = context.globalObject["add"]!
    /// let result = try add.call(withArguments: [5, 3])
    /// print(try result.toInt32()) // 8
    /// ```
    ///
    /// - Parameter arguments: Arguments to pass to the function. Supports Int, Double, String,
    ///   Bool, Array, Dictionary, MQJSValue, and nil/NSNull (converted to JS null).
    /// - Returns: The return value from the function
    /// - Throws: `MQJSError.notAFunction` if this value is not callable
    public func call(withArguments arguments: [Any]?) throws -> MQJSValue {
        let ctx = try checkedContext()
        guard isFunction else { throw MQJSError.notAFunction }
        return try performCall(
            function: self.jsValue,
            thisValue: mqjs_get_undefined(),
            arguments: arguments,
            in: ctx
        )
    }

    /// Invokes a method on this object by name.
    ///
    /// This method is compatible with JavaScriptCore's `JSValue.invokeMethod(_:withArguments:)`.
    ///
    /// ```swift
    /// let calculator = context.globalObject["calculator"]!
    /// let result = try calculator.invokeMethod("add", withArguments: [5, 3])
    /// print(try result.toInt32()) // 8
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the method to invoke
    ///   - arguments: Arguments to pass to the method
    /// - Returns: The return value from the method
    /// - Throws: `MQJSError.notAnObject` if this value is not an object,
    ///           `MQJSError.notAFunction` if the property is not a function
    public func invokeMethod(_ name: String, withArguments arguments: [Any]?) throws -> MQJSValue {
        let ctx = try checkedContext()
        guard isObject else { throw MQJSError.notAnObject }

        guard let method = self[name] else {
            throw MQJSError.evaluationError("Method '\(name)' not found")
        }
        guard method.isFunction else { throw MQJSError.notAFunction }

        return try performCall(
            function: method.jsValue,
            thisValue: self.jsValue,
            arguments: arguments,
            in: ctx
        )
    }

    /// Constructs a new object using this value as a constructor.
    ///
    /// This method is compatible with JavaScriptCore's `JSValue.construct(withArguments:)`.
    ///
    /// ```swift
    /// let DateConstructor = context.globalObject["Date"]!
    /// let date = try DateConstructor.construct(withArguments: [2024, 0, 1])
    /// ```
    ///
    /// - Parameter arguments: Arguments to pass to the constructor
    /// - Returns: The newly constructed object
    /// - Throws: `MQJSError.notAFunction` if this value is not a constructor
    public func construct(withArguments arguments: [Any]?) throws -> MQJSValue {
        let ctx = try checkedContext()
        guard isFunction else { throw MQJSError.notAFunction }

        // Use eval to construct - mquickjs doesn't expose a direct construct API
        let jsArgs = try arguments?.map { try convertToJSValue($0, in: ctx) } ?? []

        // Build argument list for eval
        var argList = ""
        for (index, arg) in jsArgs.enumerated() {
            ctx.globalObject["__arg\(index)__"] = arg
            if index > 0 { argList += ", " }
            argList += "__arg\(index)__"
        }

        ctx.globalObject["__ctor__"] = self
        defer {
            // Clean up temporaries
            ctx.globalObject["__ctor__"] = nil
            for index in 0..<jsArgs.count {
                ctx.globalObject["__arg\(index)__"] = nil
            }
        }

        return try ctx.eval("new __ctor__(\(argList))")
    }

    // MARK: - Collection Conversion (JSC-compatible)

    /// Converts this JavaScript array to a Swift array.
    ///
    /// This method is compatible with JavaScriptCore's `JSValue.toArray()`.
    ///
    /// ```swift
    /// let arr = try context.eval("[1, 'hello', true]")
    /// let swiftArray = try arr.toArray() // [1, "hello", true] as [Any]
    /// ```
    ///
    /// - Returns: A Swift array containing the converted elements
    /// - Throws: `MQJSError.typeConversionError` if conversion fails
    public func toArray() throws -> [Any] {
        _ = try checkedContext()
        guard isObject else {
            throw MQJSError.typeConversionError("Value is not an array or object")
        }

        guard let lengthValue = self["length"],
              let length = try? lengthValue.toInt32(),
              length >= 0 else {
            throw MQJSError.typeConversionError("Cannot get array length")
        }

        var result: [Any] = []
        result.reserveCapacity(Int(length))

        for i in 0..<Int(length) {
            if let element = self[i] {
                result.append(try element.toObject())
            } else {
                result.append(NSNull())
            }
        }

        return result
    }

    /// Converts this JavaScript object to a Swift dictionary.
    ///
    /// This method is compatible with JavaScriptCore's `JSValue.toDictionary()`.
    /// Uses `JSON.stringify` internally since mquickjs doesn't expose property enumeration.
    ///
    /// ```swift
    /// let obj = try context.eval("({name: 'Alice', age: 30})")
    /// let dict = try obj.toDictionary() // ["name": "Alice", "age": 30]
    /// ```
    ///
    /// - Returns: A Swift dictionary with string keys
    /// - Throws: `MQJSError.typeConversionError` if conversion fails
    public func toDictionary() throws -> [String: Any] {
        let ctx = try checkedContext()
        guard isObject else {
            throw MQJSError.typeConversionError("Value is not an object")
        }

        guard let json = ctx.globalObject["JSON"],
              let stringify = json["stringify"],
              stringify.isFunction else {
            throw MQJSError.evaluationError("JSON.stringify not available")
        }

        let jsonString = try stringify.call(withArguments: [self]).toString()

        guard let data = jsonString.data(using: .utf8),
              let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MQJSError.typeConversionError("JSON did not parse to dictionary")
        }

        return parsed
    }

    /// Converts this JavaScript value to the appropriate Swift type.
    ///
    /// This method is compatible with JavaScriptCore's `JSValue.toObject()`.
    ///
    /// - Returns: The Swift representation of the value:
    ///   - `undefined` → `NSNull()`
    ///   - `null` → `NSNull()`
    ///   - `boolean` → `Bool`
    ///   - `number` → `Double` or `Int` if whole number
    ///   - `string` → `String`
    ///   - `array` → `[Any]`
    ///   - `object` → `[String: Any]`
    public func toObject() throws -> Any {
        _ = try checkedContext()

        if isUndefined || isNull { return NSNull() }
        if isBool { return toBool() ?? false }

        if isNumber {
            let d = try toDouble()
            // Return Int if it's a whole number
            if d.truncatingRemainder(dividingBy: 1) == 0 && d >= Double(Int.min) && d <= Double(Int.max) {
                return Int(d)
            }
            return d
        }

        if isString { return try toString() }
        if isFunction { return self }

        // Check if it's an array (has numeric length property)
        if let lengthValue = self["length"], lengthValue.isNumber {
            return try toArray()
        }

        return try toDictionary()
    }

    // MARK: - Private Helpers

    /// Validates state and returns the context, or throws
    private func checkedContext() throws -> MQJSContext {
        guard isValid else { throw MQJSError.invalidValue }
        guard let ctx = context else { throw MQJSError.invalidContext }
        return ctx
    }

    /// Check if value is valid (non-throwing, for properties)
    @discardableResult
    private func checkValid() -> Bool {
        guard isValid else {
            assertionFailure("Accessing invalid MQJSValue")
            return false
        }
        guard context != nil else {
            assertionFailure("Context was deallocated")
            return false
        }
        return true
    }

    /// Performs a JavaScript function call with the given parameters
    private func performCall(
        function: JSValue,
        thisValue: JSValue,
        arguments: [Any]?,
        in ctx: MQJSContext
    ) throws -> MQJSValue {
        let jsArgs = try arguments?.map { try convertToJSValue($0, in: ctx) } ?? []

        if JS_StackCheck(ctx.ctx, UInt32(jsArgs.count + 2)) != 0 {
            throw MQJSError.stackOverflow
        }

        // Push arguments in REVERSE order (mquickjs calling convention)
        for arg in jsArgs.reversed() {
            JS_PushArg(ctx.ctx, arg.jsValue)
        }
        JS_PushArg(ctx.ctx, function)
        JS_PushArg(ctx.ctx, thisValue)

        let result = JS_Call(ctx.ctx, Int32(jsArgs.count))
        if JS_IsException(result) != 0 {
            throw try ctx.extractError()
        }

        return MQJSValue(context: ctx, jsValue: result)
    }

    /// Converts a single Swift value to MQJSValue
    private func convertToJSValue(_ value: Any, in ctx: MQJSContext) throws -> MQJSValue {
        // Note: Order matters - Bool must be checked before NSNumber since Bool bridges to NSNumber
        switch value {
        case let jsValue as MQJSValue:
            return jsValue

        case is NSNull:
            return MQJSValue(context: ctx, jsValue: mqjs_get_null())

        case let boolValue as Bool:
            return try boolValue.toJSValue(in: ctx)

        case let intValue as Int:
            return try intValue.toJSValue(in: ctx)

        case let int32Value as Int32:
            return try int32Value.toJSValue(in: ctx)

        case let uint32Value as UInt32:
            return try uint32Value.toJSValue(in: ctx)

        case let doubleValue as Double:
            return try doubleValue.toJSValue(in: ctx)

        case let floatValue as Float:
            return try floatValue.toJSValue(in: ctx)

        case let stringValue as String:
            return try stringValue.toJSValue(in: ctx)

        case let arrayValue as [Any]:
            let jsArray = JS_NewArray(ctx.ctx, Int32(arrayValue.count))
            let arrayWrapper = MQJSValue(context: ctx, jsValue: jsArray)
            for (index, element) in arrayValue.enumerated() {
                arrayWrapper[index] = try convertToJSValue(element, in: ctx)
            }
            return arrayWrapper

        case let dictValue as [String: Any]:
            let jsObject = JS_NewObject(ctx.ctx)
            let objectWrapper = MQJSValue(context: ctx, jsValue: jsObject)
            for (key, element) in dictValue {
                objectWrapper[key] = try convertToJSValue(element, in: ctx)
            }
            return objectWrapper

        case let numberValue as NSNumber:
            return try numberValue.doubleValue.toJSValue(in: ctx)

        default:
            throw MQJSError.typeConversionError("Cannot convert \(type(of: value)) to JavaScript value")
        }
    }
}
