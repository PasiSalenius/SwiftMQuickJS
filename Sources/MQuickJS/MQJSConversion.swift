import Foundation
import CMQuickJS

// MARK: - Conversion Protocols

/// Types that can be converted to JavaScript values.
public protocol MQJSConvertible {
    /// Converts this value to a JavaScript value in the given context.
    func toJSValue(in context: MQJSContext) throws -> MQJSValue
}

/// Types that can be created from JavaScript values.
public protocol MQJSInitializable {
    /// Creates an instance from a JavaScript value.
    init(from jsValue: MQJSValue) throws
}

// MARK: - Integer Conversions

extension Int: MQJSConvertible {
    public func toJSValue(in context: MQJSContext) throws -> MQJSValue {
        try context.checkValid()
        let jsVal = JS_NewInt32(context.ctx, Int32(self))
        return MQJSValue(context: context, jsValue: jsVal)
    }
}

extension Int: MQJSInitializable {
    public init(from jsValue: MQJSValue) throws {
        self = Int(try jsValue.toInt32())
    }
}

extension Int32: MQJSConvertible {
    public func toJSValue(in context: MQJSContext) throws -> MQJSValue {
        try context.checkValid()
        let jsVal = JS_NewInt32(context.ctx, self)
        return MQJSValue(context: context, jsValue: jsVal)
    }
}

extension Int32: MQJSInitializable {
    public init(from jsValue: MQJSValue) throws {
        self = try jsValue.toInt32()
    }
}

extension UInt32: MQJSConvertible {
    public func toJSValue(in context: MQJSContext) throws -> MQJSValue {
        try context.checkValid()
        let jsVal = JS_NewUint32(context.ctx, self)
        return MQJSValue(context: context, jsValue: jsVal)
    }
}

extension UInt32: MQJSInitializable {
    public init(from jsValue: MQJSValue) throws {
        var result: UInt32 = 0
        guard let ctx = jsValue.context else { throw MQJSError.invalidContext }
        let status = JS_ToUint32(ctx.ctx, &result, jsValue.jsValue)
        if status != 0 {
            throw try ctx.extractError()
        }
        self = result
    }
}

// MARK: - Floating Point Conversions

extension Double: MQJSConvertible {
    public func toJSValue(in context: MQJSContext) throws -> MQJSValue {
        try context.checkValid()
        let jsVal = JS_NewFloat64(context.ctx, self)
        return MQJSValue(context: context, jsValue: jsVal)
    }
}

extension Double: MQJSInitializable {
    public init(from jsValue: MQJSValue) throws {
        self = try jsValue.toDouble()
    }
}

extension Float: MQJSConvertible {
    public func toJSValue(in context: MQJSContext) throws -> MQJSValue {
        try context.checkValid()
        let jsVal = JS_NewFloat64(context.ctx, Double(self))
        return MQJSValue(context: context, jsValue: jsVal)
    }
}

extension Float: MQJSInitializable {
    public init(from jsValue: MQJSValue) throws {
        self = Float(try jsValue.toDouble())
    }
}

// MARK: - String Conversions

extension String: MQJSConvertible {
    public func toJSValue(in context: MQJSContext) throws -> MQJSValue {
        try context.checkValid()
        let jsVal = self.withCString { cStr in
            JS_NewString(context.ctx, cStr)
        }
        return MQJSValue(context: context, jsValue: jsVal)
    }
}

extension String: MQJSInitializable {
    public init(from jsValue: MQJSValue) throws {
        self = try jsValue.toString()
    }
}

// MARK: - Boolean Conversions

extension Bool: MQJSConvertible {
    public func toJSValue(in context: MQJSContext) throws -> MQJSValue {
        try context.checkValid()
        let jsVal = self ? mqjs_get_true() : mqjs_get_false()
        return MQJSValue(context: context, jsValue: jsVal)
    }
}

extension Bool: MQJSInitializable {
    public init(from jsValue: MQJSValue) throws {
        guard let value = jsValue.toBool() else {
            throw MQJSError.typeConversionError("Value is not a boolean")
        }
        self = value
    }
}

// MARK: - Array Conversions

extension Array: MQJSConvertible where Element: MQJSConvertible {
    public func toJSValue(in context: MQJSContext) throws -> MQJSValue {
        try context.checkValid()
        let jsArray = JS_NewArray(context.ctx, Int32(count))
        let arrayValue = MQJSValue(context: context, jsValue: jsArray)

        for (index, element) in enumerated() {
            let jsElement = try element.toJSValue(in: context)
            arrayValue[index] = jsElement
        }

        return arrayValue
    }
}

extension Array: MQJSInitializable where Element: MQJSInitializable {
    public init(from jsValue: MQJSValue) throws {
        guard jsValue.isObject else {
            throw MQJSError.typeConversionError("Value is not an array")
        }

        guard jsValue.context != nil else {
            throw MQJSError.invalidContext
        }

        // Get array length
        guard let lengthValue = jsValue["length"],
              let length = try? lengthValue.toInt32() else {
            throw MQJSError.typeConversionError("Cannot get array length")
        }

        var result: [Element] = []
        result.reserveCapacity(Int(length))

        for i in 0..<Int(length) {
            guard let elementValue = jsValue[i] else {
                throw MQJSError.typeConversionError("Cannot access array element at index \(i)")
            }
            let element = try Element(from: elementValue)
            result.append(element)
        }

        self = result
    }
}

// MARK: - Dictionary Conversions

extension Dictionary: MQJSConvertible where Key == String, Value: MQJSConvertible {
    public func toJSValue(in context: MQJSContext) throws -> MQJSValue {
        try context.checkValid()
        let jsObject = JS_NewObject(context.ctx)
        let objectValue = MQJSValue(context: context, jsValue: jsObject)

        for (key, value) in self {
            let jsValue = try value.toJSValue(in: context)
            objectValue[key] = jsValue
        }

        return objectValue
    }
}

extension Dictionary: MQJSInitializable where Key == String, Value: MQJSInitializable {
    public init(from jsValue: MQJSValue) throws {
        guard jsValue.isObject else {
            throw MQJSError.typeConversionError("Value is not an object")
        }

        // Note: mquickjs doesn't provide a standard way to enumerate object properties
        // This is a limitation - users would need to know the keys in advance
        // For a complete implementation, we'd need to add property enumeration to the C bridge
        throw MQJSError.typeConversionError("Dictionary conversion from JSValue not fully supported - property enumeration not available in mquickjs")
    }
}

// MARK: - Optional Conversions

extension Optional: MQJSConvertible where Wrapped: MQJSConvertible {
    public func toJSValue(in context: MQJSContext) throws -> MQJSValue {
        try context.checkValid()

        switch self {
        case .none:
            let jsVal = mqjs_get_null()
            return MQJSValue(context: context, jsValue: jsVal)
        case .some(let value):
            return try value.toJSValue(in: context)
        }
    }
}

extension Optional: MQJSInitializable where Wrapped: MQJSInitializable {
    public init(from jsValue: MQJSValue) throws {
        if jsValue.isNull || jsValue.isUndefined {
            self = .none
        } else {
            self = .some(try Wrapped(from: jsValue))
        }
    }
}

// MARK: - Convenience Methods on MQJSContext

extension MQJSContext {
    /// Creates a JavaScript value from a Swift value.
    ///
    /// ```swift
    /// let numValue = try context.createValue(42)
    /// let strValue = try context.createValue("Hello")
    /// let arrValue = try context.createValue([1, 2, 3])
    /// ```
    public func createValue<T: MQJSConvertible>(_ value: T) throws -> MQJSValue {
        return try value.toJSValue(in: self)
    }

    /// Extracts a Swift value from a JavaScript value.
    ///
    /// ```swift
    /// let jsValue = try context.eval("42")
    /// let number: Int = try context.extract(jsValue)
    /// ```
    public func extract<T: MQJSInitializable>(_ jsValue: MQJSValue) throws -> T {
        return try T(from: jsValue)
    }
}
