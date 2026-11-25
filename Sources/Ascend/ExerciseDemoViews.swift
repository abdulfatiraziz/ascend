import SwiftUI
import WebKit

struct ExerciseDemo: Decodable, Identifiable {
  let id: String
  let name: String
}
enum ExerciseDemoLibrary {
  static var folder: URL? {
    Bundle.main.bundleURL.pathExtension == "app"
      ? Bundle.main.resourceURL?.appendingPathComponent("Ascend_Ascend.bundle/ExerciseDemos")
      : Bundle.module.resourceURL?.appendingPathComponent("ExerciseDemos")
  }
  static let entries: [ExerciseDemo] = {
    guard let url = folder?.appendingPathComponent("catalog.json"),
      let bytes = try? Data(contentsOf: url)
    else { return [] }
    return (try? JSONDecoder().decode([ExerciseDemo].self, from: bytes)) ?? []
  }()
  static func image(_ id: String, moving: Bool) -> String? {
    guard entries.contains(where: { $0.id == id }),
      let url = folder?.appendingPathComponent(id + (moving ? ".gif" : ".png")),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return "data:image/\(moving ? "gif":"png");base64," + data.base64EncodedString()
  }
}
/// Local image player; no JavaScript, network, file navigation or web bridge.
private struct ExerciseArtworkPlayer: NSViewRepresentable {
  let source: String
  func makeNSView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.defaultWebpagePreferences.allowsContentJavaScript = false
    let view = WKWebView(frame: .zero, configuration: config)
    view.navigationDelegate = context.coordinator
    view.setValue(false, forKey: "drawsBackground")
    return view
  }
  func makeCoordinator() -> Coordinator { Coordinator() }
  final class Coordinator: NSObject, WKNavigationDelegate {
    var previous = ""
    func webView(
      _ view: WKWebView, decidePolicyFor action: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) { decisionHandler(action.request.url?.absoluteString == "about:blank" ? .allow : .cancel) }
  }
  func updateNSView(_ view: WKWebView, context: Context) {
    guard context.coordinator.previous != source else { return }
    context.coordinator.previous = source
    view.loadHTMLString(
      "<!doctype html><meta name='viewport' content='width=device-width, initial-scale=1'><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline'\"><style>html,body{margin:0;background:transparent;height:100%;overflow:hidden}body{display:grid;place-items:center}img{width:100%;height:100%;object-fit:contain}</style><img alt='Generated workout illustration' src='\(source)'>",
      baseURL: nil)
  }
}
struct ExerciseDemoSheet: View {
  var initialID: String?
  var choose: ((String) -> Void)? = nil
  @State private var selected = ""
  @State private var moving = false
  @State private var search = ""
  @Environment(\.dismiss) var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Workout artwork").font(.title2)
          Text("Generated illustrations · transparent backgrounds").font(.bt(size: 11))
            .foregroundStyle(Ink.muted)
        }
        Spacer()
        Button("Done") { dismiss() }
      }
      TextField("Find a movement", text: $search)
      HStack(alignment: .top, spacing: 20) {
        ScrollView {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(
              ExerciseDemoLibrary.entries.filter {
                search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
              }
            ) { e in
              Button {
                selected = e.id
              } label: {
                Text(e.name).font(.bt(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                  .padding(9).background(
                    selected == e.id ? Ink.accent.opacity(0.15) : .clear,
                    in: RoundedRectangle(cornerRadius: 7))
              }.buttonStyle(.plain)
            }
          }
        }.frame(width: 205)
        VStack(spacing: 14) {
          if let image = ExerciseDemoLibrary.image(selected, moving: moving) {
            ExerciseArtworkPlayer(source: image).frame(height: 350)
            Text(ExerciseDemoLibrary.entries.first { $0.id == selected }?.name ?? "").font(
              .headline)
            Toggle("Subtle GIF motion", isOn: $moving).font(.bt(size: 12))
            if let choose {
              Button("Use this illustration") {
                choose(selected)
                dismiss()
              }
            }
          } else {
            Text("Choose an illustration.").foregroundStyle(Ink.muted)
          }
        }.frame(maxWidth: .infinity)
      }
      Text(
        "Illustrative artwork, not a form demonstration. GIF motion gently moves the illustration; it does not show a repetition."
      ).font(.bt(size: 11)).foregroundStyle(Ink.muted)
      Text(
        "AI-generated for Cipher. No personal photos or measurements used. Motion is off by default and stays off when Reduce Motion is enabled."
      ).font(.bt(size: 10)).foregroundStyle(Ink.muted)
    }.padding(24).frame(width: 800, height: 620).onAppear {
      moving = false
      selected =
        initialID.flatMap { id in ExerciseDemoLibrary.entries.contains { $0.id == id } ? id : nil }
        ?? ExerciseDemoLibrary.entries.first?.id ?? ""
    }.onChange(of: reduceMotion) { _, on in if on { moving = false } }
  }
}
