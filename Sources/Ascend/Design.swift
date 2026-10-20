import SwiftUI
import AscendCore

enum Ink {
    static let background = Color(red: 0.051, green: 0.047, blue: 0.063)
    static let panel = Color(red: 0.082, green: 0.075, blue: 0.098)
    static let line = Color.white.opacity(0.10)
    static let muted = Color(red: 0.62, green: 0.59, blue: 0.66)
    static let accent = Color(red: 0.63, green: 0.54, blue: 1)
}
struct Kicker: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text.uppercased()).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.3).foregroundStyle(Ink.muted) }
}
struct PrimaryButton: View {
    var label: String
    @Environment(\.isEnabled) private var enabled
    var fullWidth = false
    var action: () -> Void
    var body: some View {
        Button(action: action) { Text(label).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 17).padding(.vertical, 10).frame(minHeight: 32).frame(maxWidth: fullWidth ? .infinity : nil) }
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
