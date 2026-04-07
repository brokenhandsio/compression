public protocol CompressibleInput: Collection where Element == UInt8 {
    func withSpan<R>(_ body: (Span<UInt8>) throws -> R) rethrows -> R
}

extension [UInt8]: CompressibleInput {
    public func withSpan<R>(_ body: (Span<UInt8>) throws -> R) rethrows -> R {
        try body(self.span)
    }
}

extension ArraySlice<UInt8>: CompressibleInput {
    public func withSpan<R>(_ body: (Span<UInt8>) throws -> R) rethrows -> R {
        try body(self.span)
    }
}
