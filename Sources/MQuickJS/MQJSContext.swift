import Foundation
import CMQuickJS

// MARK: - Eval Flags (from C macros)

/// Return the last expression value
public let JS_EVAL_RETVAL = mqjs_eval_flag_retval()

/// REPL mode (handle top-level await)
public let JS_EVAL_REPL = mqjs_eval_flag_repl()

/// Strip column info from error messages
public let JS_EVAL_STRIP_COL = mqjs_eval_flag_strip_col()

/// Parse as JSON
public let JS_EVAL_JSON = mqjs_eval_flag_json()

// MARK: - Context

/// The main JavaScript execution context.
///
/// MQJSContext manages a JavaScript runtime environment including:
/// - Memory allocation for the JavaScript engine
/// - Standard library initialization
/// - Script evaluation
/// - Global object access
/// - Lifecycle management of JavaScript values
///
/// ## Thread Safety
/// MQJSContext is NOT thread-safe. You must:
/// - Create separate contexts for each thread, OR
/// - Synchronize all access via a serial DispatchQueue
///
/// ## Usage
/// ```swift
/// let context = try MQJSContext(memorySize: 256 * 1024)
/// let result = try context.eval("1 + 2")
/// print(try result.toInt32()) // Prints: 3
/// ```
public final class MQJSContext {
    // MARK: - Internal State

    /// The underlying C context (opaque pointer)
    internal let ctx: OpaquePointer

    /// Memory buffer - MUST stay alive for context lifetime
    internal let memoryBuffer: MQJSMemoryBuffer

    /// Track if context is valid (not freed)
    private var isValid: Bool = true

    /// Weak references to all live values to coordinate cleanup
    private var liveValues = NSHashTable<MQJSValue>.weakObjects()

    // MARK: - Native Function Binding

    /// Type alias for native function handlers
    public typealias NativeFunction = ([MQJSValue]) throws -> Any?

    /// Registry of native functions keyed by ID
    private var nativeFunctions: [Int32: NativeFunction] = [:]

    /// Counter for generating unique function IDs
    private var nextFunctionId: Int32 = 0

    /// Static registry to look up context by opaque pointer
    /// This is needed because C callbacks can't capture Swift context
    private static var contextRegistry: [UnsafeMutableRawPointer: MQJSContext] = [:]

    /// Lock for thread-safe access to contextRegistry
    private static let registryLock = NSLock()

    // MARK: - Memory Size Constants

    /// Default memory size: 1MB (suitable for most scripts)
    public static let defaultMemorySize: Int = 1024 * 1024

    /// Minimum safe memory size: 64KB
    public static let minimumMemorySize: Int = MQJSMemoryBuffer.minimumSize

    /// Memory size for simple scripts: 64KB
    public static let memoryForSimpleScripts: Int = 64 * 1024

    /// Memory size for moderate scripts: 256KB
    public static let memoryForModerateScripts: Int = 256 * 1024

    /// Memory size for complex scripts: 1MB
    public static let memoryForComplexScripts: Int = 1024 * 1024

    /// Memory size for development/testing: 4MB
    public static let memoryForDevelopment: Int = 4 * 1024 * 1024

    // MARK: - Initialization

    /// Creates a new JavaScript context.
    ///
    /// - Parameters:
    ///   - memorySize: Size of memory buffer in bytes (default: 1MB, minimum: 64KB)
    /// - Throws: MQJSError if context creation fails
    public init(memorySize: Int = defaultMemorySize) throws {
        guard memorySize >= Self.minimumMemorySize else {
            throw MQJSError.invalidMemorySize(memorySize)
        }

        // Allocate memory buffer
        let memBuf = try MQJSMemoryBuffer(size: memorySize)
        self.memoryBuffer = memBuf

        // Create context with standard library
        // Get the stdlib definition via helper function
        let stdlibPtr = mqjs_get_stdlib()
        guard let context = JS_NewContext(
            memBuf.baseAddress,
            memBuf.size,
            stdlibPtr
        ) else {
            throw MQJSError.contextCreationFailed
        }

        self.ctx = context

        // Set up native function callback support
        Self.initializeNativeCallback()
        registerWithContextRegistry()
    }

    /// Initialize the native callback (only once globally)
    private static var nativeCallbackInitialized = false

    private static func initializeNativeCallback() {
        guard !nativeCallbackInitialized else { return }
        nativeCallbackInitialized = true

        // Set the C callback that will be invoked when JS calls native functions
        mqjs_set_native_callback(nativeCallbackHandler)
    }

    /// Static callback handler for native function calls from C
    private static let nativeCallbackHandler: MQJSNativeCallback = { opaque, functionId, argc, argv in
        guard let opaque = opaque else {
            return mqjs_get_exception()
        }

        // Look up the context
        registryLock.lock()
        let context = contextRegistry[opaque]
        registryLock.unlock()

        guard let context = context else {
            return mqjs_get_exception()
        }

        return context.handleNativeCall(functionId: functionId, argc: argc, argv: argv)
    }

    /// Register this context in the static registry
    private func registerWithContextRegistry() {
        let opaquePtr = Unmanaged.passUnretained(self).toOpaque()
        mqjs_set_context_opaque(ctx, opaquePtr)

        Self.registryLock.lock()
        Self.contextRegistry[opaquePtr] = self
        Self.registryLock.unlock()
    }

    /// Unregister this context from the static registry
    private func unregisterFromContextRegistry() {
        let opaquePtr = Unmanaged.passUnretained(self).toOpaque()

        Self.registryLock.lock()
        Self.contextRegistry.removeValue(forKey: opaquePtr)
        Self.registryLock.unlock()
    }

    deinit {
        invalidate()
    }

    // MARK: - Lifecycle Management

    /// Invalidate the context and all associated values
    private func invalidate() {
        guard isValid else { return }
        isValid = false

        // Unregister from context registry
        unregisterFromContextRegistry()

        // Clear native functions
        nativeFunctions.removeAll()

        // Invalidate all live values first
        for value in liveValues.allObjects {
            value.invalidate()
        }
        liveValues.removeAllObjects()

        // Free context (triggers GC cleanup and finalizers)
        JS_FreeContext(ctx)

        // Memory buffer deallocates automatically in deinit
    }

    // MARK: - Native Function Handling

    /// Handle a native function call from JavaScript
    private func handleNativeCall(functionId: Int32, argc: Int32, argv: UnsafeMutablePointer<JSValue>?) -> JSValue {
        // Look up the function
        guard let function = nativeFunctions[functionId] else {
            _ = mqjs_throw_internal_error(ctx, "Native function not found")
            return mqjs_get_exception()
        }

        // Convert arguments to MQJSValue array
        var args: [MQJSValue] = []
        if let argv = argv, argc > 0 {
            for i in 0..<Int(argc) {
                let jsValue = argv[i]
                args.append(MQJSValue(context: self, jsValue: jsValue))
            }
        }

        // Call the Swift function
        do {
            let result = try function(args)

            // Convert result back to JSValue
            if let result = result {
                if let jsValue = result as? MQJSValue {
                    return jsValue.jsValue
                } else {
                    // Convert Swift value to JS
                    let converted = try convertToJSValue(result)
                    return converted.jsValue
                }
            } else {
                return mqjs_get_undefined()
            }
        } catch {
            // Throw JS error
            let message = "\(error)"
            _ = mqjs_throw_internal_error(ctx, message)
            return mqjs_get_exception()
        }
    }

    /// Convert a Swift value to MQJSValue
    private func convertToJSValue(_ value: Any) throws -> MQJSValue {
        switch value {
        case let jsValue as MQJSValue:
            return jsValue
        case let boolValue as Bool:
            return try boolValue.toJSValue(in: self)
        case let intValue as Int:
            return try intValue.toJSValue(in: self)
        case let int32Value as Int32:
            return try int32Value.toJSValue(in: self)
        case let doubleValue as Double:
            return try doubleValue.toJSValue(in: self)
        case let stringValue as String:
            return try stringValue.toJSValue(in: self)
        case let arrayValue as [Any]:
            // Convert array elements recursively
            let jsArray = JS_NewArray(ctx, Int32(arrayValue.count))
            let arrayWrapper = MQJSValue(context: self, jsValue: jsArray)
            for (index, element) in arrayValue.enumerated() {
                arrayWrapper[index] = try convertToJSValue(element)
            }
            return arrayWrapper
        case let dictValue as [String: Any]:
            // Convert dictionary entries recursively
            let jsObject = JS_NewObject(ctx)
            let objectWrapper = MQJSValue(context: self, jsValue: jsObject)
            for (key, element) in dictValue {
                objectWrapper[key] = try convertToJSValue(element)
            }
            return objectWrapper
        default:
            throw MQJSError.typeConversionError("Cannot convert \(type(of: value)) to JavaScript value")
        }
    }

    // MARK: - Value Tracking (Internal)

    /// Register a value with the context for lifecycle tracking
    internal func registerValue(_ value: MQJSValue) {
        liveValues.add(value)
    }

    /// Unregister a value from the context
    internal func unregisterValue(_ value: MQJSValue) {
        // NSHashTable with weak references handles this automatically
    }

    // MARK: - Global Object

    /// The JavaScript global object.
    ///
    /// Use this to access or set global variables:
    /// ```swift
    /// context.globalObject["myVar"] = try 42.toJSValue(in: context)
    /// let value = context.globalObject["Math"]
    /// ```
    public var globalObject: MQJSValue {
        let jsValue = JS_GetGlobalObject(ctx)
        return MQJSValue(context: self, jsValue: jsValue)
    }

    // MARK: - Error Handling (Internal)

    /// Extract error message from context after an exception
    internal func extractError() throws -> MQJSError {
        var buffer = [CChar](repeating: 0, count: 1024)
        _ = JS_GetErrorStr(ctx, &buffer, 1024)
        let errorMessage = String(cString: buffer)
        return .evaluationError(errorMessage)
    }

    // MARK: - Script Execution

    /// Evaluates JavaScript code and returns the result.
    ///
    /// ```swift
    /// let result = try context.eval("1 + 2")
    /// print(try result.toInt32()) // 3
    ///
    /// let obj = try context.eval("({ name: 'Alice', age: 30 })")
    /// print(try obj["name"]?.toString()) // "Alice"
    /// ```
    ///
    /// - Parameters:
    ///   - script: The JavaScript code to evaluate
    ///   - filename: Optional filename for error messages (default: "<eval>")
    ///   - flags: Evaluation flags (default: returns last value)
    /// - Returns: The result of evaluating the script
    /// - Throws: MQJSError if evaluation fails or produces an exception
    @discardableResult
    public func eval(
        _ script: String,
        filename: String = "<eval>",
        flags: Int32 = JS_EVAL_RETVAL
    ) throws -> MQJSValue {
        try checkValid()

        let result = script.withCString { scriptCStr in
            filename.withCString { filenameCStr in
                JS_Eval(
                    ctx,
                    scriptCStr,
                    script.utf8.count,
                    filenameCStr,
                    flags
                )
            }
        }

        // Check for exception
        if JS_IsException(result) != 0 {
            throw try extractError()
        }

        return MQJSValue(context: self, jsValue: result)
    }

    /// Parses JavaScript code without executing it (for compilation).
    ///
    /// - Parameters:
    ///   - script: The JavaScript code to parse
    ///   - filename: Optional filename for error messages
    ///   - flags: Parse flags
    /// - Returns: A compiled function that can be executed with run()
    /// - Throws: MQJSError if parsing fails
    public func parse(
        _ script: String,
        filename: String = "<parse>",
        flags: Int32 = JS_EVAL_RETVAL
    ) throws -> MQJSValue {
        try checkValid()

        let result = script.withCString { scriptCStr in
            filename.withCString { filenameCStr in
                JS_Parse(
                    ctx,
                    scriptCStr,
                    script.utf8.count,
                    filenameCStr,
                    flags
                )
            }
        }

        if JS_IsException(result) != 0 {
            throw try extractError()
        }

        return MQJSValue(context: self, jsValue: result)
    }

    /// Runs a previously parsed JavaScript function.
    ///
    /// - Parameter compiledFunction: A function returned by parse()
    /// - Returns: The result of executing the function
    /// - Throws: MQJSError if execution fails
    @discardableResult
    public func run(_ compiledFunction: MQJSValue) throws -> MQJSValue {
        try checkValid()

        let result = JS_Run(ctx, compiledFunction.jsValue)

        if JS_IsException(result) != 0 {
            throw try extractError()
        }

        return MQJSValue(context: self, jsValue: result)
    }

    /// Manually triggers garbage collection.
    ///
    /// This is normally not needed as mquickjs handles GC automatically,
    /// but can be useful for testing or controlling memory usage.
    public func collectGarbage() {
        JS_GC(ctx)
    }

    // MARK: - Native Function Registration

    /// Registers a Swift function that can be called from JavaScript.
    ///
    /// The function receives an array of `MQJSValue` arguments and can return
    /// any Swift value that can be converted to JavaScript (Int, Double, String,
    /// Bool, Array, Dictionary, or MQJSValue).
    ///
    /// ```swift
    /// // Register a simple function
    /// try context.setFunction("greet") { args in
    ///     let name = try args[0].toString()
    ///     return "Hello, \(name)!"
    /// }
    ///
    /// // Call from JavaScript
    /// let result = try context.eval("greet('World')")
    /// print(try result.toString()) // "Hello, World!"
    ///
    /// // Register a function that uses multiple arguments
    /// try context.setFunction("add") { args in
    ///     let a = try args[0].toInt32()
    ///     let b = try args[1].toInt32()
    ///     return a + b
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the function in JavaScript's global scope
    ///   - function: The Swift closure to call when the function is invoked
    /// - Throws: MQJSError if registration fails
    public func setFunction(_ name: String, _ function: @escaping NativeFunction) throws {
        try checkValid()

        // Generate unique function ID
        let functionId = nextFunctionId
        nextFunctionId += 1

        // Store the function
        nativeFunctions[functionId] = function

        // Create the JS function
        let jsFunction = mqjs_new_native_function(ctx, functionId)

        if JS_IsException(jsFunction) != 0 {
            nativeFunctions.removeValue(forKey: functionId)
            throw try extractError()
        }

        // Set it on the global object
        let jsFunctionValue = MQJSValue(context: self, jsValue: jsFunction)
        globalObject[name] = jsFunctionValue
    }

    /// Registers a Swift function on a specific object.
    ///
    /// ```swift
    /// let myObj = try context.eval("({ value: 10 })")
    /// try context.setFunction("double", on: myObj) { args in
    ///     // 'this' is not directly available, but you can pass the object
    ///     return 42
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the function property
    ///   - object: The object to set the function on
    ///   - function: The Swift closure to call when the function is invoked
    /// - Throws: MQJSError if registration fails
    public func setFunction(_ name: String, on object: MQJSValue, _ function: @escaping NativeFunction) throws {
        try checkValid()

        let functionId = nextFunctionId
        nextFunctionId += 1

        nativeFunctions[functionId] = function

        let jsFunction = mqjs_new_native_function(ctx, functionId)

        if JS_IsException(jsFunction) != 0 {
            nativeFunctions.removeValue(forKey: functionId)
            throw try extractError()
        }

        let jsFunctionValue = MQJSValue(context: self, jsValue: jsFunction)
        object[name] = jsFunctionValue
    }

    // MARK: - JSC Compatibility

    /// Evaluates JavaScript code and returns the result.
    ///
    /// This is an alias for `eval(_:)` to match JavaScriptCore's naming convention.
    ///
    /// ```swift
    /// let result = try context.evaluateScript("1 + 2")
    /// print(try result.toInt32()) // 3
    /// ```
    @discardableResult
    public func evaluateScript(_ script: String) throws -> MQJSValue {
        return try eval(script)
    }

    /// Calls a global function by name.
    ///
    /// This is a convenience method for invoking global functions.
    ///
    /// ```swift
    /// try context.eval("function add(a, b) { return a + b; }")
    /// let result = try context.callFunction("add", withArguments: [5, 3])
    /// print(try result.toInt32()) // 8
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the global function to call
    ///   - arguments: Arguments to pass to the function
    /// - Returns: The return value from the function
    /// - Throws: `MQJSError.evaluationError` if function not found,
    ///           `MQJSError.notAFunction` if the global is not a function
    public func callFunction(_ name: String, withArguments arguments: [Any]? = nil) throws -> MQJSValue {
        guard let function = globalObject[name] else {
            throw MQJSError.evaluationError("Function '\(name)' not found")
        }
        guard function.isFunction else {
            throw MQJSError.notAFunction
        }
        return try function.call(withArguments: arguments)
    }

    // MARK: - Validation

    /// Check if the context is still valid
    internal func checkValid() throws {
        guard isValid else {
            throw MQJSError.invalidContext
        }
    }
}
