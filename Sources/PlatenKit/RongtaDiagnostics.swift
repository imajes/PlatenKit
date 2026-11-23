import Foundation

enum RongtaDiagnostics {
    // Literal emitted by Rongta's ZPLCmd SDK for its 4-series status query.
    static let statusQuery = Data("~HQPRNSTA\r\n".utf8)

    static func replyEndpoint(for output: PrinterEndpoint, in endpoints: [PrinterEndpoint]) throws -> PrinterEndpoint {
        // service / write_char / read_char in Rongta's ble_serial.plist
        let replies = ["18F0/2AF1": "18F0/2AF0", "FF00/FF02": "FF00/FF01", "FFE0/FFE1": "FFE0/FFE1"]
        let matches = endpoints.filter { $0.id == replies[output.id] && ($0.properties.contains("notify") || $0.properties.contains("indicate")) }
        guard output.writable, matches.count == 1 else {
            throw BenchError("No unique Rongta SDK reply endpoint for \(output.id).")
        }
        return matches[0]
    }

    static func dump(_ bytes: Data) -> String {
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        let readable = bytes.map { byte -> String in
            switch byte {
            case 10: return "\\n"
            case 13: return "\\r"
            case 92: return "\\\\"
            case 32...126: return String(UnicodeScalar(byte))
            default: return String(format: "\\x%02X", byte)
            }
        }.joined()
        return "\(bytes.count) bytes · hex \(hex) · text \(readable)"
    }
}
