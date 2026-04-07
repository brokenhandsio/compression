import CompressionDeflate
import Testing

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

// Download the corpus and place the files under Tests/Fixtures/Silesia/:
//   curl -L https://sun.aei.polsl.pl//~sdeor/corpus/silesia.zip -o /tmp/silesia.zip
//   mkdir Tests/Fixtures/Silesia
//   unzip /tmp/silesia.zip -d Tests/Fixtures/Silesia/
//
// Tests are disabled when files are absent.

private let silesiaCorpusDir: String = {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // CompressionTests/
        .deletingLastPathComponent()  // Tests/
        .appendingPathComponent("Fixtures/Silesia")
        .path
}()

private let silesiaCorpusAvailable: Bool = {
    FileManager.default.fileExists(atPath: silesiaCorpusDir + "/dickens")
}()

@Suite(.disabled(if: !silesiaCorpusAvailable, "Silesia corpus not found"))
struct SilesiaCorpusTests {
    static let corpusDir = silesiaCorpusDir

    static let files = [
        "dickens", "mozilla", "mr", "nci", "ooffice",
        "osdb", "reymont", "samba", "sao", "webster", "xml", "x-ray",
    ]

    private func loadFile(_ name: String) throws -> [UInt8] {
        let path = Self.corpusDir + "/" + name
        try #require(FileManager.default.fileExists(atPath: path), "Missing: \(path)")
        return try Array(Data(contentsOf: URL(filePath: path)))
    }

    @Test("Round-trip", arguments: files)
    func roundTrip(file: String) throws {
        let input = try loadFile(file)

        let compressor = Deflate.Compressor()
        let decompressor = Deflate.Decompressor()

        let compressed = try compressor.compress(input.span)
        let decompressed = try decompressor.decompress(compressed.span)
        #expect(decompressed == input)
    }

    @Test("Gzip round-trip", arguments: files)
    func gzipRoundTrip(file: String) throws {
        let input = try loadFile(file)
        let c = Deflate.Compressor(configuration: .gzip)
        let d = Deflate.Decompressor(configuration: .gzip)
        #expect(try d.decompress(c.compress(input.span)) == input)
    }
}
