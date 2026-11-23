import Foundation

public enum WriteMode: String, CaseIterable, Sendable {
    case acknowledged, queued
}

/// FF03 grants permission for more FF02 packets and announces the module's payload ceiling.
final class LabelifeLink {
    private(set) var credits = 0
    private(set) var packetLimit = 20
    private(set) var receivedGrant = false

    func receive(_ frame: Data) -> Bool {
        let bytes = Array(frame)
        if bytes.count == 2 && bytes[0] == 1 {
            credits = min(65_535, credits + Int(bytes[1]))
            receivedGrant = true
            return true
        }
        if bytes.count == 3 && bytes[0] == 2 {
            let size = Int(bytes[1]) + 256 * Int(bytes[2])
            guard size > 0 else { return false }
            packetLimit = size
            return true
        }
        return false
    }

    fileprivate func didSend() { credits -= 1 }
}

/// FF03 carries ASCII printer messages as well as binary flow-control frames.
struct LabelifeMessages {
    private var partial = Data()

    mutating func append(_ bytes: Data) -> [String] {
        var lines: [String] = []
        for byte in bytes {
            if byte == 10 {
                if partial.last == 13 { partial.removeLast() }
                if !partial.isEmpty { lines.append(Self.display(partial)) }
                partial.removeAll(keepingCapacity: true)
            } else {
                partial.append(byte)
                if partial.count == 4096 {
                    lines.append(Self.display(partial))
                    partial.removeAll(keepingCapacity: true)
                }
            }
        }
        return lines
    }

    private static func display(_ data: Data) -> String {
        data.map { (32...126).contains($0) ? String(UnicodeScalar($0)) : String(format: "\\x%02X", $0) }.joined()
    }
}

public struct PrinterEndpoint: Identifiable, Hashable, Sendable {
    public let service: String
    public let characteristic: String
    public let properties: [String]
    public var id: String { "\(service)/\(characteristic)" }
    public var writable: Bool { properties.contains("write") || properties.contains("writeWithoutResponse") }
    public var description: String { "\(id) [\(properties.joined(separator: ", "))]" }

    public init(service: String, characteristic: String, properties: [String]) {
        self.service = service.uppercased()
        self.characteristic = characteristic.uppercased()
        self.properties = properties
    }

    public func mode(preferred: WriteMode? = nil) throws -> WriteMode {
        let supportsResponse = properties.contains("write")
        let mode = preferred ?? (supportsResponse ? .acknowledged : .queued)
        guard mode == .acknowledged ? supportsResponse : properties.contains("writeWithoutResponse") else {
            throw BenchError("\(id) does not support \(mode.rawValue) writes.")
        }
        return mode
    }

    public static func select(for model: PrinterModel, in endpoints: [Self], advertisedServices: [String] = [], peripheralName: String? = nil, explicit: String? = nil) throws -> Self {
        let matches: [Self]
        if let explicit {
            matches = endpoints.filter { $0.writable && $0.id == explicit.uppercased() }
        } else if model == .rongta {
            let vendorPairs = ["FF00/FF02", "FFE0/FFE1", "18F0/2AF1"]
            matches = endpoints.filter { $0.writable && vendorPairs.contains($0.id) }
            if matches.count > 1 {
                let advertised = Set(advertisedServices.map { $0.uppercased() })
                let advertisedMatches = matches.filter { advertised.contains($0.service) }
                if advertisedMatches.count == 1 { return advertisedMatches[0] }
            }
        } else {
            let name = peripheralName?.uppercased() ?? ""
            let models = ["AM-243Z-BT", "AM-243-BT", "PM-241Z-BT", "PM-241-BT"]
            let knownName = models.contains { name == $0 || name.hasPrefix($0 + "-") }
            let notices = endpoints.filter { $0.id == "FF00/FF03" && $0.properties.contains("notify") }
            guard knownName && notices.count == 1 else {
                throw BenchError("Select the Labelife from the scan and check its FF00/FF02 write and FF00/FF03 notify profile, or choose an inspected endpoint explicitly.")
            }
            matches = endpoints.filter { $0.writable && $0.id == "FF00/FF02" }
        }
        guard matches.count == 1 else {
            throw BenchError("Found \(matches.count) matching writable endpoints. Inspect the printer and select a unique service/characteristic pair.")
        }
        return matches[0]
    }
}

public struct Submission: Sendable {
    public let runID: String
    public let mode: WriteMode
    public let bytes: Int
    public let chunks: Int
    public var description: String { "\(runID) · \(bytes) bytes in \(chunks) \(chunks == 1 ? "chunk" : "chunks") \(mode.rawValue) · paper awaits observation" }
}

/// Core Bluetooth owns the callbacks. This value owns sequencing and byte accounting.
struct WritePump {
    let payload: Data
    let limit: Int
    let mode: WriteMode
    let link: LabelifeLink?
    private(set) var handed = 0
    private(set) var acknowledged = 0
    private(set) var chunks = 0

    init(_ payload: Data, limit: Int, mode: WriteMode, link: LabelifeLink? = nil) throws {
        guard !payload.isEmpty, limit > 0 else { throw BenchError("Empty payload or invalid Bluetooth write limit.") }
        self.payload = payload
        self.limit = limit
        self.mode = mode
        self.link = link
    }

    var complete: Bool { (mode == .acknowledged ? acknowledged : handed) == payload.count }

    mutating func next(canQueue: Bool) -> Data? {
        guard handed < payload.count else { return nil }
        if let link, link.credits == 0 { return nil }
        if mode == .acknowledged && handed != acknowledged { return nil }
        if mode == .queued && !canQueue { return nil }
        let start = handed
        handed += min(limit, link?.packetLimit ?? limit, payload.count - handed)
        link?.didSend()
        chunks += 1
        return payload.subdata(in: start..<handed)
    }

    mutating func didAcknowledge() {
        if mode == .acknowledged { acknowledged = handed }
    }

    func failure(_ reason: String) -> BenchError {
        guard handed > 0 else { return BenchError("No bytes submitted. \(reason)") }
        return BenchError("Physical outcome uncertain. \(handed)/\(payload.count) bytes handed to Bluetooth, \(acknowledged) acknowledged. Check the paper before requesting a reprint. \(reason)")
    }
}
