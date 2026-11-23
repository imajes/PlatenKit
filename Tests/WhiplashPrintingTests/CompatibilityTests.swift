import WhiplashPrinting
import XCTest

final class CompatibilityTests: XCTestCase {
    func testOriginalModuleCanStillMakeTheOriginalQRJob() throws {
        let stock = try LabelStock(widthMM: 101.6, heightMM: 50.8)
        let page = try LabelRenderer.compose(text: "Box 14", qrPayload: "BOX-14", stock: stock)
        let job = try LabelJob.image(page, id: "BOX-14", model: .rongta, stock: stock)
        XCTAssertEqual(job.language, .zpl)
        XCTAssertEqual(job.stock.widthDots, 812)
    }
}
