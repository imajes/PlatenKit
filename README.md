# WhiplashPrinting

A standalone Swift package for native Bluetooth label printing on macOS and iOS. The Mac command-line tool and the iPhone bench app use the same transport, renderer and printer adapters. The Labelife AM-243-BT has produced a QR label and an ID-only label from the Mac. Physical trials from the Whiplash iPhone app are the next milestone.

To use the library directly in a native Swift app, follow the [iPhone integration quickstart](QUICKSTART.md). It covers an offline preview, adding the local package in Xcode, owning a printer session in SwiftUI, and verifying the result on paper.

## Print one Labelife label from the Mac

The bench unit advertises as `AM-243Z-BT-5AD6`. Its sticker says AM-243-BT and its hardware identifier is PM-241-BT. The loaded stock is 4 inches across the print head and 6 inches along the feed, or 101.6 × 152.4 mm. The manufacturer’s iPhone app printed successfully. Disconnect that app before using the bench. The Mac connected from the probe with its Bluetooth Settings left alone.

Run these commands from the package directory. Copy the UUID reported by this Mac into `printer_id`. Scan and inspect are read-only. The last command prints one plain label with a fresh ID.

```zsh
swift run printer-bench scan --match 243
printer_id='UUID-FROM-THIS-MACS-SCAN'
swift run printer-bench inspect --device "$printer_id"
swift run printer-bench smoke --model labelife --device "$printer_id" --width-mm 101.6 --height-mm 152.4
```

To print the design used for the QR proof, make a separate request. The default artwork is an outlined square marked in one corner so orientation is visible. `--artwork path.png` supplies different artwork.

```zsh
swift run printer-bench test-label --model labelife --device "$printer_id" --width-mm 101.6 --height-mm 152.4
```

To preview the design offline, supply a new PNG filename. To print a fully composed page, use `image`. The image command preserves its contents, so its journal ID can differ from text already present in the image.

```zsh
swift run printer-bench preview --width-mm 101.6 --height-mm 152.4 --run-id WL-CONTROL --output control.png
swift run printer-bench image --model labelife --device "$printer_id" --width-mm 101.6 --height-mm 152.4 --file control.png
```

## Physical evidence

The Mac runs below took place on November 20, 2026, on macOS 27.3 (26C5047e) using Core Bluetooth. The bench generated jobs at 203 dpi. Each Bluetooth print started from a fresh scan of the selected printer. The Labelife roll was 4 × 6 inches. The Rongta roll was 4 inches wide by 2 inches high (101.6 × 50.8 mm).

| Unit and run | Submission | Observed paper |
| --- | --- | --- |
| Labelife, vendor iPhone app | Manufacturer app test | James confirmed a successful print. |
| Labelife, `WL-L1-1904` | TSPL native text, 105 bytes acknowledged | No movement. The current ID-only command renders its text as a bitmap. |
| Labelife, `WL-L2-QR-1906` | TSPL mode-4 artwork, text and QR, 17,091 bytes in 71 acknowledged writes | Exactly one good label. James scanned the paper QR and read `WL-L2-QR-1906`. |
| Labelife, `WL-L3-1920` | Reconnected, selected the default profile, sent a raster ID, 3,302 bytes in 15 acknowledged writes | Exactly one readable label bearing `WL-L3-1920`. |
| Rongta RP421A, `WL-R1-1842` | ZPL, 42 bytes acknowledged on `18F0/2AF1` | Stock advanced with a blank or incorrect label. The vendor iPhone app could also advance stock. |
| Rongta RP421A, `WL-R2-2122` | One 88-byte ZPL write for a centered black square and ID, acknowledged on `18F0/2AF1`. The SDK status query received zero reply bytes before and after. | James saw the paper feed and confirmed that the label had no marks. [Timestamped trace and paper observation](BenchRuns/2026-11-20-rongta-2117Z/README.md) |
| Rongta RP421A, power-on self-test | The Mac had disconnected. James used the FEED button and power switch. | Stock advanced with at most a tiny line, followed by motor or roller noise. The thermal face darkened when scratched and was loaded face up. James found the visible path and roller clear. |

On November 22, the Rongta printed its built-in self-test with the correct power supply. The photographed page reports `RP421`, firmware `V4.31` (2024-01-30), ZPL and 203 dpi. James recalls that page was on the larger roll. He repeated the self-test on the confirmed 4 × 2 inch roll, where it printed on one label and stopped at its end. On the same stock and supply, the Mac’s `WL-R3-2350` on `18F0/2AF1` and `WL-R4-2359` on `FF00/FF02` each received an 88-byte write acknowledgement and fed completely blank paper. [Self-test and first endpoint](BenchRuns/2026-11-22-rongta-2349Z/README.md#built-in-self-test-on-both-rolls) · [Second endpoint and trace](BenchRuns/2026-11-22-rongta-2359Z/README.md)

James then confirmed a physical iPhone print from **RT Elabel**, the app Rongta lists for the RP421A. He selected ZPL in the app. Its published version history also documents a TSPL default for the RP421 profile. On the 4 × 2 inch roll the Mac subsequently sent one native text ID per language through `18F0/2AF1`. [RT Elabel evidence and both text traces](BenchRuns/2026-11-23-rongta-0025Z/README.md) · [Publisher’s version history](https://apps.apple.com/us/app/rt-elabel/id6714471637)

### Labelife wire format

The selected unit advertised `1812` and `AF30`. Service discovery after connecting found `FF00/FF02` for writes and `FF00/FF03` for notifications. Automatic selection checks the AM-243 or PM-241 Bluetooth model name and the properties of both characteristics. The CLI accepts an explicit service/characteristic from the current inspection for a separately identified variant.

The adapter subscribes to `FF03` before sending the job. The printer initially granted seven write credits (`01 07`) and reported a 244-byte packet limit (`02 F4 00`). One credit permits one packet. The component waits for new credits as needed and also enforces Core Bluetooth’s write limit and flow control for the selected write mode. Both verified runs used writes with response. Ordinary print messages, including `SSSGETPRINTING:DOING` and `Cmd error` lines, are assembled across notifications and appear in the journal. The component sends no status poll. This unit rejected explicit polling during the bench tests.

The TSPL job sets page dimensions and direction, clears the image buffer, sends `BITMAP 0,0,<row bytes>,<rows>,4,`, then issues `PRINT 1,1` once. The adapter packs the image MSB first with a zero for ink and white row padding. Each 4,096-byte slice is independently LZO1X encoded and prefixed with its compressed length as a 32-bit little-endian integer. A zero length terminates the stream. This matches the local manufacturer’s AM-243-BT and PM-241-BT-Bluetooth driver profiles. The 4 × 6 design is 812 × 1,218 dots with a 102-byte stride. The Swift encoder runs on both platforms without an external compression library.

### Rongta bench

Find the unit by name and take its UUID from this Mac’s current scan.

```zsh
swift run printer-bench scan --match RP421 --seconds 15
printer_id='UUID-FROM-THIS-MACS-SCAN'
```

To compare command languages, print a single text ID near the top-left of the 4 × 2 inch stock. Choose `zpl` or `tspl` for one run at a time. This option selects the encoding on the Mac. Each invocation sends one text label with the current media settings and passively logs the outgoing bytes, write acknowledgements and incoming notifications. The TSPL job uses the printer’s built-in font.

```zsh
swift run printer-bench smoke --model rongta --device "$printer_id" --language zpl --endpoint 18F0/2AF1 --width-mm 101.6 --height-mm 50.8
```

The status command connects, subscribes to the SDK’s matching reply characteristic and sends an 11-byte `~HQPRNSTA\r\n` query. The SDK documents this query for the related RP410. On the RP421A bench unit the Mac successfully subscribed to both documented channels present on the printer. Each acknowledged the query and returned zero notification bytes during the three-second observation window. These traces establish the Bluetooth exchange. The unit’s error state and internal job history remain unknown. [Status traces](BenchRuns/2026-11-20-rongta-2117Z/README.md)

```zsh
swift run printer-bench rongta-status --device "$printer_id" --endpoint 18F0/2AF1 --seconds 15
```

For a separately requested paper test, `rongta-mark` sends one ZPL format containing a solid 64-dot square and a separate text ID on the 4 × 2 inch stock. It preserves the printer’s existing media and darkness settings. It keeps the receive channel open before, during and after submission, including a status query on each side of the print. Run IDs are generated automatically unless `--run-id` is supplied. Use a fresh log filename for each run.

```zsh
set -o pipefail
swift run printer-bench rongta-mark --device "$printer_id" --endpoint 18F0/2AF1 --width-mm 101.6 --height-mm 50.8 --seconds 15 2>&1 | tee "rongta-$(date -u +%Y%m%dT%H%M%SZ).log"
```

`HOST TX` shows the exact bytes submitted, `GATT ACK` records the Bluetooth write callback, and `PRINTER RX` records each notification delivered from the selected reply channel in hex and escaped text. Record the paper observation alongside the trace. The SDK maps `18F0/2AF1` to `18F0/2AF0`, `FF00/FF02` to `FF00/FF01`, and `FFE0/FFE1` to itself. Automatic selection uses the advertised service when it resolves an ambiguity. An explicit endpoint must exist in the current inspection.

If a label feeds entirely blank, the RP421A can print a self-test independently of the Mac. With the roll loaded and the lid closed, turn the printer off, hold FEED while switching it on, then release FEED after power-on. Record whether the printer marked the paper and any firmware version, command mode or resolution shown on the page. The shipping-model guide lists Bluetooth, ZPL, 203 dpi and a 24 V DC, 2.5 A adapter. The case label and the self-test identify the actual unit. [Rongta RP421A shipping manual, printed pages 8, 25 and 26](https://cdn.shopify.com/s/files/1/0933/9538/6655/files/40800507RP421A-_-V1.5.pdf?v=1791877401)

## Use the Swift library

Add the local package and depend on its `WhiplashPrinting` product. Keep one `BluetoothPrinter` on the main actor. Call `scan()` when the operator asks, display its results and retain the selected `NearbyPrinter` on that same instance. Invoke the following from an explicit print action. Upstream SVG artwork can be rendered to a `CGImage` before calling the component.

```swift
import CoreGraphics
import WhiplashPrinting

@MainActor
func printBox(_ runID: String, artwork: CGImage?, selected: NearbyPrinter,
              using radio: BluetoothPrinter) async throws -> Submission {
    let stock = try LabelStock(widthMM: 101.6, heightMM: 152.4, dpi: 203)
    let page = try LabelRenderer.compose(artwork: artwork, text: runID, qrPayload: runID, stock: stock)
    let job = try LabelJob.image(page, id: runID, model: .labelife, stock: stock)
    try await radio.connect(selected.id)
    defer { radio.disconnect() }
    let endpoints = try await radio.inspect()
    let endpoint = try PrinterEndpoint.select(for: .labelife, in: endpoints,
                                              advertisedServices: selected.advertisedServices,
                                              peripheralName: selected.name)
    return try await radio.submit(job, to: endpoint)
}
```

Supply `LabelJob.newID()` for a fresh bench ID. Existing IDs accept 1–32 ASCII letters, digits, hyphens or underscores. `LabelJob.image` aspect-fits a complete page onto white stock. `compose` adds caller text, artwork and a QR before thresholding. `Submission` reports the run ID, byte count, chunk count and whether the transport acknowledged or queued the writes. Set `radio.onEvent` to record connection events, device messages and errors. If a disconnect or timeout occurs after any bytes were submitted, the component reports an uncertain outcome. Check the paper before explicitly requesting another label.

## Build and verify

Use Swift 6 with the macOS and iOS SDKs. The package targets macOS 13 and iOS 16 or later and has no external package dependencies. From this directory, the following commands exercise the component without accessing a printer.

```zsh
swift test
swift build -c release
swift run printer-bench help
```

The tests cover complete Labelife pages, LZO block boundaries and byte polarity, odd-width padding, ZPL field limits, supplied artwork, QR module layout, profile selection, packet credits, queued and acknowledged writes, cancellation, stale completions and interrupted submissions. The Rongta diagnostics tests check the SDK query bytes, the three mapped reply endpoints, the byte-for-byte trace display and the single-format 4 × 2 inch mark. An independent bench check also decompressed the actual Labelife QR job with liblzo2, compared every raster dot with the PNG, and decoded the QR from those bytes. liblzo2 is only needed to repeat that independent comparison.

The included Xcode project references the package locally. With device support, a development identity and the matching profile already available, build the iPhone target using the shared scheme.

```zsh
xcodebuild -project BenchApp/PrinterBench.xcodeproj -scheme PrinterBench -destination 'generic/platform=iOS' build
```

The app uses the Whiplash development team, bundle ID `app.smokeclouds.whiplash.printerbench`, and a Bluetooth usage description. Building, launching and scanning produce zero labels. Installing on a phone, pairing, changing developer-account settings, or installing system components requires James’s separate approval. On this Mac, even Xcode device enumeration previously attempted a support-package install.

## Real iPhone acceptance

Select the model, tap **Scan nearby**, choose the unit, then **Connect and inspect**. Leave **Match printer profile** selected for this Labelife. Use **Print artwork, text and QR** for each acceptance run. The app saves its journal across launches. Use **Paper check** to record the label count, readable text and artwork, and the QR scanned from the label. **Share full journal** exports the results.

For each printer, make three separately requested prints with fresh IDs: initial connection, after disconnecting and reconnecting, and after restarting the printer and relaunching the app. Each request must produce exactly one label on the selected unit, with the QR decoding to its run ID. Log host OS, app and firmware versions when known, stock, transport, command language, discovery, endpoint, write result, and physical observation.

Beads `whiplash-99r` holds the Labelife runs, `whiplash-570.3` holds the Rongta runs, and `whiplash-570.7` holds the shared software. Both real-iPhone proofs are prerequisites for `whiplash-570.6`, the Whiplash UI integration.
