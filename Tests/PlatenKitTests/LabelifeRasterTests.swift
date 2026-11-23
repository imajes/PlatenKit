import XCTest
@testable import PlatenKit

final class LabelifeRasterTests: XCTestCase {
    /// Independently expand the LZO1X instructions used by the encoder. Enforce each block's output limit.
    private func expand(_ encoded: [UInt8]) throws -> [UInt8] {
        var index = 0
        var output: [UInt8] = []
        func take() throws -> Int {
            guard index < encoded.count else { throw BenchError("Truncated LZO instruction") }
            defer { index += 1 }
            return Int(encoded[index])
        }
        func extended(base: Int) throws -> Int {
            var length = base
            while true {
                let byte = try take()
                if byte > 0 { return length + byte }
                length += 255
            }
        }
        func copyLiterals(_ count: Int) throws {
            guard count <= 4096 - output.count, count <= encoded.count - index else { throw BenchError("Invalid literal count") }
            output.append(contentsOf: encoded[index..<(index + count)])
            index += count
        }
        if let first = encoded.first, first > 17 { try copyLiterals(try take() - 17) }
        while true {
            switch try take() {
            case 0: try copyLiterals(try extended(base: 18))
            case let n where (1...15).contains(n): try copyLiterals(n + 3)
            case 17:
                let low = try take(), high = try take()
                guard low == 0, high == 0, index == encoded.count else { throw BenchError("Invalid LZO end marker") }
                return output
            case let n where (32...63).contains(n):
                let count = n == 32 ? try extended(base: 33) : (n & 31) + 2
                let low = try take(), high = try take()
                let distance = 1 + ((low | (high << 8)) >> 2)
                guard distance <= output.count, count <= 4096 - output.count else { throw BenchError("Invalid match") }
                for _ in 0..<count { output.append(output[output.count - distance]) }
                try copyLiterals(low & 3)
            default: throw BenchError("Unexpected LZO opcode")
            }
        }
    }

    func testCompressionRoundTripsIncompressibleDataRunsAndTrailingLiterals() throws {
        for size in [1, 2, 3, 4, 5, 17, 18, 19, 32, 33, 34, 35, 237, 238, 239, 254, 255, 256, 273, 274, 4095, 4096] {
            let varied = (0..<size).map { UInt8($0 % 251) }
            let uniform = [UInt8](repeating: 0xff, count: size)
            XCTAssertEqual(try expand(LabelifeRaster.compress(varied)), varied)
            XCTAssertEqual(try expand(LabelifeRaster.compress(uniform)), uniform)
        }
        for count in 0...275 {
            let gap = (0..<count).map { UInt8($0 % 251) }
            let input = [UInt8](repeating: 0x80, count: 12) + gap + [UInt8](repeating: 0xfe, count: 300)
            XCTAssertEqual(try expand(LabelifeRaster.compress(input)), input)
        }
    }

    func testFullFourBySixWireImageAndSimpleIDUseOnePrintCommand() throws {
        let stock = try LabelStock(widthMM: 101.6, heightMM: 152.4)
        let id = "WL-L2-QR-1906"
        let rich = try LabelRenderer.compose(text: id, qrPayload: id, stock: stock)
        let text = try LabelRenderer.textPage(id, stock: stock)
        let jobs = [try LabelJob.image(rich, id: id, model: .labelife, stock: stock),
                    try LabelJob.smoke(id: id, model: .labelife, stock: stock)]
        XCTAssertNotEqual(jobs[0].bytes, jobs[1].bytes)
        for (job, image) in zip(jobs, [rich, text]) {
            let expected = try LabelRenderer.bitmap(from: image, stock: stock)
            XCTAssertTrue(expected.bytes.contains { $0 != 0 })
            let header = Data("SIZE 101.60 mm,152.40 mm\r\nDIRECTION 0,0\r\nREFERENCE 0,0\r\nCLS\r\nBITMAP 0,0,102,1218,4,".utf8)
            XCTAssertTrue(job.bytes.starts(with: header))
            var pos = header.count
            var raster: [UInt8] = []
            while true {
                guard pos + 4 <= job.bytes.count else { throw BenchError("Missing block length") }
                let n = (0..<4).reduce(0) { $0 | Int(job.bytes[pos + $1]) << (8 * $1) }
                pos += 4
                if n == 0 { break }
                guard n <= job.bytes.count - pos else { throw BenchError("Block outside job") }
                let pixels = try expand(Array(job.bytes[pos..<(pos + n)]))
                XCTAssertEqual(pixels.count, min(4096, expected.bytes.count - raster.count))
                raster.append(contentsOf: pixels)
                pos += n
            }
            XCTAssertEqual(raster, expected.bytes.map { ~$0 })
            XCTAssertEqual(job.bytes[pos...], Data("\r\nPRINT 1,1\r\n".utf8))
        }
    }
}
