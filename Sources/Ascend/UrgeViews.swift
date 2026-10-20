import SwiftUI
import AscendCore

struct UrgesView: View {
    @ObservedObject var store: TrackerStore
    @Binding var editor: Editor?
    @State private var filter = "This week"
    private var visible: [UrgeLog] {
        let start = filter == "Today" ? store.today : filter == "This week" ? store.engine.adding(-6, to: store.today) : "1900-01-01"
        return store.document.urgeLogs.filter { store.engine.key($0.timestamp) >= start && store.engine.key($0.timestamp) <= store.today }.sorted { $0.timestamp > $1.timestamp }
    }
    private var groups: [String] { Array(Set(visible.map { store.engine.key($0.timestamp) })).sorted(by: >) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker("A moment, not a verdict")
                    Text("Log any urge privately. Your habit check-ins stay separate.").font(.system(size: 12)).foregroundStyle(Ink.muted)
                }
                Spacer()
                PrimaryButton(label: "Log an urge now") { store.recordUrge() }
            }
            tallyStrip
            HStack {
                Picker("Urge history", selection: $filter) { ForEach(["Today", "This week", "All time"], id: \.self) { Text($0).tag($0) } }.labelsHidden().pickerStyle(.segmented).frame(width: 285)
                Spacer(); Text("\(visible.count) logged").font(.system(size: 12, design: .monospaced)).foregroundStyle(Ink.muted)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if visible.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "circle.dotted").font(.system(size: 32)).foregroundStyle(Ink.accent)
                            Text("A place to notice the pattern.").font(.system(size: 19, weight: .medium))
                            Text("Use “Log an urge” whenever it happens. Time is saved immediately; details are optional.").font(.system(size: 12)).foregroundStyle(Ink.muted).multilineTextAlignment(.center).frame(maxWidth: 370)
                        }.frame(maxWidth: .infinity).padding(.vertical, 65)
                    }
                    ForEach(groups, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 12) {
                            Kicker(day == store.today ? "Today" : dateText(day, engine: store.engine, pattern: "EEEE, d MMM"))
                            ForEach(visible.filter { store.engine.key($0.timestamp) == day }) { urge in
                                Button { editor = .urge(urge.id) } label: {
                                    HStack(spacing: 18) {
                                        Text(timeText(urge.timestamp, engine: store.engine)).font(.system(size: 18, weight: .medium, design: .monospaced)).frame(width: 65, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(urge.category ?? urge.triggerLabel ?? "Urge logged").font(.system(size: 13))
                                            Text([urge.category == nil ? nil : urge.triggerLabel, urge.outcome.rawValue].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Ink.muted)
                                        }
                                        Spacer()
                                        if let intensity = urge.intensity { Text("\(intensity)/5 intensity").font(.system(size: 11)).foregroundStyle(Ink.muted) }
                                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Ink.muted)
                                    }.frame(maxWidth: .infinity, alignment: .leading).panel(padding: 16)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if !visible.isEmpty { patternSummary }
                }
            }
            Text("Stored only on this Mac, included in your backups, and excluded from AI context. Habit resets and new cycles preserve these observations.").font(.system(size: 11)).foregroundStyle(Ink.muted)
        }
    }
    /// Let pass vs acted on for today, the week and the cycle, plus days since the last urge acted on.
    private var tallyStrip: some View {
        let tally = store.urgeTally
        func block(_ title: String, _ counts: UrgeTally.Counts) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(title)
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) { Text("\(counts.passed)").font(.system(size: 22, weight: .semibold)); Text("let pass").font(.system(size: 10)).foregroundStyle(Ink.muted) }
                    VStack(alignment: .leading, spacing: 2) { Text("\(counts.acted)").font(.system(size: 22, weight: .semibold)).foregroundStyle(counts.acted > 0 ? Color.orange : Color.primary); Text("acted on").font(.system(size: 10)).foregroundStyle(Ink.muted) }
                }
                Text(counts.unrecorded > 0 ? "+ \(counts.unrecorded) without an outcome" : " ").font(.system(size: 10)).foregroundStyle(Ink.muted)
            }.frame(maxWidth: .infinity, alignment: .leading).panel(padding: 14)
        }
        return HStack(spacing: 12) {
            block("Today", tally.today); block("Last 7 days", tally.week); block("This cycle", tally.cycle)
            VStack(alignment: .leading, spacing: 6) {
                Kicker("Since last acted on")
                HStack(alignment: .firstTextBaseline, spacing: 5) { Text("\(tally.cleanDays)").font(.system(size: 22, weight: .semibold)); Text(tally.cleanDays == 1 ? "day" : "days").font(.system(size: 10)).foregroundStyle(Ink.muted) }
                Text(tally.lastActed.map { "Last: \(dateText(store.engine.key($0), engine: store.engine, pattern: "d MMM")) \(timeText($0, engine: store.engine))" } ?? "None this cycle").font(.system(size: 10)).foregroundStyle(Ink.muted)
            }.frame(maxWidth: .infinity, alignment: .leading).panel(padding: 14)
        }
    }
    private var patternSummary: some View {
        let groups = Dictionary(grouping: visible.compactMap(\.triggerLabel), by: { $0.lowercased() })
        let top = groups.sorted { $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count }.first
        return HStack {
            Text("Patterns in this view").font(.system(size: 13, weight: .medium))
            Spacer()
            Text(top.map { "Most logged trigger: \($0.value.first ?? $0.key) · \($0.value.count)" } ?? "Add optional triggers to see patterns.").font(.system(size: 12)).foregroundStyle(Ink.muted).lineLimit(2)
        }.padding(.vertical, 12)
    }
}
struct UrgeEditor: View {
    @ObservedObject var store: TrackerStore
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var intensity: Int
    @State private var trigger: String
    @State private var customTrigger: String
    @State private var outcome: UrgeOutcome
    @State private var note: String
    @State private var category: String
    @State private var confirmDelete = false
    private var urge: UrgeLog? { store.document.urgeLogs.first { $0.id == id } }
    init(store: TrackerStore, id: UUID) {
        self.store = store; self.id = id
        let urge = store.document.urgeLogs.first { $0.id == id }
        _intensity = State(initialValue: urge?.intensity ?? 0); _trigger = State(initialValue: urge?.trigger?.rawValue ?? "Not recorded")
        _category = State(initialValue: urge?.category ?? "")
        _customTrigger = State(initialValue: urge?.customTrigger ?? "")
        _outcome = State(initialValue: urge?.outcome ?? .unrecorded); _note = State(initialValue: urge?.note ?? "")
    }
    private var dirty: Bool { intensity != (urge?.intensity ?? 0) || trigger != (urge?.trigger?.rawValue ?? "Not recorded") || customTrigger != (urge?.customTrigger ?? "") || outcome != (urge?.outcome ?? .unrecorded) || note != (urge?.note ?? "") || category != (urge?.category ?? "") }
    private var customInvalid: Bool { trigger == UrgeTrigger.other.rawValue && (customTrigger.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 || customTrigger.trimmingCharacters(in: .whitespacesAndNewlines).rangeOfCharacter(from: .newlines) != nil) }
    var body: some View {
        EditorShell(title: "A moment you noticed", dirty: dirty) {
            if let urge {
                Text("\(dateText(store.engine.key(urge.timestamp), engine: store.engine)) · \(timeText(urge.timestamp, engine: store.engine))").font(.system(size: 13)).foregroundStyle(Ink.muted)
                Text("Your time is already saved. Everything below is optional.").font(.system(size: 12)).foregroundStyle(Ink.muted)
                FieldGroup(label: "Label (optional)") { TextField("Give this a name", text: $category).labelsHidden() }
                if category.count > 60 { Text("Use 60 characters or fewer for the label.").font(.system(size: 12)).foregroundStyle(.orange) }
                FieldGroup(label: "Intensity") {
                    Picker("Intensity", selection: $intensity) { Text("Skip").tag(0); ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented).labelsHidden()
                    Text("1 · mild                     5 · strong").font(.system(size: 11)).foregroundStyle(Ink.muted)
                }
                FieldGroup(label: "What was happening?") {
                    Picker("Trigger", selection: $trigger) { Text("Not recorded").tag("Not recorded"); ForEach(UrgeTrigger.allCases, id: \.self) { Text($0 == .other ? "Other · write your own" : $0.rawValue).tag($0.rawValue) } }.labelsHidden()
                    if trigger == UrgeTrigger.other.rawValue {
                        TextField("e.g. Work break", text: $customTrigger).accessibilityLabel("Custom trigger")
                        Text(customInvalid ? "Use a single line of 40 characters or fewer." : "A word or two is enough. Leave blank to keep Other.").font(.system(size: 11)).foregroundStyle(customInvalid ? .orange : Ink.muted)
                    }
                }
                FieldGroup(label: "Outcome") { Picker("Outcome", selection: $outcome) { ForEach(UrgeOutcome.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden() }
                FieldGroup(label: "Note (optional)") { TextField("Anything you want to remember", text: $note, axis: .vertical).lineLimit(3...5).labelsHidden() }
                if note.count > 500 { Text("Use 500 characters or fewer.").font(.system(size: 12)).foregroundStyle(.orange) }
                Text("This record stays separate from your daily habits.").font(.system(size: 11)).foregroundStyle(Ink.muted)
                SaveError(store: store)
            } else { Text("This log no longer exists.").foregroundStyle(Ink.muted) }
        } actions: {
            HStack {
                Button("Delete log…", role: .destructive) { confirmDelete = true }.disabled(urge == nil)
                Spacer(); PrimaryButton(label: "Save details") {
                    if store.updateUrge(id: id, intensity: intensity == 0 ? nil : intensity, trigger: UrgeTrigger(rawValue: trigger), outcome: outcome, note: note, category: category, customTrigger: customTrigger) { dismiss() }
                }.disabled(urge == nil || note.count > 500 || category.count > 60 || customInvalid)
            }
        }
        .confirmationDialog("Delete this urge log?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete log", role: .destructive) { if store.deleteUrge(id) { dismiss() } }; Button("Cancel", role: .cancel) {}
        } message: { Text("Your habit check-ins stay intact. Undo is available in the main window until your next edit.") }
    }
}
func timeText(_ date: Date, engine: TrackerEngine) -> String {
    let formatter = DateFormatter(); formatter.calendar = engine.calendar; formatter.timeZone = engine.calendar.timeZone; formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}
