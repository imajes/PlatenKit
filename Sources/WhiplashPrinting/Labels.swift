import CoreGraphics
import Foundation

public struct BenchError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum PrinterLanguage: String, Sendable {
    case zpl = "ZPL"
    case tspl = "TSPL"
}

public enum PrinterModel: String, CaseIterable, Identifiable, Sendable {
    case rongta, labelife
    public var id: Self { self }
    public var name: String { self == .rongta ? "Rongta RP421A" : "Labelife AM-243-BT (PM-241-BT)" }
    public var defaultLanguage: PrinterLanguage { self == .rongta ? .zpl : .tspl }
    public var language: String { defaultLanguage.rawValue }
}

public struct LabelStock: Sendable {
    /// Width is across the print head. Height follows the direction of feed.
    public let widthMM: Double
    public let heightMM: Double
    public let dpi: Int
    public let widthDots: Int
    public let heightDots: Int

    public init(widthMM: Double, heightMM: Double, dpi: Int = 203) throws {
        guard widthMM.isFinite, heightMM.isFinite, (1...120).contains(widthMM),
              (1...1000).contains(heightMM), (100...600).contains(dpi) else {
            throw BenchError("Enter stock width (1–120 mm across the head), feed length (1–1000 mm), and resolution (100–600 dpi).")
        }
        let w = Int((widthMM * Double(dpi) / 25.4).rounded())
        let h = Int((heightMM * Double(dpi) / 25.4).rounded())
        guard w * h <= 16_000_000 else { throw BenchError("The requested page exceeds 16 million dots.") }
        (self.widthMM, self.heightMM, self.dpi, widthDots, heightDots) = (widthMM, heightMM, dpi, w, h)
    }

    public var description: String { "\(widthMM) × \(heightMM) mm, \(widthDots) × \(heightDots) dots at \(dpi) dpi" }
}

/// Rows run top to bottom, MSB first, with one indicating a dark dot.
public struct LabelBitmap: Sendable {
    public let width: Int
    public let height: Int
    public let bytes: Data
    public var bytesPerRow: Int { (width + 7) / 8 }

    public init(width: Int, height: Int, grayscale: [UInt8], threshold: UInt8 = 128) throws {
        guard width > 0, height > 0, width <= 16_000_000 / height, grayscale.count == width * height else {
            throw BenchError("Invalid grayscale raster dimensions.")
        }
        let stride = (width + 7) / 8
        var packed = Data(repeating: 0, count: stride * height)
        for y in 0..<height {
            for x in 0..<width where grayscale[y * width + x] < threshold {
                packed[y * stride + x / 8] |= 0x80 >> (x % 8)
            }
        }
        (self.width, self.height, bytes) = (width, height, packed)
    }
}

public struct LabelJob: Sendable {
    public let id: String
    public let model: PrinterModel
    public let stock: LabelStock
    public let bytes: Data
    public let language: PrinterLanguage

    public static func newID() -> String {
        "WL-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).uppercased()
    }

    private static func validate(_ id: String) throws {
        let allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8
        guard (1...32).contains(id.utf8.count), id.utf8.allSatisfy(allowed.contains) else {
            throw BenchError("Use 1–32 ASCII letters, digits, underscores, or hyphens for the run ID.")
        }
    }

    /// Render the ID as pixels on the measured stock and encode one copy for the selected printer.
    public static func smoke(id: String = newID(), model: PrinterModel, stock: LabelStock) throws -> Self {
        try validate(id)
        let page = try LabelRenderer.textPage(id, stock: stock)
        return try image(page, id: id, model: model, stock: stock)
    }

    /// Compare the Rongta's built-in text commands using its current media settings. The Labelife uses TSPL raster.
    public static func smoke(id: String = newID(), model: PrinterModel, stock: LabelStock, language: PrinterLanguage) throws -> Self {
        try validate(id)
        switch (model, language) {
        case (.rongta, .zpl):
            let font = min(36, (stock.widthDots - 16) / id.utf8.count, stock.heightDots - 16)
            guard font >= 10 else { throw BenchError("Stock is too small for this test ID.") }
            let text = "^XA^FO8,8^A0N,\(font),\(font)^FD\(id)^FS^PQ1^XZ"
            return Self(id: id, model: model, stock: stock, bytes: Data(text.utf8), language: language)
        case (.rongta, .tspl):
            // TSPL font 1 occupies 8 × 12 dots before magnification.
            let scale = min(3, (stock.widthDots - 16) / (8 * id.utf8.count), (stock.heightDots - 16) / 12)
            guard scale >= 1 else { throw BenchError("Stock is too small for this test ID.") }
            let text = "CLS\r\nTEXT 8,8,\"1\",0,\(scale),\(scale),\"\(id)\"\r\nPRINT 1,1\r\n"
            return Self(id: id, model: model, stock: stock, bytes: Data(text.utf8), language: language)
        case (.labelife, .tspl):
            return try smoke(id: id, model: model, stock: stock)
        case (.labelife, .zpl):
            throw BenchError("The Labelife adapter supports TSPL.")
        }
    }

    public static func image(_ image: CGImage, id: String = newID(), model: PrinterModel, stock: LabelStock) throws -> Self {
        try raster(LabelRenderer.bitmap(from: image, stock: stock), id: id, model: model, stock: stock)
    }

    /// A font-independent black square and a separate ID, centered on the measured stock.
    public static func rongtaMark(id: String = newID(), stock: LabelStock) throws -> Self {
        try validate(id)
        let width = stock.widthDots, height = stock.heightDots
        let side = min(64, width / 4, height / 4)
        let font = min(40, (width - 16) / id.utf8.count, height / 5)
        guard side >= 8, font >= 10 else { throw BenchError("Stock is too small for the Rongta diagnostic mark.") }
        let gap = font / 2
        let top = (height - side - gap - font) / 2
        let squareX = (width - side) / 2
        let textX = (width - font * id.utf8.count) / 2
        let format = ["^XA", "^FO\(squareX),\(top)", "^GB\(side),\(side),\(side),B,0^FS",
                      "^FO\(textX),\(top + side + gap)", "^A0N,\(font),\(font)^FD\(id)^FS", "^PQ1", "^XZ"]
        let bytes = Data((format.joined(separator: "\r\n") + "\r\n").utf8)
        return Self(id: id, model: .rongta, stock: stock, bytes: bytes, language: .zpl)
    }

    public static func raster(_ page: LabelBitmap, id: String = newID(), model: PrinterModel, stock: LabelStock) throws -> Self {
        try validate(id)
        guard page.width == stock.widthDots, page.height == stock.heightDots else {
            throw BenchError("Raster dimensions differ from the requested stock.")
        }
        var data = Data()
        switch model {
        case .rongta:
            data.append(contentsOf: zplHeader(stock).utf8)
            // ZPL limits an individual graphic field to 99,999 uncompressed bytes.
            let rowsPerField = 99_999 / page.bytesPerRow
            let hex = Array("0123456789ABCDEF".utf8)
            for y in stride(from: 0, to: page.height, by: rowsPerField) {
                let start = y * page.bytesPerRow
                let end = min(start + rowsPerField * page.bytesPerRow, page.bytes.count)
                let count = end - start
                data.append(contentsOf: "^FO0,\(y)^GFA,\(count),\(count),\(page.bytesPerRow),".utf8)
                for byte in page.bytes[start..<end] {
                    data.append(hex[Int(byte >> 4)])
                    data.append(hex[Int(byte & 0x0f)])
                }
                data.append(contentsOf: "^FS".utf8)
            }
            data.append(contentsOf: "^PQ1^XZ".utf8)
        case .labelife:
            data.append(contentsOf: tsplHeader(stock).utf8)
            LabelifeRaster.append(page, to: &data)
            data.append(contentsOf: "\r\nPRINT 1,1\r\n".utf8)
        }
        return Self(id: id, model: model, stock: stock, bytes: data, language: model.defaultLanguage)
    }

    private static func zplHeader(_ stock: LabelStock) -> String {
        "^XA^PW\(stock.widthDots)^LL\(stock.heightDots)^LH0,0"
    }

    private static func tsplHeader(_ stock: LabelStock) -> String {
        let locale = Locale(identifier: "en_US_POSIX")
        let size = String(format: "SIZE %.2f mm,%.2f mm", locale: locale, stock.widthMM, stock.heightMM)
        return "\(size)\r\nDIRECTION 0,0\r\nREFERENCE 0,0\r\nCLS\r\n"
    }
}
