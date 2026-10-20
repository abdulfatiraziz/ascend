import SwiftUI
import AscendCore

struct DailyObservationEditor: View {
    @ObservedObject var store: TrackerStore
    let day: String
    @Environment(\.dismiss) private var dismiss
    @State private var energy: Int
    @State private var mood: Int
    @State private var stress: Int
    @State private var manualSleep: Bool
    @State private var bedtime: Date
    @State private var wakeTime: Date
    @State private var asleep: String
    @State private var caffeineComplete: Bool
    @State private var urgesComplete: Bool
    @State private var note: String
    @State private var delete = false
    init(store: TrackerStore, day: String) {
        self.store = store; self.day = day
        let saved = store.document.wellbeing.observation(on: day)
        let imported = PatternsEngine(document: store.document, today: store.today).night(on: day)?.window
        let wake = saved?.sleep?.wakeTime ?? imported?.wakeTime ?? store.engine.time(on: day, minute: store.document.routine.wakeMinute)!
        var bed = store.engine.time(on: day, minute: store.document.routine.bedMinute)!
        if bed >= wake { bed = store.engine.calendar.date(byAdding: .day, value: -1, to: bed)! }
        _energy = State(initialValue: saved?.energy ?? 0); _mood = State(initialValue: saved?.mood ?? 0); _stress = State(initialValue: saved?.stress ?? 0)
        _manualSleep = State(initialValue: saved?.sleep != nil)
        _bedtime = State(initialValue: saved?.sleep?.bedtime ?? imported?.bedtime ?? bed)
        _wakeTime = State(initialValue: wake)
        _asleep = State(initialValue: saved?.sleep?.asleepHours.map { String($0) } ?? "")
        _caffeineComplete = State(initialValue: saved?.caffeineComplete ?? false); _urgesComplete = State(initialValue: saved?.urgesComplete ?? false)
        _note = State(initialValue: saved?.note ?? "")
    }
    private var candidate: DailyObservation {
        DailyObservation(day: day, energy: energy == 0 ? nil : energy, mood: mood == 0 ? nil : mood, stress: stress == 0 ? nil : stress,
                         sleep: manualSleep ? SleepWindow(bedtime: bedtime, wakeTime: wakeTime, asleepHours: numericInput(asleep)) : nil,
                         caffeineComplete: caffeineComplete, urgesComplete: urgesComplete, note: note)
    }
    private var dirty: Bool { candidate != (store.document.wellbeing.observation(on: day) ?? DailyObservation(day: day)) || (manualSleep && !asleep.isEmpty && numericInput(asleep) == nil) }
    private var error: String? {
        if note.count > 500 { return "Use 500 characters or fewer for the note." }
        if manualSleep {
            if !asleep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && numericInput(asleep) == nil { return "Enter valid asleep hours or leave the field empty." }
            if wakeTime > Date() { return "Wake time must be in the past or present." }
            do { try candidate.sleep!.validate(day: day, engine: store.engine) } catch { return error.localizedDescription }
        }
        return nil
    }
    var body: some View {
        EditorShell(title: "Your day · \(dateText(day, engine: store.engine, pattern: "d MMM"))", dirty: dirty) {
            Text("An overall reflection for this date. Everything is optional and stays separate from your habit score.").font(.system(size: 12)).foregroundStyle(Ink.muted)
            rating("Overall energy", selection: $energy, legend: "1 · drained                 5 · energetic")
            DisclosureGroup("Mood & stress (optional)") {
                VStack(alignment: .leading, spacing: 18) {
                    rating("Mood", selection: $mood, legend: "1 · low                         5 · good")
                    rating("Stress", selection: $stress, legend: "1 · low                         5 · high")
                }.padding(.top, 12)
            }.font(.system(size: 12))
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Use a manual sleep window", isOn: $manualSleep).toggleStyle(.switch).font(.system(size: 12))
                if manualSleep {
                    FieldGroup(label: "Bedtime") { DatePicker("Bedtime", selection: $bedtime, in: ...Date(), displayedComponents: [.date, .hourAndMinute]).labelsHidden() }
                    FieldGroup(label: "Wake time") { DatePicker("Wake time", selection: $wakeTime, in: ...Date(), displayedComponents: [.date, .hourAndMinute]).labelsHidden() }
                    FieldGroup(label: "Asleep hours (optional)") { TextField("Leave empty if unknown", text: $asleep).labelsHidden() }
                    Text("Sleep belongs to its wake date. The window includes time awake. Your correction takes priority over the main watch session until you turn it off.").font(.system(size: 11)).foregroundStyle(Ink.muted)
                } else { Text("Uses the main Mi Fitness sleep session when available. Add a manual window to fill a gap or correct it.").font(.system(size: 11)).foregroundStyle(Ink.muted) }
            }
            FieldGroup(label: "Finished logging for this date?") {
                Toggle("Caffeine log complete", isOn: $caffeineComplete).font(.system(size: 12))
                Toggle("Urge log complete", isOn: $urgesComplete).font(.system(size: 12))
                Text("Mark complete when the day's record is finished, including a day with none. Incomplete logs stay unknown in comparisons.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            }
            FieldGroup(label: "Note (optional)") { TextField("What shaped your day?", text: $note, axis: .vertical).lineLimit(2...4).labelsHidden() }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            SaveError(store: store)
        } actions: {
            HStack {
                if store.document.wellbeing.observation(on: day) != nil { Button("Delete check-in…", role: .destructive) { delete = true } }
                Spacer(); PrimaryButton(label: "Save check-in") { if store.saveObservation(candidate) { dismiss() } }.disabled(error != nil || day > store.today)
            }
        }
        .confirmationDialog("Delete this day's reflection?", isPresented: $delete, titleVisibility: .visible) {
            Button("Delete check-in", role: .destructive) { if store.deleteObservation(day) { dismiss() } }; Button("Cancel", role: .cancel) {}
        } message: { Text("Removes ratings, completeness markers, note and manual sleep correction. Caffeine, urges, watch data and habit check-ins stay intact. A backup and Undo are available.") }
    }
    private func rating(_ label: String, selection: Binding<Int>, legend: String) -> some View {
        FieldGroup(label: label) {
            Picker(label, selection: selection) { Text("Skip").tag(0); ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented).labelsHidden()
            Text(legend).font(.system(size: 10)).foregroundStyle(Ink.muted)
        }
    }
}
struct CaffeineEditor: View {
    @ObservedObject var store: TrackerStore
    let existing: CaffeineEntry?
    @Environment(\.dismiss) private var dismiss
    @State private var baseline: CaffeineEntry
    @State private var timestamp: Date
    @State private var name: String
    @State private var amount: String
    @State private var delete = false
    init(store: TrackerStore, entry: CaffeineEntry?, day: String) {
        self.store = store; existing = entry
        let time = day == store.today ? Date() : store.engine.time(on: day, minute: 12 * 60)!
        let initial = entry ?? CaffeineEntry(timestamp: time)
        _baseline = State(initialValue: initial); _timestamp = State(initialValue: initial.timestamp)
        _name = State(initialValue: initial.name); _amount = State(initialValue: initial.milligrams.map { String($0) } ?? "")
    }
    private var candidate: CaffeineEntry { CaffeineEntry(id: baseline.id, timestamp: timestamp, name: name, milligrams: numericInput(amount)) }
    private var invalidAmount: Bool { !amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (numericInput(amount).map { $0 > 2000 } ?? true) }
    private var dirty: Bool { candidate != baseline || invalidAmount }
    var body: some View {
        EditorShell(title: existing == nil ? "Log caffeine" : "Edit caffeine", dirty: dirty) {
            FieldGroup(label: "What did you have?") { TextField("Give this a name", text: $name).labelsHidden() }
            FieldGroup(label: "Date & time") { DatePicker("Caffeine time", selection: $timestamp, in: ...Date(), displayedComponents: [.date, .hourAndMinute]).labelsHidden() }
            FieldGroup(label: "Caffeine amount (mg, optional)") { TextField("Leave empty if unknown", text: $amount).labelsHidden() }
            Text("Use an amount from the label or your own estimate. Leaving it blank keeps the amount unknown; the time still appears in your timeline.").font(.system(size: 12)).foregroundStyle(Ink.muted)
            if invalidAmount { Text("Use a finite amount from 0–2,000 mg, or leave it empty.").font(.system(size: 11)).foregroundStyle(.orange) }
            if name.count > 60 { Text("Use a name with 60 characters or fewer.").font(.system(size: 11)).foregroundStyle(.orange) }
            SaveError(store: store)
        } actions: {
            HStack {
                if existing != nil { Button("Delete entry…", role: .destructive) { delete = true } }
                Spacer(); PrimaryButton(label: "Save caffeine") { if store.saveCaffeine(candidate) { dismiss() } }.disabled(invalidAmount || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 60 || timestamp > Date())
            }
        }
        .confirmationDialog("Delete this caffeine entry?", isPresented: $delete, titleVisibility: .visible) {
            Button("Delete entry", role: .destructive) { if store.deleteCaffeine(baseline.id) { dismiss() } }; Button("Cancel", role: .cancel) {}
        } message: { Text("A backup and Undo will be available. Your other observations stay intact.") }
    }
}
