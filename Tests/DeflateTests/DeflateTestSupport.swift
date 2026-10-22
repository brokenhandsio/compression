import CompressionDeflate

/// Deterministic pseudo-random bytes
func pseudoRandomBytes(count: Int, seed: UInt64 = 0x5DEE_CE66_D000_0001) -> [UInt8] {
    var state = seed
    return (0..<count).map { _ in
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return UInt8(truncatingIfNeeded: state >> 33)
    }
}
