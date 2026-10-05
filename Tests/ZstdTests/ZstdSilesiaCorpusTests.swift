import CZstd
import Testing

@testable import Zstandard

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
        .deletingLastPathComponent()  // ZstdTests/
        .deletingLastPathComponent()  // Tests/
        .appendingPathComponent("Fixtures/Silesia")
        .path
}()

private let silesiaCorpusAvailable: Bool = {
    FileManager.default.fileExists(atPath: silesiaCorpusDir + "/dickens")
}()

@Suite("Zstd Silesia Corpus", .disabled(if: !silesiaCorpusAvailable, "Silesia corpus not found"))
struct ZstdSilesiaCorpusTests {
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

    private let decompressor = Zstd.Decompressor(configuration: .default)

    @Test("Round-trip", arguments: files)
    func roundTrip(file: String) throws {
        let input = try loadFile(file)
        let compressed = try Zstd.Compressor(configuration: .default).compress(input)

        #expect(compressed.count < input.count, "corpus files should compress")
        #expect(frameContentSize(of: compressed) == input.count)
        #expect(try decompressor.decompress(compressed) == input)
    }

    @Test("Round-trip at level 1", arguments: files)
    func roundTripFastLevel(file: String) throws {
        let input = try loadFile(file)
        let c = Zstd.Compressor(configuration: .init(strategy: .fast, level: 1))
        #expect(try decompressor.decompress(c.compress(input)) == input)
    }
}
