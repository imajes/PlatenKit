import PlatenKit
import XCTest

final class PublicAPITests: XCTestCase {
    func testGeneratedRunIDFitsThePublicLabelAPI() throws {
        let id = LabelJob.newID()
        XCTAssertEqual(id.range(of: #"^PK-[0-9A-F]{12}$"#, options: .regularExpression), id.startIndex..<id.endIndex)
        let stock = try LabelStock(widthMM: 101.6, heightMM: 50.8)
        XCTAssertEqual(try LabelJob.smoke(id: id, model: .rongta, stock: stock).id, id)
    }

    func testComposeQRLabelUsingPublicAPI() throws {
        let stock = try LabelStock(widthMM: 101.6, heightMM: 50.8)
        let page = try LabelRenderer.compose(text: "Box 14", qrPayload: "BOX-14", stock: stock)
        let job = try LabelJob.image(page, id: "BOX-14", model: .rongta, stock: stock)
        XCTAssertEqual(job.language, .zpl)
        XCTAssertEqual(job.stock.widthDots, 812)
    }
}
