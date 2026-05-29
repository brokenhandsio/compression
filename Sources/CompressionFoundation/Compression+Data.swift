#if !hasFeature(Embedded)
import CompressionCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Data: CompressionCore.CompressibleInput {
    public func withSpan<R, E: Error>(_ body: (Span<UInt8>) throws(E) -> R) throws(E) -> R {
        try body(self.span)
    }
}
#endif
