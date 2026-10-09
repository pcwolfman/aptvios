import Foundation
import Compression

enum Gzip {
    static func decompress(_ data: Data) throws -> Data {
        guard data.count > 18, data[0] == 0x1f, data[1] == 0x8b else {
            return data
        }

        var offset = 10
        let flags = data[3]
        if flags & 0x04 != 0 {
            guard offset + 2 <= data.count else { throw AptviosError.parseFailed("gzip") }
            let xlen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + xlen
        }
        if flags & 0x08 != 0 {
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 {
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 {
            offset += 2
        }

        guard offset + 8 < data.count else { throw AptviosError.parseFailed("gzip truncated") }
        let compressed = data.subdata(in: offset..<(data.count - 8))

        var capacity = max(data.count * 16, 256 * 1024)
        for _ in 0..<6 {
            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            defer { destinationBuffer.deallocate() }

            let decodedCount = compressed.withUnsafeBytes { srcBuffer -> Int in
                guard let src = srcBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationBuffer,
                    capacity,
                    src,
                    compressed.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }

            if decodedCount > 0 {
                return Data(bytes: destinationBuffer, count: decodedCount)
            }
            capacity *= 2
        }

        throw AptviosError.parseFailed("gzip inflate failed")
    }
}
