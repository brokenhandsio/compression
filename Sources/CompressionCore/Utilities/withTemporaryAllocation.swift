#if swift(<6.4)
@usableFromInline
@discardableResult
package func withTemporaryAllocation<T: ~Copyable, R: ~Copyable, E: Error>(
    of type: T.Type,
    capacity: Int,
    _ body: (inout OutputSpan<T>) throws(E) -> R
) throws(E) -> R where T: ~Copyable, R: ~Copyable {
    try unsafe withUnsafeTemporaryAllocation(of: type, capacity: capacity) { (buffer) throws(E) in
        var span = unsafe OutputSpan(buffer: buffer, initializedCount: 0)
        defer {
            let initializedCount = unsafe span.finalize(for: buffer)
            span = OutputSpan()
            unsafe buffer.extracting(..<initializedCount).deinitialize()
        }

        return try body(&span)
    }
}
#endif
