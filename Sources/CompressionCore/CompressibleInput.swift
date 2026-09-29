/// A byte source that can expose its contents as a contiguous `Span<UInt8>`.
///
/// `~Escapable` so non-escapable types like `Span<UInt8>` can conform directly.
public protocol CompressibleInput: ~Escapable {
    func withSpan<R, E: Error>(_ body: (Span<UInt8>) throws(E) -> R) throws(E) -> R
}

extension [UInt8]: CompressibleInput {
    public func withSpan<R, E: Error>(_ body: (Span<UInt8>) throws(E) -> R) throws(E) -> R {
        try body(self.span)
    }
}

extension ArraySlice<UInt8>: CompressibleInput {
    public func withSpan<R, E: Error>(_ body: (Span<UInt8>) throws(E) -> R) throws(E) -> R {
        try body(self.span)
    }
}

extension Span<UInt8>: CompressibleInput {
    public func withSpan<R, E: Error>(_ body: (Span<UInt8>) throws(E) -> R) throws(E) -> R {
        try body(self)
    }
}

extension String.UTF8View: CompressibleInput {
    public func withSpan<R, E>(_ body: (Span<UInt8>) throws(E) -> R) throws(E) -> R where E: Error {
        try body(self.span)
    }
}

extension Substring.UTF8View: CompressibleInput {
    public func withSpan<R, E>(_ body: (Span<UInt8>) throws(E) -> R) throws(E) -> R where E: Error {
        try body(self.span)
    }
}

extension ContiguousArray<UInt8>: CompressibleInput {
    public func withSpan<R, E>(_ body: (Span<UInt8>) throws(E) -> R) throws(E) -> R where E: Error {
        try body(self.span)
    }
}

extension InlineArray: CompressibleInput where Element == UInt8 {
    public func withSpan<R, E>(_ body: (Span<UInt8>) throws(E) -> R) throws(E) -> R where E: Error {
        try body(self.span)
    }
}
