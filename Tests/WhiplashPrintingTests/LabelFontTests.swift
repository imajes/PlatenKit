import CoreText
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import WhiplashPrinting

final class LabelFontTests: XCTestCase {
    private func stock() throws -> LabelStock { try LabelStock(widthMM: 101.6, heightMM: 50.8, dpi: 203) }

    func testKarlaUsesTheExactRequestedWeightAfterResizing() throws {
        let url = try XCTUnwrap(LabelFont.bundledKarlaURL)
        let data = try Data(contentsOf: url)
        let stock = try stock()
        for weight in [200, 275, 300, 800] {
            let bundled = try LabelFont(postScriptName: "Karla", weight: weight)
            let file = try LabelFont(data: data, weight: weight)
            XCTAssertEqual(bundled.postScriptName, "Karla-Regular")
            for size: CGFloat in [12, 53] {
                let variations = CTFontCopyVariation(bundled.sized(size)) as NSDictionary?
                XCTAssertEqual(variations?[NSNumber(value: 0x77676874)] as? NSNumber, NSNumber(value: weight))
            }
            let fromName = try LabelJob.smoke(id: "Box-014-Kitchen", model: .rongta, stock: stock, font: bundled)
            let fromFile = try LabelJob.smoke(id: "Box-014-Kitchen", model: .rongta, stock: stock, font: file)
            XCTAssertEqual(fromName.bytes, fromFile.bytes)
        }
    }

    func testChangingTheWeightOnlyChangesTheTitleAndBothAdaptersUseIt() throws {
        let stock = try stock()
        let id = "Box-014-Kitchen"
        let thin = try LabelFont(postScriptName: "Karla", weight: 275)
        let light = try LabelFont(postScriptName: "Karla", weight: 300)
        func page(_ font: LabelFont) throws -> LabelBitmap {
            let image = try LabelRenderer.compose(text: id, qrPayload: id, stock: stock, font: font)
            return try LabelRenderer.bitmap(from: image, stock: stock)
        }
        let a = try page(thin), b = try page(light)
        let titleEnd = 90 * a.bytesPerRow
        let inkA = a.bytes.prefix(titleEnd).reduce(0) { $0 + $1.nonzeroBitCount }
        let inkB = b.bytes.prefix(titleEnd).reduce(0) { $0 + $1.nonzeroBitCount }
        XCTAssertGreaterThan(inkA, 0)
        XCTAssertGreaterThan(inkB, inkA)
        XCTAssertEqual(a.bytes.dropFirst(titleEnd), b.bytes.dropFirst(titleEnd))
        let text = try LabelRenderer.textPage(id, stock: stock, font: thin)
        for model in PrinterModel.allCases {
            let first = try LabelJob.smoke(id: id, model: model, stock: stock, font: thin)
            let second = try LabelJob.smoke(id: id, model: model, stock: stock, font: light)
            XCTAssertEqual(first.bytes, try LabelJob.image(text, id: id, model: model, stock: stock).bytes)
            XCTAssertNotEqual(first.bytes, second.bytes)
        }
    }

    func testInstalledFacesResolveExactlyAndTheDefaultKeepsItsPixels() throws {
        let stock = try stock(), id = "WL-G9-0035"
        let helvetica = try LabelFont(postScriptName: "Helvetica-Bold")
        let courier = try LabelFont(postScriptName: "Courier-Bold")
        XCTAssertEqual(courier.postScriptName, "Courier-Bold")
        let original = try LabelJob.smoke(id: id, model: .rongta, stock: stock)
        XCTAssertEqual(original.bytes, try LabelJob.smoke(id: id, model: .rongta, stock: stock, font: helvetica).bytes)
        XCTAssertNotEqual(original.bytes, try LabelJob.smoke(id: id, model: .rongta, stock: stock, font: courier).bytes)
    }

    func testPhysicalTitleSizeScalesWithResolutionAndUsesTheAvailableSpace() throws {
        let id = "Box-014-Kitchen"
        let stock = try stock()
        let automatic = try LabelFont(postScriptName: "Karla", weight: 275)
        let larger = try LabelFont(postScriptName: "Karla", weight: 275, pointSize: 24)
        func titleHeight(on media: LabelStock, font: LabelFont) throws -> Int {
            let image = try LabelRenderer.textPage(id, stock: media, font: font)
            let page = try LabelRenderer.bitmap(from: image, stock: media)
            let inkRows = (0..<page.height).filter { row in
                let start = row * page.bytesPerRow
                return page.bytes[start..<(start + page.bytesPerRow)].contains { $0 != 0 }
            }
            return try XCTUnwrap(inkRows.last) - XCTUnwrap(inkRows.first) + 1
        }
        let height = try titleHeight(on: stock, font: larger)
        XCTAssertGreaterThan(height, try titleHeight(on: stock, font: automatic))
        let doubled = try LabelStock(widthMM: 101.6, heightMM: 50.8, dpi: 406)
        XCTAssertEqual(Double(try titleHeight(on: doubled, font: larger)), 2 * Double(height), accuracy: 2)

        func fullPage(_ font: LabelFont) throws -> LabelBitmap {
            let image = try LabelRenderer.compose(text: id, qrPayload: id, stock: stock, font: font)
            return try LabelRenderer.bitmap(from: image, stock: stock)
        }
        let original = try fullPage(automatic), updated = try fullPage(larger)
        let startOfArtwork = 100 * original.bytesPerRow
        XCTAssertNotEqual(original.bytes.prefix(startOfArtwork), updated.bytes.prefix(startOfArtwork))
        XCTAssertEqual(original.bytes.dropFirst(startOfArtwork), updated.bytes.dropFirst(startOfArtwork))
    }

    func testExplicitPointSizeMustFitWithoutSilentShrinking() throws {
        let stock = try stock()
        for size in [0, -1, Double.infinity, Double.nan] {
            XCTAssertThrowsError(try LabelFont(postScriptName: "Karla", pointSize: size))
        }
        let font = try LabelFont(postScriptName: "Karla", weight: 275, pointSize: 36)
        let tooWide = String(repeating: "W", count: 32)
        XCTAssertThrowsError(try LabelJob.smoke(id: tooWide, model: .rongta, stock: stock, font: font))
        let tooTall = try LabelFont(postScriptName: "Karla", pointSize: 200)
        XCTAssertThrowsError(try LabelRenderer.compose(text: "Box", qrPayload: "1", stock: stock, font: tooTall))
    }

    func testUnusableFontAndUnsupportedGlyphsFailBeforeJobCreation() throws {
        XCTAssertThrowsError(try LabelFont(postScriptName: "Whiplash-Missing-Face"))
        XCTAssertThrowsError(try LabelFont(data: Data([0, 1, 2])))
        XCTAssertThrowsError(try LabelFont(postScriptName: "Courier-Bold", weight: 275))
        XCTAssertThrowsError(try LabelFont(postScriptName: "Karla", weight: 199))
        XCTAssertThrowsError(try LabelFont(postScriptName: "Karla", weight: 801))
        let karla = try LabelFont(postScriptName: "Karla", weight: 275)
        XCTAssertThrowsError(try LabelRenderer.compose(text: "Box 🦊", qrPayload: "box", stock: stock(), font: karla)) { error in
            XCTAssertTrue(error.localizedDescription.contains("cannot draw every character"))
        }
    }

    func testOneBitPNGPreviewRoundTripsThePrinterDotsIncludingOddRowWidths() throws {
        let stock = try LabelStock(widthMM: 1.1, heightMM: 1.0, dpi: 203)
        XCTAssertEqual(stock.widthDots, 9)
        var pixels = [UInt8](repeating: 255, count: stock.widthDots * stock.heightDots)
        pixels[0] = 0
        pixels[2 * stock.widthDots + 8] = 0
        let page = try LabelBitmap(width: stock.widthDots, height: stock.heightDots, grayscale: pixels)
        let image = try page.makeImage()
        let png = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png, nil))
        let metadata = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        XCTAssertEqual(metadata[kCGImagePropertyDepth as String] as? Int, 1)
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(try LabelRenderer.bitmap(from: decoded, stock: stock).bytes, page.bytes)
    }
}
