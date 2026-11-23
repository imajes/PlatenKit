import CoreText
import Foundation

/// A typeface for text drawn into a label. Core Text fonts are immutable and safe to share between operations.
public struct LabelFont: @unchecked Sendable {
    public let postScriptName: String
    public let weight: Int?
    private let face: CTFont

    /// Select an available face by PostScript name. "Karla" and "Karla-Regular" use the package's upright variable font.
    public init(postScriptName name: String, weight: Int? = nil) throws {
        if name == "Karla" || name == "Karla-Regular" {
            guard let url = Bundle.module.url(forResource: "Karla-Variable", withExtension: "ttf") else {
                throw BenchError("The Karla resource is missing from the WhiplashPrinting bundle.")
            }
            try self.init(data: Data(contentsOf: url), weight: weight)
            return
        }
        let base = CTFontCreateWithNameAndOptions(name as CFString, 12, nil, [.preventAutoActivation, .preventAutoDownload])
        guard !name.isEmpty, CTFontCopyPostScriptName(base) as String == name else {
            throw BenchError("Font ‘\(name)’ is unavailable. Use its exact PostScript name or supply a font file.")
        }
        try self.init(base: base, weight: weight)
    }

    /// Use a standalone TrueType or OpenType font directly from its bytes. Its default face is used unless a weight is specified.
    public init(data: Data, weight: Int? = nil) throws {
        guard !data.starts(with: "ttcf".utf8), let descriptor = CTFontManagerCreateFontDescriptorFromData(data as CFData) else {
            throw BenchError("Supply a standalone .ttf or .otf font file.")
        }
        try self.init(base: CTFontCreateWithFontDescriptor(descriptor, 12, nil), weight: weight)
    }

    private init(base: CTFont, weight: Int?) throws {
        postScriptName = CTFontCopyPostScriptName(base) as String
        self.weight = weight
        guard let weight else { face = base; return }
        let weightTag = NSNumber(value: 0x77676874) // OpenType 'wght'
        let axes = CTFontCopyVariationAxes(base) as? [[String: Any]] ?? []
        guard let axis = axes.first(where: { ($0[kCTFontVariationAxisIdentifierKey as String] as? NSNumber) == weightTag }),
              let minimum = axis[kCTFontVariationAxisMinimumValueKey as String] as? NSNumber,
              let maximum = axis[kCTFontVariationAxisMaximumValueKey as String] as? NSNumber,
              let defaultValue = axis[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber else {
            throw BenchError("Font ‘\(postScriptName)’ has a fixed weight. Choose its named face or supply a variable font.")
        }
        guard minimum.doubleValue <= Double(weight), Double(weight) <= maximum.doubleValue else {
            throw BenchError("Weight \(weight) is outside the \(minimum)–\(maximum) range of ‘\(postScriptName)’.")
        }
        let descriptor = CTFontDescriptorCreateCopyWithVariation(CTFontCopyFontDescriptor(base), weightTag, CGFloat(weight))
        face = CTFontCreateCopyWithAttributes(base, 12, nil, descriptor)
        let applied = (CTFontCopyVariation(face) as NSDictionary?)?[weightTag] as? NSNumber ?? defaultValue
        guard applied.doubleValue == Double(weight) else { throw BenchError("Core Text could not apply weight \(weight) to ‘\(postScriptName)’.") }
    }

    public var description: String { weight.map { "\(postScriptName) · weight \($0)" } ?? postScriptName }

    func sized(_ size: CGFloat) -> CTFont { CTFontCreateCopyWithAttributes(face, size, nil, nil) }

    /// Core Text may substitute a different font while shaping an individual run.
    func checkGlyphs(in line: CTLine, using sizedFont: CTFont) throws {
        let expected = CTFontCopyPostScriptName(sizedFont) as String
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let actual = attributes[kCTFontAttributeName] as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            guard CTFontCopyPostScriptName(actual) as String == expected, !glyphs.contains(0) else {
                throw BenchError("Font ‘\(postScriptName)’ cannot draw every character in this label.")
            }
        }
    }
}
