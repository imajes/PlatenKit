import SwiftUI
import UniformTypeIdentifiers
import WhiplashPrinting

@main struct PrinterBenchApp: App {
    var body: some Scene { WindowGroup { BenchView() } }
}

private struct BenchView: View {
    @StateObject private var bench = BenchState()
    @State private var pickingFile = false
    @State private var fileType: UTType = .image

    var body: some View {
        NavigationStack {
            Form {
                Section("Printer") {
                    Picker("Model", selection: $bench.model) {
                        ForEach(PrinterModel.allCases) { Text($0.name).tag($0) }
                    }.disabled(bench.connected || bench.busy)
                        .onChange(of: bench.model) { _ in bench.selectModel() }
                    Button("Scan nearby", action: bench.scan).disabled(bench.connected || bench.busy)
                    Picker("Discovered device", selection: $bench.deviceID) {
                        Text("Select device").tag(nil as UUID?)
                        ForEach(bench.devices) { device in
                            Text("\(device.name) · \(device.id.uuidString.prefix(8))").tag(Optional(device.id))
                        }
                    }.disabled(bench.connected || bench.busy)
                    if bench.connected {
                        Button("Disconnect", action: bench.disconnect).disabled(bench.busy)
                    } else {
                        Button("Connect and inspect", action: bench.connect).disabled(bench.deviceID == nil || bench.busy)
                    }
                    if bench.busy { ProgressView() }
                }
                if bench.connected {
                    Section("Bluetooth write") {
                        Picker("Endpoint", selection: $bench.endpointID) {
                            Text("Match printer profile").tag("")
                            ForEach(Array(bench.endpoints.filter(\.writable).enumerated()), id: \.offset) { _, endpoint in
                                Text(endpoint.description).tag(endpoint.id)
                            }
                        }
                        Picker("Write mode", selection: $bench.mode) {
                            Text("From properties").tag("")
                            ForEach(WriteMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0.rawValue) }
                        }
                    }.disabled(bench.busy)
                    Section("One test label") {
                        numeric("Width across head (mm)", $bench.width)
                        numeric("Length along feed (mm)", $bench.height)
                        numeric("Resolution (dpi)", $bench.dpi)
                        Picker("Trial", selection: $bench.trial) {
                            ForEach(["Initial connection", "After reconnect", "After power cycle and app relaunch"], id: \.self) { Text($0) }
                        }
                        if bench.fontFilename.isEmpty {
                            LabeledContent("Font") {
                                TextField("Helvetica-Bold", text: $bench.fontName)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled().multilineTextAlignment(.trailing)
                            }
                        } else {
                            LabeledContent("Font file", value: bench.fontFilename)
                            Button("Use a named font", action: bench.clearFontFile)
                        }
                        LabeledContent("Variable weight") {
                            TextField("Font default", text: $bench.fontWeight).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Size (pt)") {
                            TextField("Auto fit", text: $bench.fontSize).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                        Button("Choose font file") { fileType = .font; pickingFile = true }
                        Button(bench.artworkName.isEmpty ? "Choose artwork (optional)" : bench.artworkName) { fileType = .image; pickingFile = true }
                        if !bench.artworkName.isEmpty {
                            Picker("Artwork type", selection: $bench.artworkMode) {
                                Text("Line art").tag(LabelImageMode.lineArt)
                                Text("Photograph").tag(LabelImageMode.photo)
                            }
                        }
                        Button("Print ID only") { bench.printOne(rich: false) }
                        Button("Print artwork, text and QR") { bench.printOne(rich: true) }
                    }.disabled(bench.busy)
                }
                if !bench.lastID.isEmpty {
                    Section("Paper check · \(bench.lastID)") {
                        TextField("Count, legibility and scanned QR", text: $bench.observation, axis: .vertical)
                        Button("Record observation", action: bench.recordPaper).disabled(bench.observation.isEmpty || bench.busy)
                    }
                }
                if !bench.journal.isEmpty {
                    Section("Bench journal") {
                        ShareLink("Share full journal", item: bench.journal)
                        Text(bench.journal.split(separator: "\n").suffix(16).joined(separator: "\n"))
                            .font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Printer bench")
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: [fileType]) { result in
                switch result {
                case .success(let url):
                    if fileType == .font { bench.importFont(url) } else { bench.importArtwork(url) }
                case .failure(let error): bench.record(error.localizedDescription)
                }
            }
        }
    }

    private func numeric(_ title: String, _ value: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField(title, text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }
}
