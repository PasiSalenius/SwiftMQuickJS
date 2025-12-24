import Foundation

/// Errors that can occur when using the MQuickJS library.
public enum MQJSError: Error, LocalizedError {
    /// The specified memory size is invalid (too small or allocation failed)
    case invalidMemorySize(Int)

    /// Failed to create JavaScript context
    case contextCreationFailed

    /// The JavaScript context is invalid or was deallocated
    case invalidContext

    /// The JavaScript value is invalid
    case invalidValue

    /// Attempted to call a value that is not a function
    case notAFunction

    /// Attempted to access properties on a value that is not an object
    case notAnObject

    /// JavaScript stack overflow during execution
    case stackOverflow

    /// JavaScript evaluation error with message
    case evaluationError(String)

    /// Type conversion error between Swift and JavaScript
    case typeConversionError(String)

    /// Error occurred in native function binding
    case nativeFunctionError(String)

    /// Error occurred during class registration
    case classRegistrationError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMemorySize(let size):
            return "Invalid memory size: \(size) bytes (minimum is \(MQJSMemoryBuffer.minimumSize) bytes)"

        case .contextCreationFailed:
            return "Failed to create JavaScript context"

        case .invalidContext:
            return "JavaScript context is invalid or was deallocated"

        case .invalidValue:
            return "JavaScript value is invalid"

        case .notAFunction:
            return "Value is not a function"

        case .notAnObject:
            return "Value is not an object"

        case .stackOverflow:
            return "JavaScript stack overflow"

        case .evaluationError(let message):
            return "JavaScript evaluation error: \(message)"

        case .typeConversionError(let message):
            return "Type conversion error: \(message)"

        case .nativeFunctionError(let message):
            return "Native function error: \(message)"

        case .classRegistrationError(let message):
            return "Class registration error: \(message)"
        }
    }
}
