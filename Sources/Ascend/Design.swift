import SwiftUI
import AppKit
import CoreText
import AscendCore

extension Color {
    /// 0xRRGGBB
    init(hex: UInt32, opacity: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}
/// Black Tie: a private room in Monte Carlo after dark. Green felt, lamplight, champagne gold, ivory type.
enum Ink {
    static let night = Color(hex: 0x04110D)
    static let background = Color(hex: 0x0B2A21)   // felt
    static let panel = Color(hex: 0x123A2D)
    static let panel2 = Color(hex: 0x174536)
    static let line = Color(hex: 0xF1E8D4, opacity: 0.10)
    static let muted = Color(hex: 0x8FAE9F)
    static let accent = Color(hex: 0xD9B46E)       // champagne gold
    static let lamp = Color(hex: 0xF0D49A)
    static let goldDim = Color(hex: 0x9C8152)
    static let ivory = Color(hex: 0xF1E8D4)
    static let onTrack = Color(hex: 0x86D19F)
    static let watch = Color(hex: 0xE6B04E)
    static let offTrack = Color(hex: 0xE0626C)
}
/// Inter Tight for text, JetBrains Mono for labels and data, Cormorant Garamond for titles and big numbers.
enum Typeface {
    static let sans = "Inter Tight", mono = "JetBrains Mono", serif = "Cormorant Garamond"
    static func register() {
        let folder = Bundle.main.bundleURL.pathExtension == "app"
            ? Bundle.main.resourceURL?.appendingPathComponent("Ascend_Ascend.bundle/Fonts")
            : Bundle.module.resourceURL?.appendingPathComponent("Fonts")
        for name in ["InterTight", "JetBrainsMono", "CormorantGaramond"] {
            guard let url = folder?.appendingPathComponent(name + ".ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
extension Font {
    /// The app's one font call. Mono stays mono; 18 pt and up becomes the serif display face; the rest is Inter Tight.
    static func bt(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        switch design {
        case .monospaced: return .custom(Typeface.mono, fixedSize: size * 0.94).weight(weight)
        case .serif: return serif(size * 1.2, weight)
        default:
            if size >= 18 { return serif(size * 1.2, weight) }
            return .custom(Typeface.sans, fixedSize: size).weight(weight)
        }
    }
    /// Cormorant with lining figures (its default old-style 0 reads like the letter o).
    private static func serif(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        let w: NSFont.Weight = weight == .bold || weight == .heavy || weight == .black ? .bold : weight == .light || weight == .thin || weight == .ultraLight ? .medium : .semibold
        let d = NSFontDescriptor(fontAttributes: [
            .family: Typeface.serif,
            .traits: [NSFontDescriptor.TraitKey.weight: w],
            .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberCaseType, NSFontDescriptor.FeatureKey.selectorIdentifier: kUpperCaseNumbersSelector]]
        ])
        return Font(NSFont(descriptor: d, size: size) ?? .systemFont(ofSize: size, weight: w))
    }
}
struct Kicker: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text.uppercased()).font(.bt(size: 10, weight: .medium, design: .monospaced)).tracking(1.3).foregroundStyle(Ink.muted) }
}
struct PrimaryButton: View {
    var label: String
    @Environment(\.isEnabled) private var enabled
    var fullWidth = false
    var action: () -> Void
    var body: some View {
        Button(action: action) { Text(label).font(.bt(size: 12, weight: .semibold)).padding(.horizontal, 17).padding(.vertical, 10).frame(minHeight: 32).frame(maxWidth: fullWidth ? .infinity : nil) }
            .buttonStyle(.plain).background(Ink.accent, in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(Ink.background).opacity(enabled ? 1 : 0.4)
    }
}
struct Line: View { var body: some View { Rectangle().fill(Ink.line).frame(height: 1) } }
struct ProgressTrack: View {
    var ratio: Double
    var target: Double = 0.75
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.09))
                Capsule().fill(Ink.accent).frame(width: max(0, g.size.width * min(1, max(0, ratio))))
                Rectangle().fill(Ink.muted).frame(width: 1, height: 10).offset(x: g.size.width * target)
            }
        }.frame(height: 4).accessibilityElement().accessibilityLabel("Progress").accessibilityValue("\(Int((ratio * 100).rounded())) percent; target \(Int(target * 100)) percent")
    }
}
extension View {
    func panel(padding: CGFloat = 20) -> some View {
        self.padding(padding).background(Ink.panel, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Ink.line, lineWidth: 1))
    }
}
func dateText(_ key: String, engine: TrackerEngine, pattern: String = "d MMM yyyy") -> String {
    guard let date = engine.date(key) else { return key }
    let f = DateFormatter(); f.calendar = engine.calendar; f.timeZone = engine.calendar.timeZone; f.dateFormat = pattern
    return f.string(from: date)
}
