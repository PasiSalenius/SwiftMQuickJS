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

    // MARK: - Custom Class Registration

    /// Registry of Swift object instances keyed by instance ID
    private var instanceRegistry: [Int32: AnyObject] = [:]

    /// Counter for generating unique instance IDs
    private var nextInstanceId: Int32 = 0

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
    private static let nativeCallbackHandler: MQJSNativeCallback = { opaque, functionId, argc, argv, thisVal in
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

        return context.handleNativeCall(functionId: functionId, argc: argc, argv: argv, thisVal: thisVal)
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

        // Clear instance registry (Swift ARC will deallocate objects)
        instanceRegistry.removeAll()

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
    private func handleNativeCall(functionId: Int32, argc: Int32, argv: UnsafeMutablePointer<JSValue>?, thisVal: JSValue) -> JSValue {
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

        // Store thisVal for method calls that need it
        let thisValue = MQJSValue(context: self, jsValue: thisVal)
        currentThisValue = thisValue

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

    /// Current 'this' value during native function calls (for method binding)
    internal var currentThisValue: MQJSValue?

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

    // MARK: - Instance Registry (Internal)

    /// Register a Swift object instance and return its ID
    internal func registerInstance(_ instance: AnyObject) -> Int32 {
        let instanceId = nextInstanceId
        nextInstanceId += 1
        instanceRegistry[instanceId] = instance
        return instanceId
    }

    /// Retrieve a Swift object instance by ID
    internal func getInstance<T: AnyObject>(_ instanceId: Int32, as type: T.Type) -> T? {
        return instanceRegistry[instanceId] as? T
    }

    /// Remove an instance from the registry
    internal func removeInstance(_ instanceId: Int32) {
        instanceRegistry.removeValue(forKey: instanceId)
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

    // MARK: - Custom Class Registration

    /// Hidden property name for storing instance IDs on JavaScript objects
    private static let instanceIdProperty = "__swiftInstanceId__"

    /// Registers a Swift class that can be instantiated from JavaScript.
    ///
    /// Use the builder to define the constructor and methods for the class.
    /// Once registered, JavaScript code can use `new ClassName(args)` to create
    /// instances and call methods on them.
    ///
    /// ```swift
    /// class Counter {
    ///     var value: Int
    ///     init(start: Int) { self.value = start }
    ///     func increment() { value += 1 }
    ///     func getValue() -> Int { return value }
    /// }
    ///
    /// try context.registerClass("Counter") { builder in
    ///     builder.constructor { args in
    ///         let start = try args.first?.toInt32() ?? 0
    ///         return Counter(start: Int(start))
    ///     }
    ///     builder.method("increment") { this, args in
    ///         this.increment()
    ///         return nil
    ///     }
    ///     builder.method("getValue") { this, args in
    ///         return this.getValue()
    ///     }
    /// }
    ///
    /// let result = try context.eval("""
    ///     let c = new Counter(10);
    ///     c.increment();
    ///     c.getValue();  // 11
    /// """)
    /// ```
    ///
    /// - Parameters:
    ///   - name: The class name as it appears in JavaScript
    ///   - configure: A closure that receives a builder to define the class
    /// - Throws: MQJSError if registration fails
    public func registerClass<T: AnyObject>(_ name: String, configure: (MQJSClassBuilder<T>) -> Void) throws {
        try checkValid()

        // Create and configure the builder
        let builder = MQJSClassBuilder<T>()
        configure(builder)

        // Ensure constructor is defined
        guard let constructorFn = builder.constructorFn else {
            throw MQJSError.classRegistrationError("Constructor not defined for class '\(name)'")
        }

        // Create the prototype object with methods
        let prototypeJs = JS_NewObject(ctx)
        let prototype = MQJSValue(context: self, jsValue: prototypeJs)

        // Register each method on the prototype
        for (methodName, methodFn) in builder.methods {
            try registerMethod(methodName, on: prototype, for: T.self, methodFn)
        }

        // Create a native function that initializes instances
        let initFunctionName = "__\(name)_init__"
        let initFunctionId = nextFunctionId
        nextFunctionId += 1

        // The init function receives 'this' and sets it up
        nativeFunctions[initFunctionId] = { [weak self] args in
            guard let self = self else {
                throw MQJSError.invalidContext
            }

            // 'this' is available via currentThisValue
            guard let thisValue = self.currentThisValue else {
                throw MQJSError.nativeFunctionError("Constructor called without 'this' context")
            }

            // Call the Swift constructor
            let instance = try constructorFn(args)

            // Register the instance and get its ID
            let instanceId = self.registerInstance(instance)

            // Store the instance ID on 'this'
            thisValue[Self.instanceIdProperty] = try Int32(instanceId).toJSValue(in: self)

            return nil
        }

        // Create the native init function
        let initFunctionJs = mqjs_new_native_function(ctx, initFunctionId)
        if JS_IsException(initFunctionJs) != 0 {
            nativeFunctions.removeValue(forKey: initFunctionId)
            throw try extractError()
        }

        // Set the init function on global (temporarily)
        let initFunctionValue = MQJSValue(context: self, jsValue: initFunctionJs)
        globalObject[initFunctionName] = initFunctionValue

        // Create a JavaScript constructor function that calls our init function
        // and set up the prototype
        let constructorScript = """
            (function() {
                function \(name)() {
                    \(initFunctionName).apply(this, arguments);
                }
                return \(name);
            })()
        """

        let constructorValue = try eval(constructorScript)

        // Set the prototype with methods on the constructor
        constructorValue["prototype"] = prototype

        // Set the constructor on the global object
        globalObject[name] = constructorValue
    }

    /// Register a method on a prototype object
    private func registerMethod<T: AnyObject>(
        _ name: String,
        on prototype: MQJSValue,
        for type: T.Type,
        _ method: @escaping MQJSClassBuilder<T>.Method
    ) throws {
        let methodId = nextFunctionId
        nextFunctionId += 1

        nativeFunctions[methodId] = { [weak self] args in
            guard let self = self else {
                throw MQJSError.invalidContext
            }

            // Get 'this' from the current call
            guard let thisValue = self.currentThisValue else {
                throw MQJSError.nativeFunctionError("Method called without 'this' context")
            }

            // Get the instance ID from 'this'
            guard let instanceIdValue = thisValue[Self.instanceIdProperty],
                  !instanceIdValue.isUndefined else {
                throw MQJSError.nativeFunctionError("Method called on object without instance ID")
            }

            let instanceId = try instanceIdValue.toInt32()

            // Look up the Swift instance
            guard let instance = self.getInstance(instanceId, as: type) else {
                throw MQJSError.nativeFunctionError("Swift instance not found for ID \(instanceId)")
            }

            // Call the method
            return try method(instance, args)
        }

        // Create the method function
        let methodJs = mqjs_new_native_function(ctx, methodId)
        if JS_IsException(methodJs) != 0 {
            nativeFunctions.removeValue(forKey: methodId)
            throw try extractError()
        }

        let methodValue = MQJSValue(context: self, jsValue: methodJs)
        prototype[name] = methodValue
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
