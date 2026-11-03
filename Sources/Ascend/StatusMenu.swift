import AppKit
import SwiftUI

/// A native menu closes its tracking session before a main-window action runs.
/// Rich quick check-in remains a sheet owned by the main window, not a status popup.
struct StatusMenu: View {
  @ObservedObject var store: TrackerStore
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    Button("Open Ascend") { open("Today") }
    Button("Quick check-in…") { open("QuickCheckIn") }.keyboardShortcut(
      "k", modifiers: [.command, .shift])
    Divider()
    Button("Body") { open("Body") }
    Button("Health") { open("Health") }
    Button("Screen time") { open("ScreenTime") }
    Button("Routine") { open("Routine") }
    Button("Meals") { open("Meals") }
    Button("Medicines") { open("Meds") }
    Button("Notes") { open("Notes") }
    Divider()
    Button("Settings…") { open("Settings") }
    Button("Quit Ascend") { NSApp.terminate(nil) }.keyboardShortcut("q")
  }
  private func open(_ destination: String) {
    DispatchQueue.main.async {
      openWindow(id: "main")
      NSApp.activate(ignoringOtherApps: true)
      // Window construction and menu dismissal complete on separate run-loop turns.
      DispatchQueue.main.async { store.pendingScreen = destination }
    }
  }
}
