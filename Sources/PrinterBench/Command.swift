import Foundation
import ImageIO
import UniformTypeIdentifiers
import PlatenKit

private let usage = """
printer-bench scan [--match NAME] [--seconds 5]
printer-bench inspect --device UUID [--seconds 5]
printer-bench rongta-status --device UUID [--endpoint SERVICE/WRITE] [--mode acknowledged|queued] [--seconds 5]
printer-bench rongta-mark --device UUID --width-mm W --height-mm H [--run-id ID] [--endpoint SERVICE/WRITE] [--mode acknowledged|queued] [--seconds 5]
printer-bench smoke|test-label|image --device UUID --model rongta|labelife --width-mm W --height-mm H
    [--endpoint SERVICE/CHARACTERISTIC] [--mode acknowledged|queued] [--seconds 5] [--dpi 203] [--run-id ID]
    image requires --file PATH; test-label accepts --artwork PATH
    image and supplied artwork accept --image-mode line-art|photo. Photo dithers the picture at its print size.
    smoke renders an ID as a bitmap. On the Rongta, --language zpl|tspl selects a native-text diagnostic.
printer-bench preview --width-mm W --height-mm H --output NEW.png [--artwork PATH] [--run-id ID] [--dpi 203] [--monochrome]
    preview, test-label and raster smoke accept --font POSTSCRIPT-NAME or --font-file PATH, plus optional --font-weight INTEGER and --font-size-pt POINTS.
    Karla is bundled. Use --font Karla --font-weight 275 for its upright variable face.

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
        let fontOptions = ["--font", "--font-file", "--font-weight", "--font-size-pt"]
        let allowed: [String: [String]] = [
            "scan": ["--match", "--seconds"], "inspect": ["--device", "--seconds"],
            "rongta-status": ["--device", "--seconds", "--endpoint", "--mode"],
            "rongta-mark": printOptions.filter { $0 != "--model" },
            "smoke": printOptions + fontOptions + ["--language"], "test-label": printOptions + fontOptions + ["--artwork", "--image-mode"], "image": printOptions + ["--file", "--image-mode"],
            "preview": ["--width-mm", "--height-mm", "--dpi", "--output", "--artwork", "--image-mode", "--run-id", "--monochrome"] + fontOptions,
            "help": [], "--help": [], "-h": []
        ]
        guard let flags = allowed[command] else { throw BenchError("Unknown command \(command).\n\(usage)") }
        var result: [String: String] = [:]
        var index = 1
        while index < args.count {
            let key = args[index]
            guard flags.contains(key), result[key] == nil else { throw BenchError("Unknown or repeated option \(key).\n\(usage)") }
            if key == "--monochrome" {
                result[key] = "true"
                index += 1
                continue
            }
            guard index + 1 < args.count, !args[index + 1].hasPrefix("--") else {
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

    func font() throws -> LabelFont? {
        let pointSize = try values["--font-size-pt"].map { raw in
            guard let points = Double(raw) else { throw BenchError("Use a numeric size in points for --font-size-pt.") }
            return points
        }
        let weight = try values["--font-weight"].map { raw in
            guard let value = Int(raw) else { throw BenchError("Use an integer for --font-weight.") }
            return value
        }
        switch (values["--font"], values["--font-file"]) {
        case let (name?, nil): return try LabelFont(postScriptName: name, weight: weight, pointSize: pointSize)
        case let (nil, path?): return try LabelFont(data: Data(contentsOf: URL(fileURLWithPath: path)), weight: weight, pointSize: pointSize)
        case (.some, .some): throw BenchError("Choose one font source with --font or --font-file.")
        case (nil, nil):
            guard weight == nil else { throw BenchError("Choose --font or --font-file when specifying a weight.") }
            return try pointSize.map { try LabelFont(postScriptName: "Helvetica-Bold", pointSize: $0) }
        }
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
        let font = try options.font()
        guard let imageMode = LabelImageMode(rawValue: values["--image-mode"] ?? "line-art") else {
            throw BenchError("Use line-art or photo for --image-mode.")
        }
        if values["--image-mode"] != nil && command != "image" && values["--artwork"] == nil {
            throw BenchError("Supply --artwork when selecting its image mode.")
        }
        func fixture(_ stock: LabelStock) throws -> CGImage {
            try LabelRenderer.compose(artwork: values["--artwork"].map(loadImage), text: id, qrPayload: id, stock: stock, font: font, artworkMode: imageMode)
        }
        if command == "preview" {
            let stock = try options.stock()
            let page = try fixture(stock)
            let preview = try values["--monochrome"] == nil ? page : LabelRenderer.bitmap(from: page, stock: stock).makeImage()
            try savePNG(preview, dpi: stock.dpi, path: options.require("--output"))
            writeLine("Rendered \(id)" + (font.map { " · \($0.description)" } ?? ""))
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
            let label: LabelJob
            switch command {
            case "rongta-mark": label = try .rongtaMark(id: id, stock: stock)
            case "smoke":
                if let raw = values["--language"] {
                    guard let language = PrinterLanguage(rawValue: raw.uppercased()) else { throw BenchError("Use zpl or tspl for --language.") }
                    if model == .labelife && language == .tspl {
                        label = try .smoke(id: id, model: model, stock: stock, font: font)
                    } else {
                        guard font == nil else { throw BenchError("Omit --language to print a raster ID with the selected font.") }
                        label = try .smoke(id: id, model: model, stock: stock, language: language)
                    }
                } else {
                    label = try .smoke(id: id, model: model, stock: stock, font: font)
                }
            case "image": label = try .image(loadImage(options.require("--file")), id: id, model: model, stock: stock, mode: imageMode)
            default: label = try .image(fixture(stock), id: id, model: model, stock: stock)
            }
            job = label
            writeLine("Requested \(command) · \(id) · \(model.name) · \(label.language.rawValue) · \(stock.description) · paper unobserved")
            if let font { writeLine("Font \(font.description)") }
            if command == "image" || values["--artwork"] != nil { writeLine("Image mode \(imageMode.rawValue)") }
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
        let traceText = job.model == .rongta && values["--language"] != nil
        if traceText { try await radio.listenForRongtaReplies(to: endpoint) }
        let receipt = try await radio.submit(job, to: endpoint, mode: preferred)
        if command == "rongta-mark" {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            writeLine("Status sample after label submission")
            _ = try await radio.rongtaStatus(to: endpoint, mode: preferred)
            return
        }
        // Give the controller a chance to drain queued writes before this one-shot process exits.
        if traceText || receipt.mode == .queued || job.model == .labelife { try await Task.sleep(nanoseconds: 2_000_000_000) }
    }
}
