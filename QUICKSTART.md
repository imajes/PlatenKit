# Print from a native Swift iPhone app

The planned Whiplash iPhone app can import `PlatenKit` directly through Swift Package Manager. The package takes a rendered page, physical label dimensions and a run ID, and sends one job to the selected Bluetooth printer. The included SwiftUI bench is a working example. On the Mac, the Rongta printed an ID rendered as a ZPL bitmap on 4 × 2 inch stock, and the Labelife printed artwork and a scannable QR on 4 × 6 inch stock. Both printers still need the Whiplash iPhone trials in section 4. [Rongta image and trace](BenchRuns/2026-11-23-rongta-0036Z/README.md) · [Labelife paper results](README.md#physical-evidence)

## 1. Build and preview a label on the Mac

From the root checkout, use an installed Swift 6 toolchain on macOS 13 or later. These commands run the package tests and render a 4 × 6 inch Labelife design to a new PNG. They work with both printers switched off.

```zsh
cd WhiplashPrinting
swift test
preview_dir=$(mktemp -d "${TMPDIR:-/tmp}/whiplash-label.XXXXXX")
swift run printer-bench preview --width-mm 101.6 --height-mm 152.4 --run-id PK-PREVIEW --output "$preview_dir/label.png"
print -r -- "$preview_dir/label.png"
```

At 203 dpi the preview is 812 × 1,218 pixels. It contains `PK-PREVIEW` as text and QR, plus an asymmetric square for checking orientation. For a live Mac run, `printer-bench smoke` renders a fresh ID as a bitmap and requests one copy on the selected printer. [Print one Rongta label](README.md#rongta-bench) · [Print one Labelife label](README.md#print-one-labelife-label-from-the-mac)

## 2. Add the library to the iOS target

1. To try the existing integration, open `BenchApp/PrinterBench.xcodeproj`. When starting the Whiplash app after hardware acceptance, use an iOS **App** target with **Swift** as the language and a minimum deployment target of iOS 16 or later. This guide uses **SwiftUI** for the interface. [Apple’s app project guide](https://developer.apple.com/documentation/xcode/creating-an-xcode-project-for-an-app)
2. In the new app’s Xcode package dependency dialog, choose **Add Local** and select the root checkout’s **WhiplashPrinting** folder containing `Package.swift`. Add the **PlatenKit** library product to the application target. Use a path relative to the app project so other checkouts and build machines can resolve it. The bench already links the product this way. [Bench project configuration](BenchApp/project.yml) · [Apple’s package dependency guide](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app)
3. In the app target’s **Info** settings, add `NSBluetoothAlwaysUsageDescription` with a reason such as “Find your selected label printer and send a label when you request one.” For a generated `Info.plist`, the equivalent build setting is `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription`. The first user-initiated scan can prompt for Bluetooth access. [Apple’s Bluetooth permission key](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription)

## 3. Wire Scan, Connect, Print and Disconnect

Keep one session on the main actor across the printer picker and the saved-box screen. Display the `NearbyPrinter` results from the latest scan, let the operator choose one by name and ID, and pass that result to `connect`. On this bench, `AM-243Z-BT-5AD6` is the Labelife and `RP421-A8C5` is the Rongta. Use the identifier from the current host’s scan, the matching model and the stock actually loaded.

| Bench printer | Swift model | Width across head × length along feed | Bench resolution |
| --- | --- | --- | --- |
| Labelife AM-243-BT / PM-241-BT | `.labelife` | 101.6 × 152.4 mm (4 × 6 in) | 203 dpi |
| Rongta RP421A | `.rongta` | 101.6 × 50.8 mm (4 × 2 in) | 203 dpi |

```swift
import CoreGraphics
import Foundation
import SwiftUI
import PlatenKit

@MainActor
final class BoxLabelPrinter: ObservableObject {
    @Published private(set) var nearby: [NearbyPrinter] = []
    private let radio = BluetoothPrinter()
    private var selection: (id: UUID, model: PrinterModel, endpoint: PrinterEndpoint)?

    init(log: @escaping (String) -> Void) {
        radio.onEvent = log
    }

    func scan() async throws {
        nearby = []
        nearby = try await radio.scan()
    }

    func connect(_ device: NearbyPrinter, model: PrinterModel) async throws {
        try await radio.connect(device.id)
        do {
            let endpoints = try await radio.inspect()
            let endpoint = try PrinterEndpoint.select(
                for: model, in: endpoints,
                advertisedServices: device.advertisedServices, peripheralName: device.name
            )
            selection = (device.id, model, endpoint)
        } catch {
            disconnect()
            throw error
        }
    }

    func printOne(page: CGImage, stock: LabelStock, runID: String) async throws -> Submission {
        guard let selection, radio.connectedID == selection.id else {
            throw BenchError("Select and connect to a printer before printing.")
        }
        let job = try LabelJob.image(page, id: runID, model: selection.model, stock: stock)
        return try await radio.submit(job, to: selection.endpoint)
    }

    func disconnect() {
        selection = nil
        nearby = []
        radio.disconnect()
    }
}
```

In the SwiftUI view that owns the packing flow, declare `@StateObject private var printer = BoxLabelPrinter(log: { print($0) })`. This keeps the session alive as views redraw. Pass the same object to the picker and saved-box screen using `@ObservedObject`. The example logs to the debug console. Supply the app’s journal callback to keep a record across launches. [SwiftUI ownership in the bench](BenchApp/App/PrinterBenchApp.swift) · [Apple’s StateObject guide](https://developer.apple.com/documentation/swiftui/stateobject)

On **Scan**, call `try await printer.scan()` and display `printer.nearby`. Disable duplicate taps while each async action is in progress. Disconnect before scanning for another printer. After a link drops, scan, select and inspect again. The adapter handles packet sizing, write acknowledgments and flow control. [Working iPhone session and journal](BenchApp/App/BenchState.swift)

From the **Print** action, generate a fresh `LabelJob.newID()` and record it before submission. For the physical acceptance trial, put that ID in the text and QR. For a box label, the visible text and QR payload can carry the stable box identifier while the run ID identifies this particular print attempt.

```swift
@MainActor
func printTrial(using printer: BoxLabelPrinter, runID: String, stock: LabelStock,
                artwork: CGImage? = nil, font: LabelFont? = nil,
                artworkMode: LabelImageMode = .lineArt) async throws -> Submission {
    let page = try LabelRenderer.compose(artwork: artwork, text: runID, qrPayload: runID,
                                         stock: stock, font: font, artworkMode: artworkMode)
    return try await printer.printOne(page: page, stock: stock, runID: runID)
}
```

For the Labelife stock above, construct `try LabelStock(widthMM: 101.6, heightMM: 152.4, dpi: 203)`. If the app already composes a complete label, pass its `CGImage` directly to `printOne`. Rasterize upstream SVG artwork to a `CGImage` before passing it to `compose` or `printOne`.

For a photograph of a box or its contents, pass the photograph as `artwork` and set `artworkMode: .photo`. Whiplash dithers the photograph at its final printed size and draws the title and QR separately. Use the default `.lineArt` for logos and monochrome artwork. In the iPhone bench, choose the image and select **Artwork type → Photograph** to exercise the same code. [Offline preview and physical comparison](README.md#print-photographs)

For an exact typeface, pass `try LabelFont(postScriptName: "Karla", weight: 275)` as the `font` argument. Swift Package Manager includes the upright Karla variable font with the library on both platforms. An installed or app-registered face can be selected by its full PostScript name, such as `Courier-Bold`. A font shipped in your app’s resources or imported from Files can also be loaded directly with `try LabelFont(data: Data(contentsOf: url))`. Add `weight:` when using a variable weight axis. This file-based path reads the font into memory for rendering. For ID-only jobs, pass the same font to `LabelJob.smoke(id:model:stock:font:)`. [Mac preview and bench commands](README.md#choose-the-label-font) · [Apple’s font file guidance](https://developer.apple.com/documentation/uikit/adding-a-custom-font-to-your-app)

To set a physical title size, use `try LabelFont(postScriptName: "Karla", weight: 275, pointSize: 24)`. The size is in typographic points (72 per inch). The same choice works with a font loaded from data. The default fits the title automatically. With an explicit size, a title that does not fit raises an error before submission. [203 dpi size comparison](Examples/Fonts/Karla-print-sizes.png)

## 4. Verify paper on a real iPhone

Open `BenchApp/PrinterBench.xcodeproj` and select the **PrinterBench** scheme. Under **Signing & Capabilities**, choose your development team and a bundle identifier your team can sign. Select your iPhone as the run destination and run the app. [Build the standalone harness](README.md#build-and-verify)

Release the printer from any vendor app or other bench session before scanning. In the harness, choose the model, tap **Scan nearby**, select the unit, then **Connect and inspect**. If discovery fails, check Bluetooth permission for this app and repeat the scan with the unit awake. Leave **Match printer profile** selected on these bench units. If selection is ambiguous, inspect the reported services before choosing an endpoint. Choose **Print artwork, text and QR** for each acceptance label. For a separate ID-only test, **Print ID only** calls the same `LabelJob.smoke` bitmap path used by the Mac CLI. [iPhone harness](BenchApp/App/PrinterBenchApp.swift)

For each printer, request one label on the initial connection, one after reconnecting, and one after restarting the printer and relaunching the harness. Each request gets a fresh ID. Check exactly one label emerged from the selected unit, the text and artwork are legible, and scanning the paper QR returns that ID. Under **Paper check**, enter those observations, tap **Record observation**, then use **Share full journal** to export the result.

A `Submission` records `runID`, `mode`, `bytes` and `chunks`. An acknowledged write reached the Bluetooth endpoint. A queued write was handed to the host Bluetooth stack. If submission is interrupted after bytes were handed over, show the uncertain outcome, check the paper and leave reprinting to an explicit operator action.

## 5. Print a label from a saved box

When both printers pass the iPhone trials, bind **Print label** on the saved-box screen to the shared session. Give `LabelRenderer.compose` the box title, any artwork, and the saved box ID as its QR payload. Give `printOne` the composed page, the selected stock and a fresh run ID. Store the submission or error against that attempt. A deliberate reprint uses the same box record and QR payload with a new run ID.

Verify that launching the app, selecting a unit and reconnecting each produce zero labels. One explicit Print action should produce exactly one label on the selected unit. Beads tracks the Rongta proof in `whiplash-570.3`, the Labelife proof in `whiplash-99r`, and this app integration in `whiplash-570.6`.
