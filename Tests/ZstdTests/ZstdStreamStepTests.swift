import CompressionCore
import CompressionZstd
import Testing

@Suite("Zstd StreamStep")
struct ZstdStreamStepTests {
    /// Every step's status must match what it reports:
    /// `.awaitingInput` used all input, `.outputIsFull` left no room, `.finished` ended the stream.
    @Test("Each status means what it says", arguments: [1, 7, 4_096], [16, 4_096, 64 * 1_024])
    func statusContract(chunkSize: Int, outputSize: Int) throws {
        let input = pseudoRandomBytes(count: 50_000) + [UInt8](repeating: 0x41, count: 50_000)
        var rounds = 0

        var compressor = Zstd.StreamingCompressor()
        var compressed = [UInt8]()
        for start in stride(from: 0, to: input.count, by: chunkSize) {
            let end = min(start + chunkSize, input.count)
            var offset = start
            var status = StreamStep.Status.outputIsFull
            while status == .outputIsFull {
                rounds += 1
                try #require(rounds < 5_000_000, "no progress")
                compressed += try [UInt8](capacity: outputSize) { out throws(Zstd.Error) in
                    let chunk = input.span.extracting(offset..<end)
                    let step = try compressor.compress(chunk, into: &out)
                    switch step.status {
                    case .awaitingInput: #expect(step.consumed == chunk.count)
                    case .outputIsFull:
                        let full = out.isFull
                        #expect(full)
                    case .finished: Issue.record("compress must not end the stream")
                    }
                    offset += step.consumed
                    status = step.status
                }
            }

            if start == input.count / 2 {
                status = .outputIsFull
                while status == .outputIsFull {
                    compressed += try [UInt8](capacity: outputSize) { out throws(Zstd.Error) in
                        status = try compressor.flush(into: &out)
                        #expect(status != .finished, "flush must not end the stream")
                        if status == .outputIsFull {
                            let full = out.isFull
                            #expect(full)
                        }
                    }
                }
            }
        }

        var finishStatus = StreamStep.Status.outputIsFull
        while finishStatus == .outputIsFull {
            compressed += try [UInt8](capacity: outputSize) { out throws(Zstd.Error) in
                finishStatus = try compressor.finish(into: &out)
                #expect(finishStatus != .awaitingInput, "finish only reports full output or the end")
                if finishStatus == .outputIsFull {
                    let full = out.isFull
                    #expect(full)
                }
            }
        }

        var decompressor = Zstd.StreamingDecompressor()
        var output = [UInt8]()
        var sawFinished = false
        for start in stride(from: 0, to: compressed.count, by: chunkSize) {
            let end = min(start + chunkSize, compressed.count)
            var offset = start
            var status = StreamStep.Status.outputIsFull
            while status == .outputIsFull {
                rounds += 1
                try #require(rounds < 5_000_000, "no progress")
                output += try [UInt8](capacity: outputSize) { out throws(Zstd.Error) in
                    let chunk = compressed.span.extracting(offset..<end)
                    let step = try decompressor.decompress(chunk, into: &out)
                    switch step.status {
                    case .awaitingInput: #expect(step.consumed == chunk.count)
                    case .outputIsFull:
                        let full = out.isFull
                        #expect(full)
                    case .finished:
                        let finished = decompressor.isFinished
                        #expect(finished)
                    }
                    offset += step.consumed
                    status = step.status
                }
            }
            sawFinished = sawFinished || status == .finished
        }

        #expect(sawFinished, "the last step must report .finished")
        #expect(output == input)
    }
}
