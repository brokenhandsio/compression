# Compression

[![Swift 6.3](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)](https://www.swift.org)

This is a compression package for Swift which supports multiple algorithms and is aimed to be used on any Swift-compatible platform.

> [!Important] 
> This package is still under development and the API may change in future releases.
> Use at your own risk.


## Getting Started

To use the package, add the following to your `Package.swift` file:

```swift
.package(url: "https://github.com/brokenhandsio/compression.git", branch: "main")
```

Then, in your target, you can add whatever product fits your needs:

Product | Description
--- | ---
`CompressionCore` | Core compression and decompression functionality
`CompressionDeflate` | Gzip and Deflate codecs via zlib
`CompressionZstd` | Zstandard codec via zstd
`CompressionFoundationCompat` | Compression functionality compatibility layer for Foundation APIs

## Usage

Start with importing the product with whatever algorithm you intend to use, for example:

```swift
import CompressionZstd
```

### One-shot Compression

A number of APIs are provided for different use cases. For simplicity, you can start with the `[UInt8]` returning API:

```swift
let data = Array("The quick brown fox jumps over the lazy dog.".utf8)
let compressor = Deflate.Compressor(configuration: .default)
let compressed = try compressor.compress(data)
```

This API is based on `OutputSpan` APIs which you can drop down to as well if performance is a concern:

```swift
let data = Array("The quick brown fox jumps over the lazy dog.".utf8)
let compressor = Deflate.Compressor()
let capacity = compressor.upperBound(forInputSize: data.count)
let compressed = try [UInt8](capacity: capacity) { output in
    try compressor.compress(data, into: &output)
}
```

### Streaming Compression

Streaming compression allows you to compress data in chunks, which is useful for large data streams or when you don't have all the data available at once, for example when reading from a file or network stream.

```swift
let data = Array("The quick brown fox jumps over the lazy dog.".utf8)
let compressor = Zstd.StreamingCompressor(configuration: .default)
var output: OutputSpan<UInt8> = ...
var result = try compressor.compress(data.span, into: &output)
switch result.status {
    case .awaitingInput: break // The compressor is waiting for more input data
    case .needsOutput: break // The compressor needs more output space to continue
    case .finished: break // Compression has finished successfully
}
try compressor.finish(into: &output)
```

> [!Important]
> Remember to always call `finish()` after compressing all input data to ensure that the compression is properly finalized. To re-use the compressor for a new stream, call `reset()` first.

### Async Sequences

The package also provide de/compression `AsyncSequence`s based on the streaming APIs, allowing you to process data asynchronously in a sequence of chunks.

```swift
let data: AsyncStream<[UInt8]> = ...
let decompressed = data.decompressed(using: .zstd(maxDecompressedSize: 10 * 1024))
var output: [UInt8] = []

for try await chunk in decompressed {
    output.append(contentsOf: chunk)
}
```

> [!Note]
> The AsyncSequence APIs are currently not available on Embedded platforms.
