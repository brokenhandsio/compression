extension Array where Element == UInt8 {
    // TODO: replace with proper Span append when available
    package mutating func append(span: Span<UInt8>) {
        #if compiler(>=6.4)
        span.withUnsafeBufferPointer { unsafe append(contentsOf: $0) }
        #else
        unsafe span.withUnsafeBufferPointer { unsafe append(contentsOf: $0) }
        #endif
    }
}
