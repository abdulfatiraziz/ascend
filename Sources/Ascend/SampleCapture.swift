import AppKit
import SwiftUI

/// Export only an explicitly requested, isolated sample render. No screen recording,
/// other windows, live profile, background service or user photographs are accessed.
@MainActor enum SampleCapture {
  static func export<V: View>(_ view: V) {
    let env = ProcessInfo.processInfo.environment
    guard env["ASCEND_BODY_SAMPLE"] == "1", env["ASCEND_DATA_DIR"] != nil,
      let destination = env["ASCEND_QA_CAPTURE_DIR"]
    else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      let root = NSHostingView(
        rootView: view.frame(width: 1120, height: 1500).preferredColorScheme(.dark))
      root.frame = NSRect(x: 0, y: 0, width: 1120, height: 1500)
      root.layoutSubtreeIfNeeded()
      guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
      root.cacheDisplay(in: root.bounds, to: bitmap)
      guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
      let folder = URL(fileURLWithPath: destination, isDirectory: true)
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent("body-native-sample.png"), options: .atomic)
      } catch {}
    }
  }
}
