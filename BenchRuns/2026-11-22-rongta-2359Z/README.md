# Rongta 4 × 2 inch label on FF00/FF02

At 18:00 CST on November 22, 2026, the Mac sent `WL-R4-2359` to the Rongta RP421A through its second writable Bluetooth endpoint. James confirmed the stock advanced completely blank. Immediately before this trial, the printer’s built-in self-test put dark text on one label from the same 4 × 2 inch roll and stopped at the label boundary. The correct power supply was connected for both. [Self-test and first endpoint](../2026-11-22-rongta-2349Z/README.md) · [Second endpoint trace](01-WL-R4-2359.log)

| Stage | Observation |
| --- | --- |
| Discovery | macOS 27.3 (26C5047e), Core Bluetooth LE. A fresh scan found `RP421-A8C5` at −55 dBm, advertising `FEE7` and `18F0`. |
| Connection | The Mac connected, inspected the services, selected `FF00/FF02` for writes and subscribed to `FF00/FF01` for notifications. |
| Label | One ZPL format for 101.6 × 50.8 mm at 203 dpi. Comparing the captured hex with `WL-R3-2350` verified identical square, text position and copy count. Only the run ID differed in the label data. |
| Write | All 88 label bytes were acknowledged in one GATT write at 00:00:05.934 UTC on November 23. The negotiated write limit was 512 bytes. |
| Status | Each 11-byte status query was acknowledged. No reply bytes arrived in either three-second window. The Mac requested disconnect at 00:00:11.040 UTC. |
| Paper | Stock advanced. Neither the black square nor the ID appeared. The earlier `18F0/2AF1` job produced the same result. |

## Comparison with the vendor software

In the local Rongta iOS SDK, `PrinterManager.m` passes label width and height into the ZPL header builder. The SDK library contains `^PW`, `^LL` and `^GB` format strings. The sample’s `ZplPrint` text handler in `TextViewController.m` has an empty body. The two Mac diagnostic jobs used `^GB` and text with the printer’s current page settings. Whiplash’s raster encoder explicitly supplies `^PW812^LL406^LH0,0` for this stock. [Swift encoders](../../Sources/WhiplashPrinting/Labels.swift)

An offline check passed a 4 × 2 inch page through the shared renderer and Rongta image encoder. The resulting ZPL contained a single `^GFA` graphic with 41,412 raster bytes at a 102-byte stride. Extracting those bytes and unpacking the dots produced an 812 × 406 image whose QR decoded to `WL-R-PREVIEW`. Physical raster output remains unverified.

James subsequently identified **RT Elabel** as the Rongta iPhone app that produced a physical label. Earlier unsuccessful reports involved other apps. He selected ZPL in RT Elabel when prompted. [Vendor app evidence and subsequent Mac trials](../2026-11-23-rongta-0025Z/README.md)

## Planned USB comparison

James will connect the printer’s USB data port directly to the Mac when convenient. Keep the correct power supply and the same 4 × 2 inch roll in place. Identify the Rongta on USB and an existing route that can send raw ZPL. Use the captured 88-byte label format with a fresh, equal-length run ID and a single copy. The two Bluetooth status queries were separate writes and are outside the USB label payload.

Record whether the Mac detected the unit, how it submitted the bytes and whether the square and ID appeared on paper. A readable wired label would confirm that the printer accepts this ZPL format from an external host and narrow the next comparison to Bluetooth delivery. The USB trial is pending.
