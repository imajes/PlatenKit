import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation

public enum LabelRenderer {
    private static func canvas(_ stock: LabelStock) throws -> CGContext {
        guard let context = CGContext(data: nil, width: stock.widthDots, height: stock.heightDots,
                                      bitsPerComponent: 8, bytesPerRow: stock.widthDots,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            throw BenchError("Could not allocate the label canvas.")
        }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: stock.widthDots, height: stock.heightDots))
        return context
    }

    private static func fit(_ image: CGImage, in box: CGRect) -> CGRect {
        let scale = min(box.width / CGFloat(image.width), box.height / CGFloat(image.height))
        let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
        return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }

    /// Composite onto white and aspect-fit a caller's pre-rendered page to the measured stock.
    public static func bitmap(from image: CGImage, stock: LabelStock) throws -> LabelBitmap {
        let context = try canvas(stock)
        let page = CGRect(x: 0, y: 0, width: stock.widthDots, height: stock.heightDots)
        context.interpolationQuality = .none
        context.draw(image, in: fit(image, in: page))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            throw BenchError("Could not read the label pixels.")
        }
        let pixels = Array(UnsafeBufferPointer(start: bytes, count: stock.widthDots * stock.heightDots))
        return try LabelBitmap(width: stock.widthDots, height: stock.heightDots, grayscale: pixels)
    }

    static func textPage(_ text: String, stock: LabelStock) throws -> CGImage {
        let context = try canvas(stock)
        _ = try drawTitle(text, on: context)
        guard let image = context.makeImage() else { throw BenchError("Could not finish the text label.") }
        return image
    }

    private static func drawTitle(_ text: String, on context: CGContext) throws -> (margin: CGFloat, font: CGFloat) {
        let w = CGFloat(context.width), h = CGFloat(context.height)
        let margin = max(4, (min(w, h) * 0.045).rounded())
        let ink = CGColor(gray: 0, alpha: 1)
        let fontSize = min(64, h * 0.13)
        func line(size: CGFloat) -> CTLine {
            let attributes = [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink
            ] as [NSAttributedString.Key: Any]
            return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        }
        let naturalWidth = CTLineGetTypographicBounds(line(size: fontSize), nil, nil, nil)
        let fittedFont = min(fontSize, fontSize * (w - 2 * margin) / max(1, naturalWidth))
        guard fittedFont >= 8 else { throw BenchError("Text is too long for the loaded stock.") }
        context.textPosition = CGPoint(x: margin, y: h - margin - fittedFont)
        CTLineDraw(line(size: fittedFont), context)
        return (margin, fittedFont)
    }

    /// Compose one page for either printer. The built-in asymmetric mark makes orientation visible.
    public static func compose(artwork: CGImage? = nil, text: String, qrPayload: String, stock: LabelStock) throws -> CGImage {
        guard !text.isEmpty, !qrPayload.isEmpty else { throw BenchError("Supply text and a QR payload.") }
        let context = try canvas(stock)
        let w = CGFloat(stock.widthDots), h = CGFloat(stock.heightDots)
        let (margin, fittedFont) = try drawTitle(text, on: context)
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(qrPayload.utf8)
        generator.correctionLevel = "M"
        guard let qr = generator.outputImage,
              let qrImage = qr.cgImage ?? CIContext(options: [.useSoftwareRenderer: true]).createCGImage(qr, from: qr.extent) else {
            throw BenchError("Could not encode this QR payload.")
        }
        let bodyHeight = h - 3 * margin - fittedFont
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
            context.draw(artwork, in: fit(artwork, in: art))
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
