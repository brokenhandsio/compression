extension Array where Element == UInt8 {
    // TODO: replace with proper Span append when available
    @unsafe package mutating func append(span: Span<UInt8>) {
        unsafe span.withUnsafeBufferPointer { ptr in
            unsafe append(contentsOf: ptr)
        }
    }
}
