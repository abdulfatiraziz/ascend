import SwiftUI
import AppKit

@main struct AscendApp: App {
    @StateObject private var store = TrackerStore()
    var body: some Scene {
        Window("Ascend", id: "main") {
            MainView(store: store).preferredColorScheme(.dark)
                .environment(\.calendar, store.engine.calendar)
                .environment(\.timeZone, store.engine.calendar.timeZone)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 860)
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
