import SwiftUI

/// MIT-licensed polygon artwork from giavinh79/react-body-highlighter. See bundled BodyMap/LICENSE.txt.
/// Reference anatomy only: colors never represent measured regional fat or muscle distribution.
private struct BodyMapRegion: Decodable {
    let name: String
    let polygons: [[Double]]
}
private enum BodyMapArtwork {
    static let front = load("anterior"), back = load("posterior")
    static func load(_ name: String) -> [BodyMapRegion] {
        let folder = Bundle.main.bundleURL.pathExtension == "app"
            ? Bundle.main.resourceURL?.appendingPathComponent("Ascend_Ascend.bundle/BodyMap")
            : Bundle.module.resourceURL?.appendingPathComponent("BodyMap")
        guard let url = folder?.appendingPathComponent(name + ".json"), let data = try? Data(contentsOf: url),
              let regions = try? JSONDecoder().decode([BodyMapRegion].self, from: data) else { return [] }
        return regions
    }
}
struct BodyMapView: View {
    @State private var back = false
    var body: some View {
        VStack(spacing: 12) {
            Picker("Reference body view", selection: $back) {
                Text("Front").tag(false)
                Text("Back").tag(true)
            }.labelsHidden().pickerStyle(.segmented).frame(width: 140)
            ZStack {
                Ellipse().fill(Ink.accent.opacity(0.13)).blur(radius: 28).frame(width: 140, height: 230)
                ForEach(0..<3) { i in
                    Ellipse().stroke(Ink.accent.opacity(0.07), lineWidth: 1)
                        .frame(width: CGFloat(125 + i * 30), height: CGFloat(220 + i * 35))
                }
                Canvas { context, size in
                    let regions = back ? BodyMapArtwork.back : BodyMapArtwork.front
                    let scale = min(size.width / 1000, size.height / 2000)
                    let x = (size.width - 1000 * scale) / 2, y = (size.height - 2000 * scale) / 2
                    for region in regions {
                        let peripheral = ["HEAD", "NECK", "KNEES", "LEFT_SOLEUS", "RIGHT_SOLEUS"].contains(region.name)
                        for polygon in region.polygons where polygon.count >= 6 && polygon.count.isMultiple(of: 2) {
                            var path = Path()
                            for index in stride(from: 0, to: polygon.count, by: 2) {
                                let p = CGPoint(x: x + polygon[index] * scale, y: y + polygon[index + 1] * scale)
                                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                            }
                            path.closeSubpath()
                            context.fill(path, with: .linearGradient(Gradient(colors: [Ink.accent.opacity(peripheral ? 0.23 : 0.65), Ink.accent.opacity(peripheral ? 0.14 : 0.28)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                            context.stroke(path, with: .color(Ink.accent.opacity(0.32)), lineWidth: 0.6)
                        }
                    }
                    if regions.isEmpty {
                        context.draw(Text(Image(systemName: "figure.stand")).font(.system(size: 120)).foregroundColor(Ink.accent), at: CGPoint(x: size.width / 2, y: size.height / 2))
                    }
                }.frame(width: 170, height: 300)
            }.frame(maxWidth: .infinity).frame(height: 302)
            Text("REFERENCE ANATOMY").font(.system(size: 8.5, design: .monospaced)).tracking(1.2).foregroundStyle(Ink.muted)
            Text("Illustration, not a body scan").font(.system(size: 10)).foregroundStyle(Ink.muted.opacity(0.8))
        }
        .frame(width: 220).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Ink.accent.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Ink.accent.opacity(0.10)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reference anatomy. No regional measurements are shown.")
    }
}
