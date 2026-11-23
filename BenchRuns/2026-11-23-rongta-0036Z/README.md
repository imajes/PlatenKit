# First Mac Bluetooth print on the Rongta RP421A

James confirmed that the Rongta printed when Whiplash sent `WL-G9-0035` as an image on the 4 × 2 inch roll. This was a text-only design. The program requested one copy. James reported “success!” after the write completed.

| Stage | Result |
| --- | --- |
| Setup | macOS 27.3 (26C5047e), Swift Mac bench, Core Bluetooth. Rongta RP421A with the correct supply and 101.6 mm across the head by 50.8 mm along the feed. The printer’s self-test reported RP421, V4.31 (2024-01-30), ZPL and 203 dpi. |
| Discovery | A fresh 15-second scan found `RP421-A8C5` at −58 dBm, advertising `FEE7` and `18F0`. |
| Connection | The Mac connected and inspected the services. It selected `18F0/2AF1` with write response, the same endpoint used in the earlier native text comparison. |
| Job | The Swift renderer drew the ID on an 812 × 406 dot page. The ZPL encoder set the width, length and origin, sent one `^GFA` field with 41,412 bytes of raster data at 102 bytes per row, and requested one copy with `^PQ1`. |
| Write | All 82,882 bytes were acknowledged in 162 writes with a 512-byte limit. The submission took 43 seconds, ending at 6:37:33 p.m. CST on November 22, 2026 (00:37:33 UTC on November 23). The Mac then requested disconnect. |
| Paper | James confirmed physical output. A later photograph shows the readable `WL-G9-0035` beneath the smaller Moon label. [Photographed print](../2026-11-23-moon-0132Z/paper.jpg) |

The watched native ZPL text job on this stock advanced one blank label. The TSPL text job produced no movement. The successful ZPL job changed both how the text was drawn and how the page dimensions and origin were specified. [Text comparison](../2026-11-23-rongta-0025Z/README.md) · [Self-test on both rolls](../2026-11-22-rongta-2349Z/README.md#built-in-self-test-on-both-rolls)

## Reproduce the print

The captured PNG is the input used by the Mac. From the package directory, scan with `swift run printer-bench scan --match RP421 --seconds 15` and set `printer_id` to the UUID shown for this Rongta. The following command sends one physical copy of the original design. A fresh journal ID identifies the repeat, while the text in the PNG stays `WL-G9-0035`. [Original PNG](WL-G9-0035.png) · [Complete Bluetooth trace](01-WL-G9-0035.log)

```zsh
swift run printer-bench image --model rongta --device "$printer_id" --endpoint 18F0/2AF1 --mode acknowledged --width-mm 101.6 --height-mm 50.8 --dpi 203 --seconds 15 --file BenchRuns/2026-11-23-rongta-0036Z/WL-G9-0035.png
```

The PNG’s SHA-256 is `745c07b66c9b5242ed4618e26e6f43b5da26e0d59795b6a92d33f0b79c97a2c0`. The ZPL generated from that file before submission has SHA-256 `e12704dd478897f42b457be22b3cf5da7108de515dfde2773e767ecac7bc6089`. The trace records the connection, endpoint, byte count and write acknowledgements.
