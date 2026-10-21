import CZstd
public import CompressionCore

extension Zstd: OneShotDecompressionAlgorithm {
    public struct Decompressor: CompressionCore.Decompressor {
        public let configuration: ZstdDecompressionConfiguration

        public init(configuration: DecompressionConfiguration = .default) {
            self.configuration = configuration
        }

        public func decompress(_ input: some CompressibleInput) throws(Zstd.Error) -> [UInt8] {
            try input.withSpan { inputSpan throws(Zstd.Error) in
                let declared = try getDecompressedSize(from: inputSpan)

                if declared != ZSTD_CONTENTSIZE_UNKNOWN, let capacity = Int(exactly: declared) {
                    if let max = configuration.maxDecompressedSize, capacity > Int(max) {
                        throw .maxDecompressedSizeExceeded
                    }

                    return try [UInt8](capacity: capacity) { output throws(Zstd.Error) in
                        try decompress(inputSpan, into: &output)
                    }
                }

                // If we have no declared size, which is usual for streamed inputs,
                // use the streaming decompressor
                var decompressor = Zstd.StreamingDecompressor(configuration: configuration)
                var output = [UInt8]()
                try decompressor.decompress(inputSpan) { chunk in output.append(span: chunk) }
                guard decompressor.isFinished else { throw .truncatedInput }
                return output
            }
        }

        func getDecompressedSize(from span: Span<UInt8>) throws(Zstd.Error) -> UInt64 {
            guard !span.isEmpty else { throw .corruptData }
            var totalSize: UInt64 = 0
            var i = 0
            // if there's joint frames we need to traverse them all and sum their contentSize
            while i < span.count {
                let remaining = span.extracting(i...)
                let frameLength = try Zstd.check(CZstd_findFrameCompressedSize(remaining))
                guard frameLength > 0, frameLength <= remaining.count else { throw .corruptData }

                let contentSize = CZstd_getFrameContentSize(remaining)
                guard contentSize != ZSTD_CONTENTSIZE_ERROR else { throw .corruptData }
                guard contentSize != ZSTD_CONTENTSIZE_UNKNOWN else { return contentSize }

                let (sum, overflow) = totalSize.addingReportingOverflow(contentSize)
                guard !overflow else { throw .corruptData }

                totalSize = sum
                i += frameLength
            }

            return totalSize
        }

        public func decompress(_ input: some CompressionCore.CompressibleInput, into output: inout OutputSpan<UInt8>) throws(Zstd.Error) {
            try input.withSpan { inputSpan throws(Zstd.Error) in
                try decompress(inputSpan, into: &output)
            }
        }

        public func decompress(_ input: Span<UInt8>, into output: inout OutputSpan<UInt8>) throws(Zstd.Error) {
            guard let dctx = unsafe ZSTD_createDCtx() else { throw .insufficientMemory }
            defer { _ = unsafe ZSTD_freeDCtx(dctx) }

            unsafe try Zstd.check(ZSTD_DCtx_setParameter(dctx, ZSTD_d_windowLogMax, configuration.effectiveWindowLogMax))

            try unsafe output.withUnsafeMutableBufferPointer { outputPtr, initCount throws(Zstd.Error) in
                var dst = unsafe MutableSpan(_unsafeElements: outputPtr.extracting(initCount...))
                let status = unsafe CZstd_decompressDCtx(dctx, &dst, input)
                try Zstd.check(status)

                initCount += status
            }
        }
    }
}
