@preconcurrency @unsafe import CZlib
import CompressionCore

extension Deflate {
    public struct StreamingCompressor: CompressionCore.StreamingCompressor, ~Copyable {
        public let configuration: Deflate.CompressionConfiguration

        @usableFromInline
        let stream: ZStreamBox

        public init(configuration: Configuration = .default) {
            self.configuration = configuration
            self.stream = .init()
            unsafe stream.value.zalloc = nil
            unsafe stream.value.zfree = nil
            unsafe stream.value.opaque = nil

            let rt = unsafe CZlib_deflateInit2(
                &stream.value,
                configuration.level.rawValue,
                CZLIB_Z_DEFLATED,
                configuration.format.windowBits,
                configuration.memory.rawValue,
                configuration.strategy.rawValue,
            )
            precondition(rt == CZLIB_Z_OK, "deflateInit2 failed: \(rt)")
        }

        deinit {
            unsafe CZlib.czlib_z_deflateEnd(&stream.value)
        }

        @inlinable
        public func compress(
            _ chunk: Span<UInt8>,
            into output: inout OutputSpan<UInt8>
        ) throws(Deflate.Error) -> Int {
            guard !output.isFull else { return 0 }

            unsafe stream.value.avail_in = UInt32(chunk.count)
            unsafe stream.value.next_in = CZlib_voidPtr_to_BytefPtr(chunk)

            loop: repeat {
                let status = try deflateStep(flag: CZLIB_Z_NO_FLUSH, into: &output)

                switch status {
                case CZLIB_Z_OK, CZLIB_Z_BUF_ERROR:
                    if output.freeCapacity == 0 {
                        break loop
                    }
                default:
                    throw unsafe .fromZlib(status, message: czlib_z_zError(status))
                }
            } while unsafe (stream.value.avail_in > 0 || stream.value.avail_out == 0)

            return unsafe chunk.count - Int(stream.value.avail_in)
        }

        /// Emit all pending compressed data, aligned to a byte boundary, without ending the stream.
        ///
        /// Returns `true` once the flush is complete. On `false` the output ran out of
        /// space: call again with more room. Keep more than 6 bytes free to avoid
        /// emitting repeated flush markers.
        @inlinable
        @discardableResult
        public func flush(
            into output: inout OutputSpan<UInt8>
        ) throws(Deflate.Error) -> Bool {
            guard output.freeCapacity > 0 else { return false }

            let streamRef = stream
            unsafe streamRef.value.avail_in = 0
            unsafe streamRef.value.next_in = nil
            try deflateStep(flag: CZLIB_Z_SYNC_FLUSH, into: &output)

            // zlib signals a complete flush by leaving output space unused.
            return unsafe streamRef.value.avail_out != 0
        }

        @inlinable
        public func finish(
            into output: inout OutputSpan<UInt8>
        ) throws(Deflate.Error) -> Bool {
            let streamRef = stream
            unsafe streamRef.value.avail_in = 0

            guard !output.isFull else {
                return false
            }

            let status = try deflateStep(flag: CZLIB_Z_FINISH, into: &output)

            return status == CZLIB_Z_STREAM_END
        }

        /// Run a single `deflate` call into the free space of `output`.
        ///
        /// `output` must have free capacity.
        @inlinable
        @discardableResult
        func deflateStep(
            flag: Int32,
            into output: inout OutputSpan<UInt8>
        ) throws(Deflate.Error) -> Int32 {
            let free = output.freeCapacity
            precondition(free > 0, "Output buffer is full")

            let status = unsafe output.withUnsafeMutableBufferPointer { tail, initialisedCount in
                unsafe stream.value.avail_out = UInt32(free)
                unsafe stream.value.next_out = CZlib_voidPtr_to_BytefPtr_mut(tail.baseAddress! + initialisedCount, free)

                let status = unsafe CZlib.czlib_z_deflate(&stream.value, flag)
                initialisedCount += free - Int(unsafe stream.value.avail_out)
                return status
            }

            switch status {
            case CZLIB_Z_OK, CZLIB_Z_BUF_ERROR, CZLIB_Z_STREAM_END:
                return status
            case CZLIB_Z_MEM_ERROR:
                throw .insufficientMemory
            default:
                throw unsafe .fromZlib(status, message: czlib_z_zError(status))
            }
        }
    }
}

extension Deflate.StreamingCompressor {
    /// Emit all pending compressed data, aligned to a byte boundary, without ending the stream.
    ///
    /// The handler may be called zero or more times.
    @inlinable
    public mutating func flush(
        handler: (Span<UInt8>) throws(Deflate.Error) -> Void
    ) throws(Deflate.Error) {
        try withTemporaryAllocation(of: UInt8.self, capacity: Self.outputBufferSize) { output throws(Deflate.Error) in
            var isFlushed: Bool
            repeat {
                isFlushed = try self.flush(into: &output)
                if !output.isEmpty {
                    try handler(output.span)
                    output.removeAll()
                }
            } while !isFlushed
        }
    }
}
