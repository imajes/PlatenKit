import Foundation
import ImageIO
import UniformTypeIdentifiers
import WhiplashPrinting

private let usage = """
printer-bench scan [--match NAME] [--seconds 5]
printer-bench inspect --device UUID [--seconds 5]
printer-bench rongta-status --device UUID [--endpoint SERVICE/WRITE] [--mode acknowledged|queued] [--seconds 5]
printer-bench rongta-mark --device UUID --width-mm W --height-mm H [--run-id ID] [--endpoint SERVICE/WRITE] [--mode acknowledged|queued] [--seconds 5]
printer-bench smoke|test-label|image --device UUID --model rongta|labelife --width-mm W --height-mm H
    [--endpoint SERVICE/CHARACTERISTIC] [--mode acknowledged|queued] [--seconds 5] [--dpi 203] [--run-id ID]
    image requires --file PATH; test-label accepts --artwork PATH
printer-bench preview --width-mm W --height-mm H --output NEW.png [--artwork PATH] [--run-id ID] [--dpi 203]

Width is across the print head. Height is the feed length.
Each print command scans again, connects to the selected UUID, inspects it, and submits exactly one job.
rongta-status only queries the printer. rongta-mark brackets one black square and ID label with status queries and logs raw replies.
"""

private struct Options {
    let command: String
    let values: [String: String]

    init(_ args: [String]) throws {
        command = args.first ?? "help"
        let printOptions = ["--device", "--seconds", "--model", "--width-mm", "--height-mm", "--dpi", "--endpoint", "--mode", "--run-id"]
        let allowed: [String: [String]] = [
            "scan": ["--match", "--seconds"], "inspect": ["--device", "--seconds"],
            "rongta-status": ["--device", "--seconds", "--endpoint", "--mode"],
            "rongta-mark": printOptions.filter { $0 != "--model" },
            "smoke": printOptions, "test-label": printOptions + ["--artwork"], "image": printOptions + ["--file"],
            "preview": ["--width-mm", "--height-mm", "--dpi", "--output", "--artwork", "--run-id"],
            "help": [], "--help": [], "-h": []
        ]
        guard let flags = allowed[command] else { throw BenchError("Unknown command \(command).\n\(usage)") }
        var result: [String: String] = [:]
        var index = 1
        while index < args.count {
            let key = args[index]
            guard flags.contains(key), result[key] == nil, index + 1 < args.count, !args[index + 1].hasPrefix("--") else {
                throw BenchError("Unknown, repeated, or incomplete option \(key).\n\(usage)")
            }
            result[key] = args[index + 1]
            index += 2
        }
        values = result
    }

    func require(_ key: String) throws -> String {
        guard let value = values[key], !value.isEmpty else { throw BenchError("Missing \(key).\n\(usage)") }
        return value
    }

    func stock() throws -> LabelStock {
        guard let width = Double(try require("--width-mm")), let height = Double(try require("--height-mm")),
              let dpi = Int(values["--dpi"] ?? "203") else { throw BenchError("Invalid stock dimensions or DPI.") }
        return try LabelStock(widthMM: width, heightMM: height, dpi: dpi)
    }
}

private func loadImage(_ path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw BenchError("Cannot decode image \(path).") }
    return image
}

private func savePNG(_ image: CGImage, dpi: Int, path: String) throws {
    let buffer = NSMutableData()
    guard let sink = CGImageDestinationCreateWithData(buffer, UTType.png.identifier as CFString, 1, nil) else {
        throw BenchError("Cannot create PNG.")
    }
    let pixelsPerMeter = Int((Double(dpi) / 0.0254).rounded())
    let properties: [CFString: Any] = [
        kCGImagePropertyDPIWidth: dpi,
        kCGImagePropertyDPIHeight: dpi,
        kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGXPixelsPerMeter: pixelsPerMeter, kCGImagePropertyPNGYPixelsPerMeter: pixelsPerMeter]
    ]
    CGImageDestinationAddImage(sink, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(sink) else { throw BenchError("Cannot encode PNG.") }
    try (buffer as Data).write(to: URL(fileURLWithPath: path), options: .withoutOverwriting)
}

@main struct PrinterBench {
    @MainActor private static let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // Write each line immediately so a piped trace retains its order even if a run is interrupted.
    private static func writeLine(_ line: String, to stream: FileHandle = .standardOutput) {
        stream.write(Data((line + "\n").utf8))
    }

    @MainActor static func main() async {
        do { try await run(Options(Array(CommandLine.arguments.dropFirst()))) }
        catch {
            writeLine("\(timestamp.string(from: Date())) printer-bench: \(error.localizedDescription)", to: .standardError)
            exit(1)
        }
    }

    @MainActor private static func run(_ options: Options) async throws {
        let command = options.command, values = options.values
        if ["help", "-h", "--help"].contains(command) { writeLine(usage); return }
        let id = values["--run-id"] ?? LabelJob.newID()
        func fixture(_ stock: LabelStock) throws -> CGImage {
            try LabelRenderer.compose(artwork: values["--artwork"].map(loadImage), text: id, qrPayload: id, stock: stock)
        }
        if command == "preview" {
            let stock = try options.stock()
            try savePNG(fixture(stock), dpi: stock.dpi, path: options.require("--output"))
            writeLine("Rendered \(id)")
            return
        }
        guard let seconds = Double(values["--seconds"] ?? "5") else { throw BenchError("Invalid scan duration.") }
        let radio = BluetoothPrinter()
        radio.onEvent = { writeLine("\(timestamp.string(from: Date())) \($0)") }
        writeLine("Host \(ProcessInfo.processInfo.operatingSystemVersionString) · Core Bluetooth")
        if command == "scan" {
            let devices = try await radio.scan(seconds: seconds)
            let visible = devices.filter { device in values["--match"].map { device.name.localizedCaseInsensitiveContains($0) } ?? true }
            for device in visible {
                writeLine("\(device.id.uuidString)  \(device.name)  RSSI \(device.rssi)  \(device.advertisedServices.joined(separator: ","))")
            }
            writeLine("\(visible.count) matching peripheral(s)")
            return
        }
        guard let target = UUID(uuidString: try options.require("--device")) else { throw BenchError("Invalid peripheral UUID.") }
        var job: LabelJob?
        var preferred: WriteMode?
        if let raw = values["--mode"] {
            guard let parsed = WriteMode(rawValue: raw) else { throw BenchError("Unknown write mode.") }
            preferred = parsed
        }
        if command != "inspect" && command != "rongta-status" {
            let modelName = command == "rongta-mark" ? "rongta" : try options.require("--model")
            guard let model = PrinterModel(rawValue: modelName) else { throw BenchError("Unknown printer model.") }
            let stock = try options.stock()
            switch command {
            case "rongta-mark": job = try .rongtaMark(id: id, stock: stock)
            case "smoke": job = try .smoke(id: id, model: model, stock: stock)
            case "image": job = try .image(loadImage(options.require("--file")), id: id, model: model, stock: stock)
            default: job = try .image(fixture(stock), id: id, model: model, stock: stock)
            }
            writeLine("Requested \(command) · \(id) · \(model.name) · \(model.language) · \(stock.description) · paper unobserved")
        }
        let devices = try await radio.scan(seconds: seconds)
        guard let device = devices.first(where: { $0.id == target }) else { throw BenchError("Selected peripheral did not appear in the current scan.") }
        writeLine("Discovered \(device.name) · \(device.id) · RSSI \(device.rssi) · advertised \(device.advertisedServices.joined(separator: ","))")
        try await radio.connect(target)
        defer { radio.disconnect() }
        let endpoints = try await radio.inspect()
        if command == "inspect" { return }
        let endpoint = try PrinterEndpoint.select(for: job?.model ?? .rongta, in: endpoints, advertisedServices: device.advertisedServices, peripheralName: device.name, explicit: values["--endpoint"])
        if command == "rongta-status" || command == "rongta-mark" {
            writeLine("Status sample before any label")
            _ = try await radio.rongtaStatus(to: endpoint, mode: preferred)
        }
        guard let job else { return }
        let receipt = try await radio.submit(job, to: endpoint, mode: preferred)
        if command == "rongta-mark" {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            writeLine("Status sample after label submission")
            _ = try await radio.rongtaStatus(to: endpoint, mode: preferred)
            return
        }
        // Give the controller a chance to drain queued writes before this one-shot process exits.
        if receipt.mode == .queued || job.model == .labelife { try await Task.sleep(nanoseconds: 2_000_000_000) }
    }
}
