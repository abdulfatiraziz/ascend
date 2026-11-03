import SwiftUI
import AppKit

@main struct AscendApp: App {
    @StateObject private var store = TrackerStore()
    /// Ascend is dark-only. preferredColorScheme doesn't reach the menu bar window's AppKit controls
    /// (segmented pickers, scrollers, plain buttons), so set the app's appearance itself.
    init() { NSApplication.shared.appearance = NSAppearance(named: .darkAqua) }
    // Isolated sample launches can verify fixed window sizes without touching live UI preferences.
    private func sampleDimension(_ key:String,fallback:Double,minimum:Double)->Double {
        guard ProcessInfo.processInfo.environment["ASCEND_DATA_DIR"] != nil,
              let raw=ProcessInfo.processInfo.environment[key],let value=Double(raw),value.isFinite else{return fallback}
        return min(1800,max(minimum,value))
    }
    var body: some Scene {
        Window("Ascend", id: "main") {
            MainView(store: store).preferredColorScheme(.dark)
                .environment(\.calendar, store.engine.calendar)
                .environment(\.timeZone, store.engine.calendar.timeZone)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: sampleDimension("ASCEND_QA_WIDTH",fallback:1120,minimum:980), height: sampleDimension("ASCEND_QA_HEIGHT",fallback:860,minimum:720))
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appSettings) {
                Button("Export backup…") { store.exportBackup() }.keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
        MenuBarExtra {
            MenuBarPanel(store: store).preferredColorScheme(.dark)
                .environment(\.calendar, store.engine.calendar)
                .environment(\.timeZone, store.engine.calendar.timeZone)
        } label: {
            let score = store.engine.score(on: store.today)
            Label("\(score.completed)/\(score.scheduled)", systemImage: "circle.hexagongrid")
        }.menuBarExtraStyle(.window)
    }
}
