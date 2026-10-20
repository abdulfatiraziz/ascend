import SwiftUI
import AppKit
import AscendCore

struct EditorShell<Content: View, Actions: View>: View {
    let title: String
    var dirty = false
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions
    @Environment(\.dismiss) private var dismiss
    @State private var discard = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title).font(.system(size: 23, weight: .medium)).tracking(-0.7).lineLimit(2); Spacer()
                Button { if dirty { discard = true } else { dismiss() } } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).keyboardShortcut(.cancelAction).accessibilityLabel("Close editor")
            }
            Line()
            ScrollView { VStack(alignment: .leading, spacing: 20) { content }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 6).padding(.vertical, 2) }.frame(maxHeight: 390)
            Line()
            actions
        }.padding(24).frame(width: 500).background(Ink.background).tint(Ink.accent).foregroundStyle(.white)
            .interactiveDismissDisabled(dirty)
            .confirmationDialog("Discard unsaved changes?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }; Button("Keep editing", role: .cancel) {}
            }
    }
}
struct FieldGroup<Content: View>: View {
    var label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Ink.muted); content }
            .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity, alignment: .leading)
    }
}
func numericInput(_ text: String) -> Double? {
    let decimal = Locale.current.decimalSeparator ?? "."
    let raw = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: decimal, with: ".")
    guard let number = Double(raw), number.isFinite, number >= 0 else { return nil }
    return number
}
struct SaveError: View {
    @ObservedObject var store: TrackerStore
    var body: some View { if let error = store.saveError ?? store.notice { Text(error).font(.system(size: 11)).foregroundStyle(.orange); Button("Retry saving") { store.save() } } }
}
struct GoalEditor: View {
    @ObservedObject var store: TrackerStore
    let goal: Goal?
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    init(store: TrackerStore, goal: Goal?) {
        self.store = store; self.goal = goal
        _title = State(initialValue: goal?.title ?? "")
        _start = State(initialValue: store.engine.date(goal?.latest.start ?? store.document.cycle.start)!)
        _end = State(initialValue: store.engine.date(goal?.latest.end ?? store.document.cycle.end)!)
    }
    private var dirty: Bool { title != (goal?.title ?? "") || store.engine.key(start) != (goal?.latest.start ?? store.document.cycle.start) || store.engine.key(end) != (goal?.latest.end ?? store.document.cycle.end) }
    var body: some View {
        EditorShell(title: goal == nil ? "New goal" : "Edit goal", dirty: dirty) {
            FieldGroup(label: "Goal name") { TextField("e.g. Physique & health", text: $title).labelsHidden() }
            HStack(spacing: 24) {
                FieldGroup(label: "Start date") { DatePicker("Start", selection: $start, displayedComponents: .date).labelsHidden() }
                FieldGroup(label: "End date") { DatePicker("End", selection: $end, displayedComponents: .date).labelsHidden() }
            }
            Text("Date edits apply from today. Earlier check-ins keep their original goal window.").font(.system(size: 12)).foregroundStyle(Ink.muted)
            if end < start { Text("End date must be on or after the start date.").font(.system(size: 12)).foregroundStyle(.orange) }
            SaveError(store: store)
        } actions: {
            HStack { Spacer(); PrimaryButton(label: "Save goal") {
                if store.saveGoal(id: goal?.id, title: title, symbol: goal?.symbol ?? "flag", start: store.engine.key(start), end: store.engine.key(end)) { dismiss() }
            }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || end < start) }
        }
    }
}
struct HabitEditor: View {
    @ObservedObject var store: TrackerStore
    let habit: Habit?
    @Environment(\.dismiss) private var dismiss
    @State private var goalID: UUID
    @State private var title: String
    @State private var note: String
    @State private var kind: HabitKind
    @State private var period: Period
    @State private var days: Set<Int>
    @State private var dueDate: Date
    @State private var minimum: String
    @State private var maximum: String
    @State private var unit: String
    @State private var confirmArchive = false
    @State private var hasExactTime: Bool
    @State private var exactTime: Date
    init(store: TrackerStore, habit: Habit?, goalID: UUID?) {
        self.store = store; self.habit = habit
        let r = habit?.latest
        _goalID = State(initialValue: habit?.goalID ?? goalID ?? store.document.goals.first?.id ?? UUID())
        _title = State(initialValue: r?.title ?? ""); _note = State(initialValue: r?.note ?? "")
        _kind = State(initialValue: habit?.kind ?? .check); _period = State(initialValue: r?.period ?? .daytime)
        _days = State(initialValue: Set(r?.schedule.weekdays ?? Array(1...7)))
        _dueDate = State(initialValue: store.engine.date(r?.schedule.once ?? store.today)!)
        _minimum = State(initialValue: r?.target?.minimum.map { String($0) } ?? "")
        _maximum = State(initialValue: r?.target?.maximum.map { String($0) } ?? "")
        _unit = State(initialValue: r?.target?.unit ?? "")
        _hasExactTime = State(initialValue: r?.scheduledMinute != nil)
        _exactTime = State(initialValue: store.engine.time(on: store.today, minute: r?.scheduledMinute ?? 12 * 60)!)
    }
    private var validation: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give this habit a name." }
        if !store.document.goals.contains(where: { $0.id == goalID }) { return "Create a goal before adding habits." }
        if kind != .milestone && days.isEmpty { return "Choose at least one repeat day." }
        if kind == .milestone && store.engine.key(dueDate) < store.today { return "New due dates must be today or later." }
        if kind == .metric {
            if unit.trimmingCharacters(in: .whitespaces).isEmpty { return "Add a unit, such as hours, steps or g." }
            if minimum.isEmpty && maximum.isEmpty { return "Set a minimum, a maximum, or both." }
            if (!minimum.isEmpty && numericInput(minimum) == nil) || (!maximum.isEmpty && numericInput(maximum) == nil) { return "Targets must be finite numbers of zero or more." }
            if let a = numericInput(minimum), let b = numericInput(maximum), a > b { return "Minimum cannot exceed maximum." }
        }
        return nil
    }
    private var dirty: Bool {
        let r = habit?.latest
        return hasExactTime != (r?.scheduledMinute != nil) || (hasExactTime && store.engine.minute(exactTime) != r?.scheduledMinute) || title != (r?.title ?? "") || note != (r?.note ?? "") || kind != (habit?.kind ?? .check) || period != (r?.period ?? .daytime) || days != Set(r?.schedule.weekdays ?? Array(1...7)) || unit != (r?.target?.unit ?? "") || minimum != (r?.target?.minimum.map { String($0) } ?? "") || maximum != (r?.target?.maximum.map { String($0) } ?? "") || (kind == .milestone && store.engine.key(dueDate) != (r?.schedule.once ?? store.today))
    }
    var body: some View {
        EditorShell(title: habit == nil ? "New habit or task" : "Edit habit", dirty: dirty) {
            FieldGroup(label: "Name") { TextField("e.g. Sleep", text: $title).labelsHidden() }
            HStack(spacing: 16) {
                FieldGroup(label: "Goal") { Picker("Goal", selection: $goalID) { ForEach(store.document.goals) { Text($0.title).tag($0.id) } }.labelsHidden().disabled(habit != nil) }
                FieldGroup(label: "Type") { Picker("Type", selection: $kind) { ForEach(HabitKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().disabled(habit != nil) }
            }
            if habit != nil { Text("Goal and type are fixed to keep historical records consistent.").font(.system(size: 11)).foregroundStyle(Ink.muted) }
            FieldGroup(label: "Time of day") { Picker("When", selection: $period) { ForEach(Period.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden() }
            Toggle("Set an exact time on the routine clock", isOn: $hasExactTime).font(.system(size: 12))
            if hasExactTime { FieldGroup(label: "Local time · \(store.document.timeZoneID)") { DatePicker("Habit time", selection: $exactTime, displayedComponents: .hourAndMinute).labelsHidden() } }
            FieldGroup(label: "Note (optional)") { TextField("A reminder or context", text: $note).labelsHidden() }
            if kind == .milestone {
                FieldGroup(label: "Due date") { DatePicker("Due date", selection: $dueDate, displayedComponents: .date).labelsHidden() }
            } else { repeatDays }
            if kind == .metric {
                FieldGroup(label: "Unit") { TextField("hours / steps / g", text: $unit).labelsHidden() }
                HStack(spacing: 16) {
                    FieldGroup(label: "Minimum (optional)") { TextField("No minimum", text: $minimum).labelsHidden().accessibilityLabel("Minimum") }
                    FieldGroup(label: "Maximum (optional)") { TextField("No maximum", text: $maximum).labelsHidden().accessibilityLabel("Maximum") }
                }
            }
            if let message = validation { Text(message).foregroundStyle(.orange).font(.system(size: 12)) }
            Text("Schedule and target edits apply from today. Past dates keep their original rules.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            SaveError(store: store)
        } actions: {
            HStack {
                if habit != nil { Button("Archive…") { confirmArchive = true }.buttonStyle(.borderless).foregroundStyle(Ink.muted) }
                Spacer(); PrimaryButton(label: "Save habit", action: save).disabled(validation != nil)
            }
        }
        .confirmationDialog("Archive this habit?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archive habit", role: .destructive) { if let habit, store.archive(habit) { dismiss() } }; Button("Cancel", role: .cancel) {}
        } message: { Text("It will leave today’s plan. Earlier dates stay available in Calendar. You can restore it as a new habit in Settings.") }
    }
    private var repeatDays: some View {
        FieldGroup(label: "Repeat on") {
            HStack(spacing: 8) {
                ForEach([2,3,4,5,6,7,1], id: \.self) { d in
                    Button { if days.contains(d) { days.remove(d) } else { days.insert(d) } } label: {
                        Text(["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"][d-1]).font(.system(size: 11, weight: .medium)).frame(width: 39, height: 34).background(days.contains(d) ? Ink.accent : Ink.panel, in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(days.contains(d) ? Ink.background : .white)
                    }.buttonStyle(.plain).accessibilityLabel(["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][d-1]).accessibilityAddTraits(days.contains(d) ? .isSelected : [])
                }
            }
            HStack { Button("Every day") { days = Set(1...7) }; Button("Mon · Wed · Fri · Sat") { days = [2,4,6,7] } }.font(.system(size: 11)).buttonStyle(.borderless)
        }
    }
    private func save() {
        guard validation == nil else { return }
        let schedule = kind == .milestone ? Schedule(weekdays: [], once: store.engine.key(dueDate)) : Schedule(weekdays: days.sorted())
        let target = kind == .metric ? MetricTarget(minimum: numericInput(minimum), maximum: numericInput(maximum), unit: unit.trimmingCharacters(in: .whitespaces)) : nil
        if store.saveHabit(id: habit?.id, goalID: goalID, kind: kind, title: title, note: note, period: period, schedule: schedule, target: target, scheduledMinute: hasExactTime ? store.engine.minute(exactTime) : nil) { dismiss() }
    }
}
struct MetricEditor: View {
    @ObservedObject var store: TrackerStore
    let habit: Habit
    let day: String
    @Environment(\.dismiss) private var dismiss
    @State private var value: String
    private var revision: HabitRevision { habit.revision(on: day) ?? habit.latest }
    private var original: String { store.engine.entry(for: habit, day: day)?.value.map { String($0) } ?? "" }
    init(store: TrackerStore, habit: Habit, day: String) {
        self.store = store; self.habit = habit; self.day = day
        _value = State(initialValue: store.engine.entry(for: habit, day: day)?.value.map { String($0) } ?? "")
    }
    var body: some View {
        EditorShell(title: revision.title, dirty: value != original) {
            Text("\(dateText(day, engine: store.engine)) · Target: \(revision.target?.label ?? "")").font(.system(size: 13)).foregroundStyle(Ink.muted)
            FieldGroup(label: revision.target?.unit ?? "Value") { TextField("Enter value", text: $value).font(.system(size: 24)).labelsHidden().onSubmit { save() } }
            if let n = numericInput(value) { Text(revision.target?.accepts(n) == true ? "Target reached." : "This value will be saved; it is outside your target.").font(.system(size: 12)).foregroundStyle(Ink.muted) }
            else if !value.isEmpty { Text("Enter a finite number of zero or more.").font(.system(size: 12)).foregroundStyle(.orange) }
            SaveError(store: store)
        } actions: {
            HStack {
                Button("Clear entry") { if store.log(habit, value: nil, day: day) { dismiss() } }.buttonStyle(.borderless).disabled(original.isEmpty)
                Spacer(); PrimaryButton(label: "Save check-in", action: save).disabled(numericInput(value) == nil || day > store.today)
            }
        }
    }
    private func save() { if let n = numericInput(value), store.log(habit, value: n, day: day) { dismiss() } }
}

struct SettingsEditor: View {
    @ObservedObject var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var target: Double
    @State private var restartLength = 84
    @State private var confirmRestart = false
    @State private var confirmReset = false
    init(store: TrackerStore) {
        self.store = store
        _title = State(initialValue: store.document.cycle.title)
        _start = State(initialValue: store.engine.date(store.document.cycle.start)!)
        _end = State(initialValue: store.engine.date(store.document.cycle.end)!)
        _target = State(initialValue: store.document.cycle.target)
    }
    private var dirty: Bool { title != store.document.cycle.title || store.engine.key(start) != store.document.cycle.start || store.engine.key(end) != store.document.cycle.end || target != store.document.cycle.target }
    var body: some View {
        EditorShell(title: "Your space", dirty: dirty) {
            FieldGroup(label: "Avatar appearance · saves immediately") {
                Picker("Avatar appearance", selection: Binding(get: { store.document.avatarFinish }, set: { store.finish($0) })) {
                    Text("Follow progress").tag("Progress")
                    ForEach(["Obsidian", "Titanium", "Ascendant"], id: \.self) { Text($0).tag($0) }
                }.labelsHidden()
                Text("Follow progress starts at Obsidian, reaches Titanium halfway to your cycle goal, and Ascendant when the goal is earned. Fixed appearances are cosmetic.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            }
            Line(); Kicker("Cycle")
            FieldGroup(label: "Cycle name") { TextField("Cycle name", text: $title).labelsHidden() }
            HStack(spacing: 20) {
                FieldGroup(label: "Start") { DatePicker("Start", selection: $start, displayedComponents: .date).labelsHidden() }
                FieldGroup(label: "End") { DatePicker("End", selection: $end, displayedComponents: .date).labelsHidden() }
            }
            HStack { Button("12 weeks / 84 days") { setLength(83) }; Button("90 days") { setLength(89) } }.font(.system(size: 11))
            FieldGroup(label: "Consistency target · \(Int((target * 100).rounded()))%") { Slider(value: $target, in: 0.5...1, step: 0.05) }
            if end < start { Text("End date must be on or after start date.").font(.system(size: 12)).foregroundStyle(.orange) }
            Text("Goals using the cycle’s dates move with it. Custom goal windows keep their dates. Rest days are excluded from consistency.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            Line(); Kicker("Routine & assistant")
            HStack { Button("Set routine clock…") { store.pendingScreen = "RoutineSettings" }; Button("Claude settings…") { store.pendingScreen = "AISettings" } }.font(.system(size: 12))
            Text("Routine and urge tracking stay local. Ask Ascend is optional and uses your personal Claude Code account.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            Line(); ReminderSettings(store: store, service: store.notifications)
            Line(); Kicker("Start fresh")
            Text("Start a new cycle today using your active habits. Earlier records stay in Calendar. Today’s values are cleared; all goals get the new dates and one-off due dates move relative to the new start. Archived habits stay archived.").font(.system(size: 12)).foregroundStyle(Ink.muted)
            Picker("New cycle length", selection: $restartLength) { Text("84 days").tag(84); Text("90 days").tag(90) }.pickerStyle(.segmented)
            Button("Start a new cycle…") { confirmRestart = true }.disabled(dirty)
            if dirty { Text("Save your cycle edits before starting over.").font(.system(size: 11)).foregroundStyle(Ink.muted) }
            Button("Reset all check-in history…", role: .destructive) { confirmReset = true }.disabled(store.document.checkIns.isEmpty && store.document.restDays.isEmpty)
            Text("Both actions create a dated backup and offer Undo until your next edit.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            Line(); Kicker("Local data")
            Text("Saved on this Mac. No account or cloud sync. Calendar time zone: \(store.document.timeZoneID).").font(.system(size: 12)).foregroundStyle(Ink.muted)
            HStack { Button("Export backup…") { store.exportBackup() }; Button("Restore backup…") { store.importBackup() }; Button("Show data") { store.revealData() } }.font(.system(size: 11))
            SaveError(store: store)
            if !archived.isEmpty {
                Line(); Kicker("Archived habits")
                ForEach(archived) { habit in HStack { Text(habit.latest.title).font(.system(size: 12)); Spacer(); Button("Restore as new") { store.restore(habit) }.font(.system(size: 11)) } }
            }
            Text("The avatar reflects check-ins, not body measurements. Health imports and manual sleep windows are available in Health and Patterns.").font(.system(size: 11)).foregroundStyle(Ink.muted)
        } actions: {
            HStack { Spacer(); PrimaryButton(label: "Save cycle") {
                if store.updateCycle(title: title.trimmingCharacters(in: .whitespacesAndNewlines), start: store.engine.key(start), end: store.engine.key(end), target: target) { dismiss() }
            }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || end < start) }
        }
        .confirmationDialog("Start a new \(restartLength)-day cycle today?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Start new cycle", role: .destructive) { store.restart(length: restartLength); if store.saveError == nil { syncCycle() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Today’s check-ins will be cleared. Your active habits continue, all goal dates restart, and earlier dates stay in Calendar. A safety backup and Undo will be available in the main window.") }
        .confirmationDialog("Reset all check-in history?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset all history", role: .destructive) { store.resetProgress() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Clears ALL habit check-ins, numeric values and rest days across every date. Your goals, habits, cycle dates and urge logs stay intact. A safety backup is saved first. Close Settings to Undo before making another edit.") }
    }
    private var archived: [Habit] { store.document.habits.filter { $0.archivedDay != nil } }
    private func setLength(_ days: Int) { end = store.engine.date(store.engine.adding(days, to: store.engine.key(start)))! }
    private func syncCycle() {
        title = store.document.cycle.title; start = store.engine.date(store.document.cycle.start)!; end = store.engine.date(store.document.cycle.end)!; target = store.document.cycle.target
    }
}
struct ReminderSettings: View {
    @ObservedObject var store: TrackerStore
    @ObservedObject var service: ReminderService
    @State private var enabling = false
    @State private var morning: Date
    @State private var evening: Date
    init(store: TrackerStore, service: ReminderService) {
        self.store = store; self.service = service
        let date = store.engine.date(store.today)!
        let c = store.engine.calendar, r = store.document.reminders
        _morning = State(initialValue: c.date(bySettingHour: r.morningMinute / 60, minute: r.morningMinute % 60, second: 0, of: date)!)
        _evening = State(initialValue: c.date(bySettingHour: r.eveningMinute / 60, minute: r.eveningMinute % 60, second: 0, of: date)!)
    }
    private func minute(_ date: Date) -> Int { let c = store.engine.calendar; return c.component(.hour, from: date) * 60 + c.component(.minute, from: date) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker("Reminders · saves immediately")
            Toggle("Daily check-in reminders", isOn: Binding(get: { store.document.reminders.enabled }, set: { enabled in
                if enabled {
                    enabling = true
                    Task { @MainActor in
                        if await service.enable(store.document) { var r = store.document.reminders; r.enabled = true; store.saveReminders(r) }
                        enabling = false
                    }
                } else { var r = store.document.reminders; r.enabled = false; store.saveReminders(r) }
            })).disabled(enabling)
            Text(enabling ? "Waiting for macOS permission…" : service.status).font(.system(size: 11)).foregroundStyle(Ink.muted)
            HStack {
                DatePicker("Morning", selection: $morning, displayedComponents: .hourAndMinute)
                DatePicker("Evening", selection: $evening, displayedComponents: .hourAndMinute)
            }.font(.system(size: 12))
            if minute(morning) >= minute(evening) { Text("Evening must follow morning.").font(.system(size: 11)).foregroundStyle(.orange) }
            Text("Times save automatically when evening follows morning.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            Toggle("Play a sound", isOn: Binding(get: { store.document.reminders.sound }, set: { value in var r = store.document.reminders; r.sound = value; store.saveReminders(r) })).font(.system(size: 12))
            HStack {
                Button("Send test notification") { Task { await service.test(sound: store.document.reminders.sound) } }.disabled(!service.authorized)
                Button("macOS settings ↗") { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") { NSWorkspace.shared.open(url) } }
            }.font(.system(size: 11))
            Text("Morning nudges for morning habits; evening nudges for unfinished recurring tasks. Rest days and completed days are skipped. Scheduled locally for the next 30 days, refreshed when you open Ascend. Times use \(store.document.timeZoneID). macOS Focus and notification settings control delivery.").font(.system(size: 11)).foregroundStyle(Ink.muted)
        }
        .onChange(of: morning) { _, _ in saveTimes() }
        .onChange(of: evening) { _, _ in saveTimes() }
    }
    private func saveTimes() {
        guard minute(morning) < minute(evening) else { return }
        var r = store.document.reminders
        r.morningMinute = minute(morning); r.eveningMinute = minute(evening)
        store.saveReminders(r)
    }
}
