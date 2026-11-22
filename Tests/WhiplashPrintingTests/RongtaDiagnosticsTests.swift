import XCTest
@testable import WhiplashPrinting

final class RongtaDiagnosticsTests: XCTestCase {
    func testVendorReplyPathMustMatchServiceWriteAndNotificationProperties() throws {
        for (service, write, read) in [("18F0", "2AF1", "2AF0"), ("FF00", "FF02", "FF01"), ("FFE0", "FFE1", "FFE1")] {
            let output = PrinterEndpoint(service: service, characteristic: write, properties: ["write"])
            let input = PrinterEndpoint(service: service, characteristic: read, properties: ["notify"])
            let unrelated = PrinterEndpoint(service: "1234", characteristic: read, properties: ["notify"])
            let inert = PrinterEndpoint(service: service, characteristic: read, properties: ["read"])
            XCTAssertEqual(try RongtaDiagnostics.replyEndpoint(for: output, in: [input, unrelated]), input)
            XCTAssertThrowsError(try RongtaDiagnostics.replyEndpoint(for: output, in: [inert, unrelated]))
            XCTAssertThrowsError(try RongtaDiagnostics.replyEndpoint(for: output, in: [input, input]))
        }
    }

    func testQueryAndTracePreserveTheWireBytes() {
        XCTAssertEqual(RongtaDiagnostics.statusQuery, Data("~HQPRNSTA\r\n".utf8))
        let dump = RongtaDiagnostics.dump(Data([2, 65, 92, 13, 10, 255]))
        XCTAssertEqual(dump, "6 bytes · hex 02 41 5C 0D 0A FF · text \\x02A\\\\\\r\\n\\xFF")
    }

    func testMarkIsOneCenteredJobOnTheFourByTwoStock() throws {
        let stock = try LabelStock(widthMM: 101.6, heightMM: 50.8)
        let job = try LabelJob.rongtaMark(id: "WL-R2-2122", stock: stock)
        let expected = "^XA\r\n^FO374,141\r\n^GB64,64,64,B,0^FS\r\n^FO206,225\r\n^A0N,40,40^FDWL-R2-2122^FS\r\n^PQ1\r\n^XZ\r\n"
        XCTAssertEqual(job.bytes, Data(expected.utf8))
        XCTAssertThrowsError(try LabelJob.rongtaMark(id: "bad^XZ", stock: stock))
    }
}
