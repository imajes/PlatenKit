import CoreImage.CIFilterBuiltins
import XCTest
@testable import WhiplashPrinting

final class PrinterTests: XCTestCase {
    func testOddWidthAndWireBytes() throws {
        let stock = try LabelStock(widthMM: 9 * 25.4 / 203, heightMM: 8 * 25.4 / 203)
        var pixels = [UInt8](repeating: 255, count: 72)
        pixels[0] = 0
        pixels[8] = 0
        pixels[10] = 0
        let page = try LabelBitmap(width: 9, height: 8, grayscale: pixels)
        XCTAssertEqual(page.bytes.prefix(4), Data([0x80, 0x80, 0x40, 0]))
        let zpl = try LabelJob.raster(page, id: "A", model: .rongta, stock: stock)
        XCTAssertTrue(String(decoding: zpl.bytes, as: UTF8.self).contains("^GFA,16,16,2,80804000"))
        let tspl = try LabelJob.raster(page, id: "A", model: .labelife, stock: stock)
        let header = try XCTUnwrap(tspl.bytes.range(of: Data("BITMAP 0,0,2,8,4,".utf8)))
        // A little-endian block length, four literals, a distance-one match, LZO EOF, then the mode-4 terminator.
        let expected = Data([11, 0, 0, 0, 21, 0x7f, 0x7f, 0xbf, 0xff, 42, 0, 0, 17, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(tspl.bytes[header.upperBound..<(header.upperBound + expected.count)], expected)
        XCTAssertEqual(tspl.bytes.suffix(13), Data("\r\nPRINT 1,1\r\n".utf8))
    }

    func testLabelifeBitmapUsesIndependent4096ByteBlocks() throws {
        let page = try LabelBitmap(width: 8, height: 4097, grayscale: .init(repeating: 255, count: 8 * 4097))
        var stream = Data()
        LabelifeRaster.append(page, to: &stream)
        let first = Data("BITMAP 0,0,1,4097,4,".utf8).count
        XCTAssertEqual(stream[first..<(first + 4)], Data([24, 0, 0, 0]))
        let second = first + 4 + 24
        XCTAssertEqual(stream[second...], Data([5, 0, 0, 0, 18, 255, 17, 0, 0, 0, 0, 0, 0]))
    }

    func testFullShippingLabelSplitsZPLGraphicFields() throws {
        let stock = try LabelStock(widthMM: 101.6, heightMM: 152.4)
        let page = try LabelBitmap(width: stock.widthDots, height: stock.heightDots, grayscale: .init(repeating: 255, count: stock.widthDots * stock.heightDots))
        let job = try LabelJob.raster(page, model: .rongta, stock: stock)
        let wire = String(decoding: job.bytes, as: UTF8.self)
        XCTAssertEqual(wire.components(separatedBy: "^GFA").count, 3)
        XCTAssertTrue(wire.contains("^FO0,980^GFA"))
        XCTAssertEqual(wire.components(separatedBy: "^PQ1").count, 2)
    }

    func testSmokeIsOneJobAndIDCannotBecomeCommands() throws {
        let stock = try LabelStock(widthMM: 50.8, heightMM: 101.6)
        for model in PrinterModel.allCases {
            let job = try LabelJob.smoke(id: "WL-123", model: model, stock: stock)
            let bytes = String(decoding: job.bytes, as: UTF8.self)
            if model == .rongta { XCTAssertTrue(bytes.contains("WL-123")) }
            else { XCTAssertTrue(bytes.contains("BITMAP 0,0,")) }
            XCTAssertTrue(bytes.hasSuffix(model == .rongta ? "^PQ1^XZ" : "PRINT 1,1\r\n"))
            XCTAssertThrowsError(try LabelJob.smoke(id: "A^XZ\r\n", model: model, stock: stock))
        }
        XCTAssertThrowsError(try LabelStock(widthMM: .nan, heightMM: 10))
        XCTAssertThrowsError(try LabelBitmap(width: 9, height: 8, grayscale: []))
    }

    func testRenderedPagePreservesQRPayloadModulesAndQuietZone() throws {
        let stock = try LabelStock(widthMM: 50.8, heightMM: 101.6)
        let id = "WL-0123456789AB"
        let image = try LabelRenderer.compose(text: id, qrPayload: id, stock: stock)
        let page = try LabelRenderer.bitmap(from: image, stock: stock)
        XCTAssertEqual(page.bytes.count, page.bytesPerRow * page.height)

        // Compare the packed print bytes with an independently generated, unscaled QR symbol.
        // This includes polarity and orientation and needs no camera, GPU, or barcode service.
        let encoder = CIFilter.qrCodeGenerator()
        encoder.message = Data(id.utf8)
        encoder.correctionLevel = "M"
        let reference = try XCTUnwrap(encoder.outputImage?.cgImage)
        let n = reference.width
        let context = try XCTUnwrap(CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: n, height: n))
        context.draw(reference, in: CGRect(x: 0, y: 0, width: n, height: n))
        let modules = try XCTUnwrap(context.data?.assumingMemoryBound(to: UInt8.self))
        let first = try XCTUnwrap((0..<(n * n)).first { modules[$0] < 128 })
        let border = first % n
        let side = n - 2 * border
        func dot(_ x: Int, _ y: Int) -> Bool {
            page.bytes[y * page.bytesPerRow + x / 8] & (0x80 >> (x % 8)) != 0
        }
        // The QR occupies the left of the page below the title.
        let leftRegion = 0..<(page.width * 3 / 5)
        let top = try XCTUnwrap((page.height / 5..<page.height).first { y in leftRegion.contains { dot($0, y) } })
        let left = try XCTUnwrap(leftRegion.first { dot($0, top) })
        let right = try XCTUnwrap(leftRegion.last { dot($0, top) })
        let scale = (right - left + 1) / side
        XCTAssertGreaterThan(scale, 0)
        for y in -4..<(side + 4) {
            for x in -4..<(side + 4) {
                let inSymbol = (0..<side).contains(x) && (0..<side).contains(y)
                let expected = inSymbol && modules[(y + border) * n + x + border] < 128
                XCTAssertEqual(dot(left + x * scale + scale / 2, top + y * scale + scale / 2), expected, "QR module \(x),\(y)")
            }
        }
    }

    func testSuppliedArtworkIsFittedOnWhiteAndCompositedIntoTheLabel() throws {
        let pixels = Data([0, 0, 0, 255, 0, 0, 0, 0])
        let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
        let art = try XCTUnwrap(CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let square = try LabelStock(widthMM: 4, heightMM: 4)
        let page = try LabelRenderer.bitmap(from: art, stock: square)
        XCTAssertEqual(page.width, 32)
        let blank = [UInt8](repeating: 0, count: 32)
        let row: [UInt8] = [255, 255, 0, 0]
        let body = Array(repeating: row, count: 16).flatMap { $0 }
        XCTAssertEqual(Array(page.bytes), blank + body + blank)

        let stock = try LabelStock(widthMM: 101.6, heightMM: 152.4)
        let custom = try LabelRenderer.compose(artwork: art, text: "BOX 014", qrPayload: "box-014", stock: stock)
        let standard = try LabelRenderer.compose(text: "BOX 014", qrPayload: "box-014", stock: stock)
        let a = try LabelRenderer.bitmap(from: custom, stock: stock)
        let b = try LabelRenderer.bitmap(from: standard, stock: stock)
        XCTAssertEqual(a.width, 812)
        XCTAssertEqual(a.height, 1218)
        XCTAssertNotEqual(a.bytes, b.bytes)
        for y in 0..<a.height {
            let start = y * a.bytesPerRow
            // The title and QR at the left stay identical when the caller changes only the art.
            XCTAssertEqual(a.bytes[start..<(start + 50)], b.bytes[start..<(start + 50)])
        }
    }
}
