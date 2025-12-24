import Foundation
import CMQuickJS

/// Builder for defining a Swift class to expose to JavaScript.
///
/// Use this builder to define the constructor and methods for a class
/// that will be accessible from JavaScript via the `new` keyword.
///
/// ```swift
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
/// ```
public final class MQJSClassBuilder<T: AnyObject> {
    // MARK: - Type Aliases

    /// Constructor function type: receives JS arguments, returns Swift instance
    public typealias Constructor = ([MQJSValue]) throws -> T

    /// Method function type: receives Swift instance and JS arguments, returns value
    public typealias Method = (T, [MQJSValue]) throws -> Any?

    // MARK: - Stored Definitions

    /// The constructor function for creating instances
    internal var constructorFn: Constructor?

    /// Dictionary of method name to method implementation
    internal var methods: [String: Method] = [:]

    // MARK: - Builder Methods

    /// Define the constructor for this class.
    ///
    /// The constructor is called when JavaScript uses `new ClassName(args)`.
    ///
    /// ```swift
    /// builder.constructor { args in
    ///     let name = try args.first?.toString() ?? "default"
    ///     return MyClass(name: name)
    /// }
    /// ```
    ///
    /// - Parameter fn: A closure that receives JavaScript arguments and returns a new instance
    @discardableResult
    public func constructor(_ fn: @escaping Constructor) -> Self {
        self.constructorFn = fn
        return self
    }

    /// Define a method for this class.
    ///
    /// Methods are callable on instances created with `new`.
    ///
    /// ```swift
    /// builder.method("getValue") { this, args in
    ///     return this.value
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - name: The method name as it appears in JavaScript
    ///   - fn: A closure that receives the Swift instance and JavaScript arguments
    @discardableResult
    public func method(_ name: String, _ fn: @escaping Method) -> Self {
        self.methods[name] = fn
        return self
    }
}
