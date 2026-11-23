# Rongta text-only comparison after a successful RT Elabel print

James confirmed that the **RT Elabel** iPhone app produced a physical label on the Rongta. Earlier unsuccessful attempts involved other Rongta apps. He selected ZPL in RT Elabel when prompted. He also reported intermittent roll-feed trouble and later confirmed that the 4 × 2 inch roll was ready for the Mac. The cause of the earlier blank labels is still open.

## Vendor app

Rongta lists the RP421A for its iOS edition of RT Elabel and identifies it as the Bluetooth phone app on the printer’s product page. The exact App Store listing is **RT Elabel** by **Xiamen Rongta Technology Co., Ltd.**, app ID **6714471637**. It offers Bluetooth device binding, custom-size labels, image and PDF printing. Its version history records a change to the RP421 app default to TSPL and support for remembering a user-selected command language. The printer’s self-test reports ZPL at 203 dpi. The installed app version, exact GATT characteristic and bytes from the successful iPhone job are unknown. [Rongta’s supported-model list](https://www.rongtatech.com/label-design-software/) · [RP421A product page](https://rongtaglobal.com/products/rongta-rp421a-thermal-shipping-label-printer-black) · [RT Elabel and version history](https://apps.apple.com/us/app/rt-elabel/id6714471637)

## Mac comparison

Both jobs ran from macOS 27.3 (26C5047e) over Core Bluetooth with the correct power supply, 101.6 × 50.8 mm stock and a 203-dpi layout. The unit identifies as RP421 on its self-test, firmware V4.31 dated 2024-01-30. For each job the probe scanned, found `RP421-A8C5`, connected to the same peripheral and subscribed to `18F0/2AF0`. It sent only the run ID as label content, near the leading corner at (8, 8) dots. Each format requested one copy and used the current media settings. [Stock and self-test record](../2026-11-22-rongta-2349Z/README.md#built-in-self-test-on-both-rolls)

| Language and run ID | Discovery and write | Paper observation |
| --- | --- | --- |
| ZPL · `WL-Z5-0025` | −58 dBm. One 42-byte write acknowledged on `18F0/2AF1` at 18:25:46 CST, November 22. [Trace](01-WL-Z5-0025.log) | James reported blank, advanced stock in response to the ZPL check. |
| TSPL · `WL-T6-0027` | −53 dBm. One 49-byte write acknowledged on `18F0/2AF1` at 18:27:41 CST, November 22. [Trace](02-WL-T6-0027.log) | Unobserved individually. |

The advertised services were `FEE7` and `18F0`. The negotiated acknowledged-write limit was 512 bytes on both connections. Each trace contains the complete label payload in a single write. The probe listened for unsolicited replies for approximately two seconds after each acknowledgement. No notification payload arrived. Each connection ended before the next job.

James recalled one feed across the pair and said he had been away. Neither printed ID was confirmed. He requested a repeat so each paper result could be observed before the following job.

## Repeat observed one job at a time

The Mac used the same stock, endpoint, font commands and media settings. The captured repeat payload in each language differed from its first run only in the ID. James reported the ZPL result before the Mac started the TSPL repeat.

| Language and run ID | Discovery and write | Paper observation |
| --- | --- | --- |
| ZPL · `WL-Z7-0033` | −54 dBm. All 42 bytes acknowledged in one write at 18:33:40 CST. [Trace](03-WL-Z7-0033.log) | Exactly one label advanced, completely blank. |
| TSPL · `WL-T8-0034` | −60 dBm. All 49 bytes acknowledged in one write at 18:34:23 CST. [Trace](04-WL-T8-0034.log) | No paper moved. |

These results support continuing with ZPL on this unit in its present configuration. The next experiment uses the same Bluetooth endpoint and represents the text as a graphic field.
