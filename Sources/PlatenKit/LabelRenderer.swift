import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation

/// Choose how grayscale artwork is converted to printable black and white dots.
public enum LabelImageMode: String, Sendable {
    case lineArt = "line-art"
    case photo
}

public enum LabelRenderer {
    private static func canvas(width: Int, height: Int) throws -> CGContext {
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            throw BenchError("Could not allocate the label canvas.")
        }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    private static func fit(_ image: CGImage, in box: CGRect) -> CGRect {
        let scale = min(box.width / CGFloat(image.width), box.height / CGFloat(image.height))
        let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
        return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }

    /// Composite onto white and aspect-fit a caller's pre-rendered page to the measured stock.
    public static func bitmap(from image: CGImage, stock: LabelStock) throws -> LabelBitmap {
        try bitmap(from: image, stock: stock, mode: .lineArt)
    }

    /// Photo mode resamples at the final print size and represents gray with Floyd–Steinberg error diffusion.
    public static func bitmap(from image: CGImage, stock: LabelStock, mode: LabelImageMode) throws -> LabelBitmap {
        try bitmap(from: image, width: stock.widthDots, height: stock.heightDots, mode: mode)
    }

    private static func bitmap(from image: CGImage, width: Int, height: Int, mode: LabelImageMode) throws -> LabelBitmap {
        let context = try canvas(width: width, height: height)
        let page = CGRect(x: 0, y: 0, width: width, height: height)
        context.interpolationQuality = mode == .photo ? .high : .none
        context.draw(image, in: fit(image, in: page))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            throw BenchError("Could not read the label pixels.")
        }
        var pixels = Array(UnsafeBufferPointer(start: bytes, count: width * height))
        if mode == .photo { ditherPhoto(&pixels, width: width, height: height) }
        return try LabelBitmap(width: width, height: height, grayscale: pixels)
    }

    private static func ditherPhoto(_ pixels: inout [UInt8], width: Int, height: Int) {
        // The guard columns discard errors that would otherwise wrap around the page.
        var current = [Int](repeating: 0, count: width + 2)
        var next = current
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let gray = min(255, max(0, Int(pixels[index]) + current[x + 1] / 16))
                let result = gray > 128 ? 255 : 0
                pixels[index] = UInt8(result)
                let error = gray - result
                current[x + 2] += 7 * error
                next[x] += 3 * error
                next[x + 1] += 5 * error
                next[x + 2] += error
            }
            swap(&current, &next)
            for index in next.indices { next[index] = 0 }
        }
    }

    static func textPage(_ text: String, stock: LabelStock, font: LabelFont? = nil) throws -> CGImage {
        let context = try canvas(width: stock.widthDots, height: stock.heightDots)
        _ = try drawTitle(text, on: context, font: font, dpi: stock.dpi)
        guard let image = context.makeImage() else { throw BenchError("Could not finish the text label.") }
        return image
    }

    private static func drawTitle(_ text: String, on context: CGContext, font: LabelFont?, dpi: Int) throws -> (margin: CGFloat, reservedHeight: CGFloat) {
        let w = CGFloat(context.width), h = CGFloat(context.height)
        let margin = max(4, (min(w, h) * 0.045).rounded())
        let ink = CGColor(gray: 0, alpha: 1)
        let fontSize = min(64, h * 0.13)
        func typeface(_ size: CGFloat) -> CTFont {
            font?.sized(size) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        }
        func line(using face: CTFont) -> CTLine {
            let attributes = [
                NSAttributedString.Key(kCTFontAttributeName as String): face,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink
            ] as [NSAttributedString.Key: Any]
            return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        }
        let naturalWidth = CTLineGetTypographicBounds(line(using: typeface(fontSize)), nil, nil, nil)
        let autoSize = min(fontSize, fontSize * (w - 2 * margin) / max(1, naturalWidth))
        let size = font?.pointSize.map { CGFloat($0) * CGFloat(dpi) / 72 } ?? autoSize
        let fitError = BenchError("The requested font size does not fit this label. Use a smaller size or shorter text.")
        guard size.isFinite, size >= 1, size <= h - 2 * margin else { throw fitError }
        if font?.pointSize == nil && autoSize < 8 { throw BenchError("Text is too long for the loaded stock.") }
        let face = typeface(size)
        let fittedLine = line(using: face)
        try font?.checkGlyphs(in: fittedLine, using: face)
        var origin = CGPoint(x: margin, y: h - margin - size)
        var reservedHeight = autoSize
        if font?.pointSize != nil {
            let ink = CTLineGetBoundsWithOptions(fittedLine, [.useGlyphPathBounds])
            if !ink.isNull {
                origin.x += max(0, -ink.minX)
                origin.y -= max(0, ink.maxY - size)
                guard origin.x + ink.maxX <= w - margin, origin.y + ink.minY >= margin else { throw fitError }
                // Use the spare space above the artwork before moving the artwork or reducing the QR.
                reservedHeight = max(autoSize, h - (origin.y + ink.minY) - 2 * margin)
            }
        }
        context.textPosition = origin
        CTLineDraw(fittedLine, context)
        return (margin, reservedHeight)
    }

    /// Compose one page for either printer. The built-in asymmetric mark makes orientation visible.
    public static func compose(artwork: CGImage? = nil, text: String, qrPayload: String, stock: LabelStock) throws -> CGImage {
        try compose(artwork: artwork, text: text, qrPayload: qrPayload, stock: stock, font: nil)
    }

    public static func compose(artwork: CGImage? = nil, text: String, qrPayload: String, stock: LabelStock, font: LabelFont?) throws -> CGImage {
        try compose(artwork: artwork, text: text, qrPayload: qrPayload, stock: stock, font: font, artworkMode: .lineArt)
    }

    /// Apply the image treatment only inside the supplied artwork.
    public static func compose(artwork: CGImage?, text: String, qrPayload: String, stock: LabelStock, font: LabelFont? = nil, artworkMode: LabelImageMode) throws -> CGImage {
        guard !text.isEmpty, !qrPayload.isEmpty else { throw BenchError("Supply text and a QR payload.") }
        let context = try canvas(width: stock.widthDots, height: stock.heightDots)
        let w = CGFloat(stock.widthDots), h = CGFloat(stock.heightDots)
        let (margin, reservedHeight) = try drawTitle(text, on: context, font: font, dpi: stock.dpi)
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(qrPayload.utf8)
        generator.correctionLevel = "M"
        guard let qr = generator.outputImage,
              let qrImage = qr.cgImage ?? CIContext(options: [.useSoftwareRenderer: true]).createCGImage(qr, from: qr.extent) else {
            throw BenchError("Could not encode this QR payload.")
        }
        let bodyHeight = h - 3 * margin - reservedHeight
        let side = min((w - 3 * margin) * 0.62, bodyHeight)
        let scale = floor(side / CGFloat(qrImage.width + 8))
        guard scale >= 1 else { throw BenchError("The loaded stock is too small for this QR code.") }
        let quiet = scale * 4, size = CGFloat(qrImage.width) * scale
        let qrBox = CGRect(x: (margin + quiet).rounded(), y: (margin + (bodyHeight - size) / 2).rounded(),
                           width: size, height: size)
        context.interpolationQuality = .none
        context.draw(qrImage, in: qrBox)

        let left = qrBox.maxX + quiet + margin
        let art = CGRect(x: left, y: margin, width: w - margin - left, height: bodyHeight)
        if let artwork {
            let target = fit(artwork, in: art)
            if artworkMode == .photo {
                let box = target.integral
                let dots = try bitmap(from: artwork, width: Int(box.width), height: Int(box.height), mode: .photo)
                context.draw(try dots.makeImage(), in: box)
            } else {
                context.draw(artwork, in: target)
            }
        } else {
            let ink = CGColor(gray: 0, alpha: 1)
            let s = min(art.width, art.height) * 0.72
            let square = CGRect(x: art.midX - s / 2, y: art.midY - s / 2, width: s, height: s)
            context.setStrokeColor(ink)
            context.setLineWidth(max(2, s * 0.05))
            context.stroke(square)
            context.setFillColor(ink)
            context.fill(CGRect(x: square.minX, y: square.maxY - s * 0.28, width: s * 0.45, height: s * 0.28))
        }
        guard let image = context.makeImage() else { throw BenchError("Could not finish the label image.") }
        return image
    }
}
