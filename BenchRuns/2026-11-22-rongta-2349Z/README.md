# Rongta RP421A on 4 × 2 inch stock with the correct power supply

On November 22, 2026, at 17:50 CST, the Mac sent one ZPL label with a solid black square and the text `WL-R3-2350`. James saw paper advance and confirmed it came out completely blank. The run used the correct power supply and the smaller labels, 4 inches across the print head and 2 inches along the feed. [Print trace](03-WL-R3-2350.log)

| Stage | Observation |
| --- | --- |
| Discovery | On macOS 27.3 (26C5047e), Core Bluetooth found one `RP421-A8C5` with ID `A5EA084A-DEF8-8782-D233-0A30DBE64C89`, advertising `FEE7` and `18F0` at −57 dBm. The first attempt was confined to a sandbox that could not access the controller. [Initial attempt](01-sandbox-scan.log) · [Mac scan](02-scan.log) |
| Connection | The print command scanned again, saw the unit at −62 dBm, connected, inspected its services and subscribed to `18F0/2AF0`. |
| Label | The 101.6 × 50.8 mm layout at 203 dpi placed a 64-dot square at (374, 141) and the text at (206, 225). The ZPL format requested one copy. Firmware, active command mode and configured resolution were unverified during the run. |
| Write | Core Bluetooth acknowledged the 88-byte label in one write to `18F0/2AF1` at 23:50:46.519 UTC. The negotiated write limit was 512 bytes. |
| Status | The 11-byte status query was acknowledged before and after the label. Each three-second observation window received zero reply bytes. The Mac requested disconnect at 23:50:51.651 UTC. |
| Paper | The stock advanced. Neither the square nor the run ID appeared. |

Comparing the captured Bluetooth payloads with `WL-R2-2122` shows that the two jobs differed only in the run ID. Both produced blank paper. [Earlier run and power supply history](../2026-11-20-rongta-2117Z/README.md)

## Built-in self-test on both rolls

After changing to the correct supply, James photographed a clearly printed FEED-button self-test. He recalls the photographed sheet was the larger 4 × 6 inch stock. The page identifies the printer as `RP421`, firmware `V4.31` dated `2024-01-30`, command language `ZPL`, resolution `203` dpi and media type `label`. It lists a maximum print width of 104 mm. Both `DENSITY1` and `DENSITY2` read 8. The configured BLE name is `RP421-A8C5-B`. The Mac discovered `RP421-A8C5` during the Bluetooth trial.

After the blank `WL-R3-2350` job, James repeated the FEED-button self-test on the loaded 4 × 2 inch roll with the correct supply. The self-test printed on one short label and stopped at its end. This establishes that the printer can mark that stock under the same power and loading conditions as the blank Mac job.
