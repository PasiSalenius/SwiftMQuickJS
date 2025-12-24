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
    }

    deinit {
        invalidate()
    }

    // MARK: - Lifecycle Management

    /// Invalidate the context and all associated values
    private func invalidate() {
        guard isValid else { return }
        isValid = false

        // Invalidate all live values first
        for value in liveValues.allObjects {
            value.invalidate()
        }
        liveValues.removeAllObjects()

        // Free context (triggers GC cleanup and finalizers)
        JS_FreeContext(ctx)

        // Memory buffer deallocates automatically in deinit
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
