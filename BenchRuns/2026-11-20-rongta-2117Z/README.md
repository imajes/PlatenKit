# Rongta RP421A blank-label investigation

On November 20, 2026, at 15:25 CST, James observed that the Rongta fed paper for `WL-R2-2122` and left it completely blank. The label requested a solid black square and an independent text ID. The Mac received a successful Bluetooth write callback for all 88 label bytes. The printer sent no notification on the subscribed reply characteristic during this connection. [Complete print trace](05-WL-R2-2122.log)

| Bench detail | Observation |
| --- | --- |
| Host and unit | macOS 27.3 build 26C5047e, Core Bluetooth LE, Rongta RP421A advertised as `RP421-A8C5`. The successful print connection began at RSSI −56 dBm. |
| Stock and language | 4 inches across the head by 2 inches along the feed (101.6 × 50.8 mm). ZPL is on the sticker. The job was laid out for 812 × 406 dots at 203 dpi. The printer’s configured mode, resolution and firmware were unverified. |
| Format | Black 64 × 64 dot square at (374, 141), native font 0 for `WL-R2-2122` starting at (206, 225), CRLF line endings, one `^PQ1` and one `^XZ`. No density, stock calibration or saved configuration commands. |
| Print write | At 21:25:52.796 UTC the Mac submitted one 88-byte write on `18F0/2AF1`. Core Bluetooth acknowledged it at 21:25:52.822 UTC. The negotiated with-response limit was 512 bytes. |
| Printer-originated status | The Mac subscribed to `18F0/2AF0` before sending anything. The vendor SDK query `~HQPRNSTA\r\n` was acknowledged before and after the label. Each observation continued for three seconds after its write completed. Zero notification bytes arrived during the connection. |
| Physical result | Paper advanced. James saw neither a black square nor text. The earlier 42-byte `WL-R1-1842` test had also advanced paper with blank or incorrect output. |

## Other captures

- [Service inspection](01-inspect.log) identifies the two documented write and receive pairs present on this RP421A. The third pair listed by the SDK, `FFE0/FFE1`, was absent.
- [Advertised service status query](02-status-18F0.log) and [alternate service status query](03-status-FF00.log) show successful notification subscriptions, acknowledged queries and zero replies in both observation windows. The local SDK header names the RP410 for this query. Its support on the RP421A is unconfirmed.
- [First scan for the mark](04-WL-R2-2122.log) expired before the target appeared. That invocation made zero connections and zero writes. The 15-second scan in the [print trace](05-WL-R2-2122.log) found the selected unit and submitted the only label of this session.

## What happened with the Mac disconnected

James started the self-test from the printer’s own FEED button and power switch. It advanced stock, made at most a tiny line, then sounded like a motor or roller struggling. There was no readable test page or countable buzzer code. Firmware and configured command mode could not be read. The same failure to make a readable mark can occur without a Bluetooth job. The tests do not identify a failed part.

A fingernail darkened the exposed face of a loose label. James checked the open printer and confirmed that this heat-sensitive face was up toward the head, the stock lay flat, and the visible paper path and roller looked clear.

After cleaning, James observed that the printer could feed stock and locate a label edge. During the built-in self-test the leading edge advanced a short distance, then stopped while the motor-like sound continued. The paper’s movement was observable. Whether the roller kept turning at that point is unknown.

In James’s open-printer photo, the small turquoise slider with the dark window in the lower clear track matches the adjustable optical media sensor. The two larger turquoise pieces are the paper guides. The black cylinder across the front is the platen roller with a white drive gear at its right end. The fixed, full-width thermal head is in the lid opposite that roller. [RP421A inside-view drawing, page 7](https://file.globalso.com/file_manage/4365/20260226/rp421a-user-manual_v1-2_en.pdf#page=7)

## November 22 follow-up with the correct power supply

James found a different power supply connected to the Rongta. The 2.5 A rating he reported earlier was for the adapter he thought was connected. After switching to the correct supply, he reported good print output. The source of that print and its label dimensions were unrecorded. Rongta specifies 24 V DC, 2.5 A for this model. [RP421A shipping manual, printed pages 8, 25 and 26](https://cdn.shopify.com/s/files/1/0933/9538/6655/files/40800507RP421A-_-V1.5.pdf?v=1791877401)

Once the 4 × 2 inch roll is back in the printer, repeat the Mac Bluetooth test with the same ZPL square, a fresh run ID and the correct supply. Record the write trace and check the paper for both the square and the ID so the result can be compared with `WL-R2-2122`.
