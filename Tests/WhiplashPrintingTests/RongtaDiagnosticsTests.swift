import XCTest
@testable import WhiplashPrinting

final class RongtaDiagnosticsTests: XCTestCase {
    func testMarkIsOneCenteredJobOnTheFourByTwoStock() throws {
        let stock = try LabelStock(widthMM: 101.6, heightMM: 50.8)
        let job = try LabelJob.rongtaMark(id: "WL-R2-2122", stock: stock)
        let expected = "^XA\r\n^FO374,141\r\n^GB64,64,64,B,0^FS\r\n^FO206,225\r\n^A0N,40,40^FDWL-R2-2122^FS\r\n^PQ1\r\n^XZ\r\n"
        XCTAssertEqual(job.bytes, Data(expected.utf8))
        XCTAssertThrowsError(try LabelJob.rongtaMark(id: "bad^XZ", stock: stock))
    }
}
