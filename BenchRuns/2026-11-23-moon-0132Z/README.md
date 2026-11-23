# Moon photograph on the Labelife and Rongta

On November 22, 2026, James confirmed that each Mac Bluetooth request produced exactly one Moon label. He preferred the dithered image on both. In the paper photograph, the tall label on the left is the Labelife and the short label on the upper right is the Rongta. Each shows thresholding on the left and dithering on the right. The earlier Rongta bitmap ID `WL-G9-0035` is legible on the label below. [Photograph of the paper](paper.jpg)

| Stage | Labelife AM-243-BT (hardware PM-241-BT) | Rongta RP421A (firmware V4.31) |
| --- | --- | --- |
| Host and stock | Swift Mac bench on macOS 27.3 (26C5047e), Core Bluetooth, 203 dpi, 4″ across × 6″ feed | Same host and DPI, 4″ across × 2″ feed |
| Discovery | Fresh scan found `AM-243Z-BT-5AD6` at −60 dBm, advertising `1812` and `AF30` | Fresh scan found `RP421-A8C5` at −63 dBm, advertising `FEE7` and `18F0` |
| Connection | Connected, inspected services, subscribed to notifications on `FF00/FF03` | Connected and inspected services |
| Submission | `WL-LIMG-013140`, TSPL mode-4 bitmap through `FF00/FF02`. Initial grant of 7 write credits and a 244-byte packet limit. | `WL-RIMG-013140`, ZPL graphic through `18F0/2AF1` with a 512-byte write limit. |
| Write result | 21,983 bytes in 92 acknowledged writes by 7:32:17 p.m. CST. The printer reported `SSSGETPRINTING:DOING`. [Bluetooth trace](WL-LIMG-013140.log) | 82,882 bytes in 162 acknowledged writes by 7:33:51 p.m. CST. [Bluetooth trace](WL-RIMG-013140.log) |
| Paper | One label with the matching ID. Both images printed and the dithered Moon showed more surface detail. [Source page](WL-LIMG-013140.png) | One label with the matching ID. Both images printed and the dithered Moon showed more surface detail. [Source page](WL-RIMG-013140.png) |

## Compare the dots

Each printer received a precomposed 812 × 406 pixel page through the Swift bench’s `image` command. The Rongta used the full page. On the Labelife the adapter centered the design on an 812 × 1,218 dot page, preserving the image scale. Both pictures on each label are 284 × 284 dots, about 35.5 mm square at 203 dpi. [Labelife source page](WL-LIMG-013140.png) · [Rongta source page](WL-RIMG-013140.png)

The source was NASA’s Lunar Reconnaissance Orbiter mosaic, converted to grayscale and resized using Lanczos sampling. The left sample used a fixed threshold of 128. The right used Pillow’s Floyd–Steinberg error diffusion. On both source pages, the top-left pixel of the right square is at (467, 58), measured from the upper-left corner. Packing that crop from top to bottom, most significant bit first, with a set bit for ink and zero padding to 36 bytes per row, gives SHA-256 `ff6965e9970d9034c400cbe3b305e100371dbe18dca7aaefd4dedaab37d663d1`. [NASA Moon Mosaic](https://science.nasa.gov/resource/moon-mosaic/)
