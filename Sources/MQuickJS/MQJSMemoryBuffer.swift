import Foundation

/// Manages the pre-allocated memory buffer required by mquickjs engine.
///
/// MQuickJS requires a pre-allocated memory buffer and does not use malloc/free internally.
/// This class handles allocation, alignment, and cleanup of that buffer.
internal final class MQJSMemoryBuffer {
    /// Base address of the allocated memory buffer
    let baseAddress: UnsafeMutableRawPointer

    /// Size of the allocated buffer in bytes
    let size: Int

    /// Minimum recommended memory size: 64KB
    static let minimumSize: Int = 64 * 1024

    /// Creates a new aligned memory buffer of the specified size.
    ///
    /// - Parameter size: Size in bytes (must be at least minimumSize)
    /// - Throws: MQJSError.invalidMemorySize if size is too small or allocation fails
    init(size: Int) throws {
        guard size >= Self.minimumSize else {
            throw MQJSError.invalidMemorySize(size)
        }

        // Allocate aligned memory for optimal performance
        // MQuickJS may require alignment for certain operations
        let alignment = MemoryLayout<Int>.alignment

        #if os(Windows)
        // Windows uses _aligned_malloc
        guard let buffer = _aligned_malloc(size, alignment) else {
            throw MQJSError.contextCreationFailed
        }
        #else
        // POSIX systems use posix_memalign
        var buffer: UnsafeMutableRawPointer?
        let result = posix_memalign(&buffer, alignment, size)
        guard result == 0, let allocatedBuffer = buffer else {
            throw MQJSError.contextCreationFailed
        }
        self.baseAddress = allocatedBuffer
        #endif

        #if os(Windows)
        self.baseAddress = buffer
        #endif

        self.size = size

        // Zero out memory for safety and deterministic behavior
        memset(baseAddress, 0, size)
    }

    deinit {
        // Free the allocated memory
        #if os(Windows)
        _aligned_free(baseAddress)
        #else
        free(baseAddress)
        #endif
    }
}
