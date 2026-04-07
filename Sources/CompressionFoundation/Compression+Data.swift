import CompressionCore

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

extension Data: CompressionCore.CompressibleInput {
    public func withSpan<R>(_ body: (Span<UInt8>) throws -> R) rethrows -> R {
        try body(self.span)
    }
}
