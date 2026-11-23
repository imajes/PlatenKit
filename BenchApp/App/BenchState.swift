import ImageIO
import SwiftUI
import PlatenKit

@MainActor final class BenchState: ObservableObject {
    @Published var devices: [NearbyPrinter] = []
    @Published var deviceID: UUID?
    @Published var connected = false
    @Published var endpoints: [PrinterEndpoint] = []
    @Published var endpointID = ""
    @Published var model: PrinterModel = .rongta
    @Published var width = "101.6"
    @Published var height = "50.8"
    @Published var dpi = "203"
    @Published var mode = ""
    @Published var trial = "Initial connection"
    @Published var artworkName = ""
    @Published var artworkMode = LabelImageMode.lineArt
    @Published var fontName = ""
    @Published var fontWeight = ""
    @Published var fontSize = ""
    @Published private(set) var fontFilename = ""
    @Published var busy = false
    @Published var journal = ""
    @Published var lastID = UserDefaults.standard.string(forKey: "lastPrintRun") ?? ""
    @Published var observation = ""
    private var artwork: CGImage?
    private var fontData: Data?
    private let radio = BluetoothPrinter()
    private let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("printer-bench.log")

    init() {
        if FileManager.default.fileExists(atPath: logURL.path) {
            do { journal = try String(contentsOf: logURL, encoding: .utf8) }
            catch { journal = "Cannot read bench journal: \(error.localizedDescription)\n" }
        }
        radio.onEvent = { [weak self] message in
            guard let self else { return }
            record(message)
            Task { @MainActor in
                if self.connected && self.radio.connectedID == nil { self.resetConnection() }
            }
        }
    }

    func record(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        journal += line
        do {
            if !FileManager.default.fileExists(atPath: logURL.path) {
                try Data(line.utf8).write(to: logURL, options: .withoutOverwriting)
            } else {
                let file = try FileHandle(forWritingTo: logURL)
                defer { try? file.close() }
                try file.seekToEnd()
                try file.write(contentsOf: Data(line.utf8))
            }
        } catch { journal += "Journal write failed: \(error.localizedDescription)\n" }
    }

    private func perform(_ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await work() }
            catch { record("Error: \(error.localizedDescription)") }
            if radio.connectedID == nil { resetConnection() }
        }
    }

    private func resetConnection() {
        connected = false
        endpoints = []
        endpointID = ""
    }

    func scan() {
        perform {
            self.devices = []
            self.deviceID = nil
            self.record("Host \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion) · Core Bluetooth · \(self.model.name)")
            self.devices = try await self.radio.scan()
            self.record("Scan finished with \(self.devices.count) nearby peripherals")
        }
    }

    func connect() {
        guard let id = deviceID, let device = devices.first(where: { $0.id == id }) else { return }
        perform {
            self.record("Discovered \(device.name) \(id) · advertised \(device.advertisedServices.joined(separator: ","))")
            try await self.radio.connect(id)
            self.endpoints = try await self.radio.inspect()
            self.connected = true
        }
    }

    func disconnect() {
        radio.disconnect()
        resetConnection()
        deviceID = nil
        devices = []
        record("Disconnected. Scan to select a printer again.")
    }

    func selectModel() {
        width = "101.6"
        height = model == .rongta ? "50.8" : "152.4"
        endpointID = ""
        mode = ""
    }

    func importArtwork(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let contents = try Data(contentsOf: url)
            guard let source = CGImageSourceCreateWithData(contents as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw BenchError("Cannot decode the artwork.") }
            artwork = image
            artworkName = url.lastPathComponent
        } catch { record("Artwork: \(error.localizedDescription)") }
    }

    func importFont(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            _ = try LabelFont(data: data)
            fontData = data
            fontFilename = url.lastPathComponent
        } catch { record("Font: \(error.localizedDescription)") }
    }

    func clearFontFile() {
        fontData = nil
        fontFilename = ""
    }

    private func selectedFont() throws -> LabelFont? {
        let weightText = fontWeight.trimmingCharacters(in: .whitespacesAndNewlines)
        let weight = Int(weightText)
        guard weightText.isEmpty || weight != nil else { throw BenchError("Enter a whole-number weight.") }
        let sizeText = fontSize.trimmingCharacters(in: .whitespacesAndNewlines)
        let points = Double(sizeText)
        guard sizeText.isEmpty || points != nil else { throw BenchError("Enter a numeric font size in points.") }
        if let fontData { return try LabelFont(data: fontData, weight: weight, pointSize: points) }
        let name = fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return try LabelFont(postScriptName: name, weight: weight, pointSize: points) }
        guard weight == nil else { throw BenchError("Enter a font name or choose a font file for this weight.") }
        return try points.map { try LabelFont(postScriptName: "Helvetica-Bold", pointSize: $0) }
    }

    func printOne(rich: Bool) {
        perform {
            guard let w = Double(self.width), let h = Double(self.height), let dpi = Int(self.dpi) else {
                throw BenchError("Enter stock dimensions in millimeters and resolution in dots per inch.")
            }
            let stock = try LabelStock(widthMM: w, heightMM: h, dpi: dpi)
            let device = self.devices.first { $0.id == self.radio.connectedID }
            let endpoint = try PrinterEndpoint.select(for: self.model, in: self.endpoints, advertisedServices: device?.advertisedServices ?? [], peripheralName: device?.name, explicit: self.endpointID.isEmpty ? nil : self.endpointID)
            let id = LabelJob.newID()
            let font = try self.selectedFont()
            let job: LabelJob
            if rich {
                let page = try LabelRenderer.compose(artwork: self.artwork, text: id, qrPayload: id, stock: stock, font: font, artworkMode: self.artworkMode)
                job = try .image(page, id: id, model: self.model, stock: stock)
            } else {
                job = try .smoke(id: id, model: self.model, stock: stock, font: font)
            }
            self.lastID = id
            UserDefaults.standard.set(id, forKey: "lastPrintRun")
            self.record("\(self.trial) · \(rich ? "artwork, text, QR" : "ID only") · \(id) · paper unobserved")
            if let font { self.record("Font \(font.description)") }
            if rich && self.artwork != nil { self.record("Image mode \(self.artworkMode.rawValue)") }
            _ = try await self.radio.submit(job, to: endpoint, mode: WriteMode(rawValue: self.mode))
        }
    }

    func recordPaper() {
        let note = observation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lastID.isEmpty, !note.isEmpty else { return }
        record("Paper observation for \(lastID): \(note)")
        observation = ""
    }
}
