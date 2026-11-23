import CoreGraphics
import CryptoKit
import ImageIO
import XCTest
@testable import PlatenKit

final class PhotoRasterTests: XCTestCase {
    private func image(_ pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                                     bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    func testPhotoMatchesIndependentFloydSteinbergDotsIncludingRowEdgesAndPadding() throws {
        let pixels: [UInt8] = [
            0, 32, 64, 96, 128, 160, 192, 224, 255,
            128, 128, 128, 128, 128, 128, 128, 128, 128,
            255, 224, 192, 160, 128, 96, 64, 32, 0,
            48, 80, 112, 144, 176, 112, 80, 48, 16,
            160, 160, 160, 160, 160, 160, 160, 160, 160
        ]
        let sample = try image(pixels, width: 9, height: 5)
        let media = try LabelStock(widthMM: 2.286, heightMM: 1.27, dpi: 100)
        let photo = try LabelRenderer.bitmap(from: sample, stock: media, mode: .photo)
        // Pillow's one-bit Floyd–Steinberg conversion, packed with one marking an ink dot.
        XCTAssertEqual(Array(photo.bytes), [232, 0, 86, 128, 23, 128, 211, 128, 40, 0])
        let original = try LabelRenderer.bitmap(from: sample, stock: media)
        XCTAssertNotEqual(photo.bytes, original.bytes)
        XCTAssertEqual(original.bytes, try LabelRenderer.bitmap(from: sample, stock: media, mode: .lineArt).bytes)
        for model in PrinterModel.allCases {
            let job = try LabelJob.image(sample, id: "PHOTO", model: model, stock: media, mode: .photo)
            XCTAssertEqual(job.bytes, try LabelJob.raster(photo, id: "PHOTO", model: model, stock: media).bytes)
        }
    }

    func testPhotoTreatmentOnlyChangesTheSuppliedArtworkOnAMixedLabel() throws {
        let stock = try LabelStock(widthMM: 101.6, heightMM: 50.8)
        let artwork = try image([255, 60, 100, 200, 0, 128], width: 3, height: 2)
        func page(_ image: CGImage, _ mode: LabelImageMode) throws -> Data {
            let page = try LabelRenderer.compose(artwork: image, text: "Box-014-Kitchen", qrPayload: "Box-014-Kitchen",
                                                 stock: stock, artworkMode: mode)
            return try LabelRenderer.bitmap(from: page, stock: stock).bytes
        }
        let baseline = try page(artwork, .lineArt)
        let photograph = try page(artwork, .photo)
        XCTAssertNotEqual(baseline, photograph)

        // A solid rectangle reveals the artwork's footprint, including rounded edge pixels.
        let black = try image(Array(repeating: 0, count: 6), width: 3, height: 2)
        let white = try image(Array(repeating: 255, count: 6), width: 3, height: 2)
        let blackLine = try page(black, .lineArt), blackPhoto = try page(black, .photo)
        let whitePage = try page(white, .lineArt)
        XCTAssertEqual(whitePage, try page(white, .photo))
        XCTAssertTrue(whitePage.contains { $0 != 0 }, "The reference must contain the title and QR.")
        let outsideChange = baseline.indices.first { i in
            let footprint = (blackLine[i] ^ whitePage[i]) | (blackPhoto[i] ^ whitePage[i])
            return (baseline[i] ^ photograph[i]) & ~footprint != 0
        }
        XCTAssertNil(outsideChange, "An ink dot outside the artwork changed.")
    }

    func testMoonPhotoMatchesDotsInBothPrintedReferencePages() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "moon-gray-284", withExtension: "png"))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let moon = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let sideMM = 284.0 * 25.4 / 203
        let stock = try LabelStock(widthMM: sideMM, heightMM: sideMM, dpi: 203)
        let photo = try LabelRenderer.bitmap(from: moon, stock: stock, mode: .photo)
        // Fingerprint of the right-hand 284 × 284 crop in both November 22 paper proofs.
        let hash = SHA256.hash(data: photo.bytes).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hash, "ff6965e9970d9034c400cbe3b305e100371dbe18dca7aaefd4dedaab37d663d1")
    }
}
