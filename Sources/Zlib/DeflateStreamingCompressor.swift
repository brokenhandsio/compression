@preconcurrency @unsafe import CZlib
import CompressionCore

extension Deflate {
    public struct StreamingCompressor: CompressionCore.StreamingCompressor, ~Copyable {
        public let configuration: Deflate.CompressionConfiguration

        @usableFromInline
        let stream: ZStreamBox

        @usableFromInline
        var output: [UInt8]

        public init(configuration: Configuration) {
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

            output = unsafe .init(unsafeUninitializedCapacity: 32 * 1024) { _, count in
                count = 32 * 1024
            }
        }

        deinit {
            unsafe CZlib.czlib_z_deflateEnd(&stream.value)
        }

        @inlinable
        public mutating func compress(
            _ chunk: Span<UInt8>,
            handler: (Span<UInt8>) throws(Deflate.Error) -> Void
        ) throws(Deflate.Error) {
            let streamRef = stream
            unsafe streamRef.value.avail_in = UInt32(chunk.count)
            unsafe streamRef.value.next_in = CZlib_voidPtr_to_BytefPtr(chunk)
            try drainOutput(flag: CZLIB_Z_NO_FLUSH, handler: handler)
        }

        public mutating func flush(
            handler: (Span<UInt8>) throws(Deflate.Error) -> Void
        ) throws(Deflate.Error) {
            let streamRef = stream
            unsafe streamRef.value.avail_in = 0
            unsafe streamRef.value.next_in = nil
            try drainOutput(flag: CZLIB_Z_SYNC_FLUSH, handler: handler)
        }

        public mutating func finish(
            handler: (Span<UInt8>) throws(Deflate.Error) -> Void
        ) throws(Deflate.Error) {
            let streamRef = stream
            unsafe streamRef.value.avail_in = 0
            var status: Int32 = CZLIB_Z_OK

            while status != CZLIB_Z_STREAM_END {
                var mutableSpan = output.mutableSpan
                unsafe streamRef.value.avail_out = UInt32(mutableSpan.count)
                unsafe streamRef.value.next_out = CZlib_voidPtr_to_BytefPtr_mut(&mutableSpan)
                status = unsafe CZlib.czlib_z_deflate(&streamRef.value, CZLIB_Z_FINISH)
                let produced = mutableSpan.count - Int(unsafe streamRef.value.avail_out)

                switch status {
                case CZLIB_Z_OK, CZLIB_Z_STREAM_END:
                    if produced > 0 {
                        try handler(output.span.extracting(..<produced))
                    }
                case CZLIB_Z_MEM_ERROR:
                    throw Deflate.Error.insufficientMemory
                default:
                    throw unsafe Deflate.Error.fromZlib(status, message: czlib_z_zError(status))
                }
            }
        }

        @inlinable
        mutating func drainOutput(
            flag: Int32,
            handler: (Span<UInt8>) throws(Deflate.Error) -> Void
        ) throws(Deflate.Error) {
            let streamRef = stream
            repeat {
                var mutableSpan = output.mutableSpan
                unsafe streamRef.value.avail_out = UInt32(mutableSpan.count)
                unsafe streamRef.value.next_out = CZlib_voidPtr_to_BytefPtr_mut(&mutableSpan)

                let status = unsafe CZlib.czlib_z_deflate(&streamRef.value, flag)
                let produced = mutableSpan.count - Int(unsafe streamRef.value.avail_out)

                switch status {
                case CZLIB_Z_OK, CZLIB_Z_BUF_ERROR:
                    if produced > 0 {
                        try handler(output.span.extracting(..<produced))
                    }
                case CZLIB_Z_MEM_ERROR:
                    throw .insufficientMemory
                default:
                    throw unsafe .fromZlib(status, message: czlib_z_zError(status))
                }
            } while unsafe (streamRef.value.avail_in > 0 || streamRef.value.avail_out == 0)
        }
    }
}
