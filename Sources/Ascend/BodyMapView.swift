import SwiftUI

/// MIT polygon artwork from giavinh79/react-body-highlighter; bundled attribution is retained.
/// Optional colors show logged hard-set training volume only, never regional fat or composition.
private struct BodyMapRegion: Decodable {
  let name: String
  let polygons: [[Double]]
}
private enum BodyMapArtwork {
  static let front = load("anterior"), back = load("posterior")
  static func load(_ name: String) -> [BodyMapRegion] {
    let folder =
      Bundle.main.bundleURL.pathExtension == "app"
      ? Bundle.main.resourceURL?.appendingPathComponent("Ascend_Ascend.bundle/BodyMap")
      : Bundle.module.resourceURL?.appendingPathComponent("BodyMap")
    guard let url = folder?.appendingPathComponent(name + ".json"),
      let data = try? Data(contentsOf: url),
      let regions = try? JSONDecoder().decode([BodyMapRegion].self, from: data)
    else { return [] }
    return regions
  }
}
struct BodyMapView: View {
  var volumes: [String: Int]? = nil
  var exerciseNames: [String: [String]] = [:]
  @State private var back = false
  @State private var selected = "CHEST"
  private var regions: [BodyMapRegion] { back ? BodyMapArtwork.back : BodyMapArtwork.front }
  private func path(_ points: [Double], size: CGSize) -> Path {
    var p = Path()
    guard points.count >= 6, points.count.isMultiple(of: 2) else { return p }
    let scale = min(size.width / 1000, size.height / 2000)
    let x = (size.width - 1000 * scale) / 2
    let y = (size.height - 2000 * scale) / 2
    for i in stride(from: 0, to: points.count, by: 2) {
      let point = CGPoint(x: x + points[i] * scale, y: y + points[i + 1] * scale)
      if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
    }
    p.closeSubpath()
    return p
  }
  private func color(_ name: String) -> Color {
    guard let volumes else { return Ink.accent.opacity(0.35) }
    let count = volumes[name] ?? 0
    return count == 0
      ? Color.white.opacity(0.08)
      : count < 10 ? Ink.accent.opacity(0.3) : count <= 20 ? Ink.accent : Color.orange
  }
  private func select(_ point: CGPoint) {
    if let r = regions.first(where: {
      $0.polygons.contains { path($0, size: CGSize(width: 170, height: 300)).contains(point) }
    }) {
      selected = r.name
    }
  }
  var body: some View {
    VStack(spacing: 12) {
      Picker("Body view", selection: $back) {
        Text("Front").tag(false)
        Text("Back").tag(true)
      }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
      Canvas { context, size in
        for r in regions {
          for polygon in r.polygons {
            let p = path(polygon, size: size)
            context.fill(p, with: .color(color(r.name)))
            context.stroke(
              p,
              with: .color(
                r.name == selected && volumes != nil
                  ? .white.opacity(0.7) : Ink.accent.opacity(0.25)),
              lineWidth: r.name == selected ? 1.2 : 0.5)
          }
        }
      }.frame(width: 170, height: 300)
        .onTapGesture(coordinateSpace: .local) { select($0) }.onContinuousHover { phase in
          if case .active(let point) = phase { select(point) }
        }
      if let volumes {
        Picker("Muscle region", selection: $selected) {
          ForEach(
            Array(Set((BodyMapArtwork.front + BodyMapArtwork.back).map(\.name))).sorted(),
            id: \.self
          ) { Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) }
        }.frame(width: 200)
        Text("\(volumes[selected] ?? 0) hard sets this week").font(
          .system(size: 12, weight: .medium)
        ).foregroundStyle(Ink.accent)
        Text(
          (exerciseNames[selected] ?? []).joined(separator: ", ").isEmpty
            ? "No logged exercises" : (exerciseNames[selected] ?? []).joined(separator: ", ")
        ).font(.system(size: 10)).foregroundStyle(Ink.muted).multilineTextAlignment(.center)
      }
      Text(volumes == nil ? "REFERENCE ANATOMY" : "LOGGED TRAINING VOLUME").font(
        .system(size: 8.5, design: .monospaced)
      ).tracking(1.2).foregroundStyle(Ink.muted)
      Text("Not a body scan or regional fat map").font(.system(size: 10)).foregroundStyle(Ink.muted)
    }.frame(width: 230).padding(.vertical, 16).background(
      Ink.accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 18)
    ).overlay(RoundedRectangle(cornerRadius: 18).stroke(Ink.accent.opacity(0.1)))
      .accessibilityElement(children: .contain).accessibilityLabel(
        volumes == nil
          ? "Reference anatomy"
          : "Logged hard-set volume. No regional body-composition measurements.")
  }
}
