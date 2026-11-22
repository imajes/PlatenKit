import CoreImage.CIFilterBuiltins
import XCTest
@testable import WhiplashPrinting

final class PrinterTests: XCTestCase {
    func testLabelifeFragmentedPrinterMessagesAndErrors() {
        var messages = LabelifeMessages()
        XCTAssertEqual(messages.append(Data("SSSGETPRI".utf8)), [])
        XCTAssertEqual(messages.append(Data("NTING:DOING\r\nCmd error:".utf8)), ["SSSGETPRINTING:DOING"])
        XCTAssertEqual(messages.append(Data([0x1f, 0x11]) + Data("/SIZE\r".utf8)), [])
        XCTAssertEqual(messages.append(Data("\n\r\nSSSGETPRINTING:DONE\r\n".utf8)), ["Cmd error:\\x1F\\x11/SIZE", "SSSGETPRINTING:DONE"])
    }

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

    func testLabelifeCreditsAndPacketLength() throws {
        let link = LabelifeLink()
        XCTAssertEqual(link.credits, 0)
        XCTAssertEqual(link.packetLimit, 20)
        var pump = try WritePump(Data(repeating: 1, count: 500), limit: 512, mode: .acknowledged, link: link)
        XCTAssertNil(pump.next(canQueue: true))
        XCTAssertTrue(link.receive(Data([1, 7])))
        XCTAssertTrue(link.receive(Data([2, 0xf4, 0])))
        XCTAssertEqual(link.packetLimit, 244)
        XCTAssertEqual(pump.next(canQueue: true)?.count, 244)
        XCTAssertNil(pump.next(canQueue: true))
        XCTAssertEqual(link.credits, 6)
        XCTAssertTrue(link.receive(Data([1, 1])))
        XCTAssertEqual(link.credits, 7)
        XCTAssertFalse(link.receive(Data([0x1a, 0x1d, 0])))
        XCTAssertFalse(link.receive(Data([2, 0, 0])))
        XCTAssertEqual(link.packetLimit, 244)
        pump.didAcknowledge()
        XCTAssertEqual(pump.next(canQueue: false)?.count, 244)
        pump.didAcknowledge()
        XCTAssertEqual(pump.next(canQueue: false)?.count, 12)
        XCTAssertFalse(pump.complete)
        pump.didAcknowledge()
        XCTAssertTrue(pump.complete)
    }

    func testLabelifeQueuedWritesNeedBothCreditAndCoreBluetoothCapacity() throws {
        let link = LabelifeLink()
        XCTAssertTrue(link.receive(Data([1, 1])))
        var pump = try WritePump(Data(0..<34), limit: 16, mode: .queued, link: link)
        XCTAssertNil(pump.next(canQueue: false))
        XCTAssertEqual(link.credits, 1)
        XCTAssertEqual(pump.next(canQueue: true), Data(0..<16))
        XCTAssertNil(pump.next(canQueue: true))
        XCTAssertTrue(pump.failure("link lost").message.contains("16/34 bytes"))
        XCTAssertTrue(link.receive(Data([1, 2])))
        XCTAssertEqual(pump.next(canQueue: true), Data(16..<32))
        XCTAssertEqual(pump.next(canQueue: true), Data(32..<34))
        XCTAssertTrue(pump.complete)
        XCTAssertEqual(pump.acknowledged, 0)
    }

    func testLabelifeSelectionUsesObservedNameAndCharacteristicPair() throws {
        let output = PrinterEndpoint(service: "FF00", characteristic: "FF02", properties: ["write", "writeWithoutResponse"])
        let replies = PrinterEndpoint(service: "FF00", characteristic: "FF03", properties: ["notify"])
        let name = "AM-243Z-BT-5AD6"
        XCTAssertEqual(try PrinterEndpoint.select(for: .labelife, in: [output, replies], peripheralName: name), output)
        XCTAssertThrowsError(try PrinterEndpoint.select(for: .labelife, in: [output, replies], peripheralName: "Other device"))
        XCTAssertThrowsError(try PrinterEndpoint.select(for: .labelife, in: [output], peripheralName: name))
        XCTAssertThrowsError(try PrinterEndpoint.select(for: .labelife, in: [output, output, replies], peripheralName: name))
        XCTAssertThrowsError(try PrinterEndpoint.select(for: .labelife, in: [output, replies, replies], peripheralName: name))
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

    func testEndpointSelectionUsesServiceAndLiveProperties() throws {
        let printer = PrinterEndpoint(service: "ff00", characteristic: "ff02", properties: ["writeWithoutResponse"])
        let unrelated = PrinterEndpoint(service: "1234", characteristic: "ff02", properties: ["write"])
        XCTAssertEqual(try PrinterEndpoint.select(for: .rongta, in: [printer, unrelated]), printer)
        XCTAssertEqual(try printer.mode(), .queued)
        XCTAssertThrowsError(try printer.mode(preferred: .acknowledged))
        XCTAssertThrowsError(try PrinterEndpoint.select(for: .rongta, in: [printer, printer]))
        XCTAssertThrowsError(try PrinterEndpoint.select(for: .labelife, in: [printer]))
        XCTAssertEqual(try PrinterEndpoint.select(for: .labelife, in: [printer], explicit: "ff00/ff02"), printer)
    }

    func testLiveRongtaWithTwoVendorEndpointsPrefersAdvertisedService() throws {
        let endpoints = [
            PrinterEndpoint(service: "FF00", characteristic: "FF02", properties: ["write", "writeWithoutResponse"]),
            PrinterEndpoint(service: "18F0", characteristic: "2AF1", properties: ["write", "writeWithoutResponse"])
        ]
        XCTAssertThrowsError(try PrinterEndpoint.select(for: .rongta, in: endpoints))
        XCTAssertEqual(try PrinterEndpoint.select(for: .rongta, in: endpoints, advertisedServices: ["FEE7", "18F0"]), endpoints[1])
        XCTAssertEqual(try PrinterEndpoint.select(for: .rongta, in: endpoints, advertisedServices: ["18F0"], explicit: "FF00/FF02"), endpoints[0])
        XCTAssertThrowsError(try PrinterEndpoint.select(for: .rongta, in: endpoints, advertisedServices: ["18f0", "FF00"]))
    }

    func testWritesWaitForAcknowledgementsIncludingLastChunk() throws {
        var pump = try WritePump(Data(0..<10), limit: 4, mode: .acknowledged)
        for expected in [Data(0..<4), Data(4..<8), Data(8..<10)] {
            XCTAssertEqual(pump.next(canQueue: false), expected)
            XCTAssertNil(pump.next(canQueue: true))
            XCTAssertFalse(pump.complete)
            pump.didAcknowledge()
        }
        XCTAssertTrue(pump.complete)
        XCTAssertNil(pump.next(canQueue: true))
        XCTAssertEqual(pump.chunks, 3)
    }

    func testBackpressureResumesAtFirstUnsentByteAndDisconnectIsUncertain() throws {
        var pump = try WritePump(Data(0..<8), limit: 4, mode: .queued)
        XCTAssertNil(pump.next(canQueue: false))
        XCTAssertTrue(pump.failure("Disconnected").message.contains("No bytes submitted"))
        XCTAssertEqual(pump.next(canQueue: true), Data(0..<4))
        XCTAssertNil(pump.next(canQueue: false))
        XCTAssertTrue(pump.failure("Disconnected").message.contains("4/8 bytes"))
        XCTAssertEqual(pump.next(canQueue: true), Data(4..<8))
        XCTAssertTrue(pump.complete)
        XCTAssertEqual(pump.acknowledged, 0)
        XCTAssertThrowsError(try WritePump(Data([1]), limit: 0, mode: .queued))
    }
}
