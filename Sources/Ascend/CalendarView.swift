import SwiftUI
import AscendCore

struct DayActions: View {
    @ObservedObject var store: TrackerStore
    let day: String
    @State private var confirmReset = false
    var body: some View {
        Menu {
            Button(store.document.restDays.contains(day) ? "Resume day" : "Mark as rest day") {
                store.setRestDay(day, rest: !store.document.restDays.contains(day))
            }
            Divider()
            Button("Reset this date…", role: .destructive) { confirmReset = true }
                .disabled(!store.document.checkIns.contains { $0.day == day } && !store.document.restDays.contains(day))
        } label: { Label("Day options", systemImage: "ellipsis.circle") }
        .menuStyle(.borderlessButton).fixedSize().disabled(day > store.today)
        .confirmationDialog("Reset \(dateText(day, engine: store.engine))?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset this date", role: .destructive) { store.resetDay(day) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Clears this date’s check-ins, numeric values and rest marker. Other dates and your plan stay intact. A safety backup and Undo will be available.") }
    }
}
