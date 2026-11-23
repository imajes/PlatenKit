import Foundation

/// BITMAP mode 4 from the AM-243-BT and PM-241-BT-Bluetooth driver profiles.
enum LabelifeRaster {
    static func append(_ page: LabelBitmap, to job: inout Data) {
        job.append(contentsOf: "BITMAP 0,0,\(page.bytesPerRow),\(page.height),4,".utf8)
        for start in stride(from: 0, to: page.bytes.count, by: 4096) {
            let end = min(start + 4096, page.bytes.count)
            // This driver's mode 4 uses a zero bit for ink, including white padding at row ends.
            let block = compress(page.bytes[start..<end].map { ~$0 })
            var length = UInt32(block.count).littleEndian
            withUnsafeBytes(of: &length) { job.append(contentsOf: $0) }
            job.append(contentsOf: block)
        }
        job.append(contentsOf: [0, 0, 0, 0])
    }

    /// LZO1X literals and distance-one matches cover the flat areas of a monochrome label.
    static func compress(_ input: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        var previousOffset: Int?
        var literalStart = 0

        func extendedLength(_ value: Int) {
            var length = value
            while length > 255 {
                output.append(0)
                length -= 255
            }
            output.append(UInt8(length))
        }

        func literals(until end: Int) {
            let count = end - literalStart
            guard count > 0 else { return }
            if output.isEmpty && count <= 238 {
                output.append(UInt8(17 + count))
            } else if let previousOffset, count <= 3 {
                // The low two bits of the previous match carry up to three trailing literals.
                output[previousOffset] |= UInt8(count)
            } else if count <= 18 {
                output.append(UInt8(count - 3))
            } else {
                output.append(0)
                extendedLength(count - 18)
            }
            output.append(contentsOf: input[literalStart..<end])
        }

        var index = 0
        while index < input.count {
            let start = index
            index += 1
            while index < input.count && input[index] == input[start] { index += 1 }
            let copies = index - start - 1
            guard copies >= 4 else { continue }
            literals(until: start + 1)
            if copies <= 33 {
                output.append(UInt8(32 + copies - 2))
            } else {
                output.append(32)
                extendedLength(copies - 33)
            }
            previousOffset = output.count
            output.append(contentsOf: [0, 0])
            literalStart = index
        }
        literals(until: input.count)
        output.append(contentsOf: [0x11, 0, 0])
        return output
    }
}
