import SwiftUI
import AppKit
import AscendCore

struct GoalsView: View {
    @ObservedObject var store: TrackerStore
    @Binding var editor: Editor?
    private var oneOffs: [Habit] {
        store.document.habits.filter { $0.kind == .milestone && $0.archivedDay == nil }.sorted { ($0.latest.schedule.once ?? "") < ($1.latest.schedule.once ?? "") }
    }
    var body: some View {
        ScrollView {
            MissionBoard(store: store, missions: store.missions, editor: $editor)
            if !oneOffs.isEmpty { milestones.padding(.top, 28) }
        }
    }
    private var milestones: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker("One-off milestones / separate from habit score")
            ForEach(oneOffs) { habit in
                HStack {
                    Button { store.completeMilestone(habit) } label: { Image(systemName: store.engine.milestoneCompleted(habit) ? "checkmark.circle.fill" : "circle").foregroundStyle(store.engine.milestoneCompleted(habit) ? Ink.accent : Ink.muted) }.buttonStyle(.plain).accessibilityLabel("Complete \(habit.latest.title)")
                    Text(habit.latest.title).font(.bt(size: 12)); Spacer()
                    Text(habit.latest.schedule.once.map { dateText($0, engine: store.engine) } ?? "").font(.bt(size: 11, design: .monospaced)).foregroundStyle(Ink.muted)
                    Button { editor = .habit(habit, nil) } label: { Image(systemName: "ellipsis") }.buttonStyle(.plain)
                }.padding(.vertical, 7)
                Line()
            }
        }
    }
}
struct MenuBarPanel: View {
    @ObservedObject var store: TrackerStore
    var isModal = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var avatarError: String?
    @State private var showAll = false
    @State private var loggedUrgeID: UUID?
    @AppStorage("ascend.menuClock") private var showClock = true
    private var score: Score { store.engine.score(on: store.today) }
    private var rest: Bool { store.document.restDays.contains(store.today) }
    private var tasks: [Habit] { store.engine.due(on: store.today, includeMilestones: true).filter { showAll || !store.engine.completed($0, on: store.today) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ASCEND ↗").font(.bt(size: 13, weight: .semibold)).tracking(3)
                Spacer()
                Menu {
                    Button("Daily check-in") { open("DailyCheckIn") }
                    Button("Log caffeine") { open("Caffeine") }
                    Button("Patterns") { open("Patterns") }
                    Divider()
                    Button("Daily routine") { open("Routine") }
                    Button("Urge history") { open("Urges") }
                    Button("Ask Ascend") { open("Assistant") }
                    Toggle("Show routine clock", isOn: $showClock)
                    Button("Reminders & settings") { open("Settings") }
                    Divider()
                    Button("Export backup…") { store.exportBackup() }
                    Button("Quit Ascend") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Quick menu")
                if isModal { Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Close quick check-in").keyboardShortcut(.cancelAction) }
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(dateText(store.today, engine: store.engine, pattern: "EEEE, d MMM"))
                    Text(rest ? "Rest day." : score.percentLabel).font(.bt(size: 34, weight: .medium)).tracking(-1.3)
                    Text(rest ? "Recovery counts, too." : "\(score.completed) of \(score.scheduled) check-ins").font(.bt(size: 12)).foregroundStyle(Ink.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if showClock {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in RoutineDial(store: store, now: timeline.date, compact: true) }.frame(width: 94, height: 100)
                } else {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in RoutineDial(store: store, now: timeline.date, compact: true) }
                        .frame(width: 94, height: 100).clipped()
                }
            }.padding(.leading, 16).background(Ink.panel, in: RoundedRectangle(cornerRadius: 10))
            ProgressTrack(ratio: score.ratio ?? 0, target: store.document.cycle.target)
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                Button { open(store.document.routine.configured ? "Routine" : "RoutineSettings") } label: {
                    HStack {
                        if let next = store.engine.nextRoutineEvent(after: timeline.date) { Text("Next · \(next.title)").lineLimit(1); Spacer(); Text("\(timeText(next.date, engine: store.engine))\(store.engine.key(next.date) == store.today ? "" : " tomorrow")").monospacedDigit() }
                        else { Text("Set your routine clock"); Spacer(); Text("Example windows  ↗") }
                    }.font(.bt(size: 11)).foregroundStyle(Ink.muted)
                }.buttonStyle(.plain)
            }
            Button { loggedUrgeID = store.recordUrge() } label: { Label("Log an urge", systemImage: "circle.dotted").font(.bt(size: 12)).foregroundStyle(.white.opacity(0.9)).frame(maxWidth: .infinity).padding(.vertical, 9).background(Ink.panel, in: RoundedRectangle(cornerRadius: 7)) }.buttonStyle(.plain).accessibilityLabel("Log an urge")
            if let id = loggedUrgeID, store.document.urgeLogs.contains(where: { $0.id == id }) {
                HStack {
                    Text("Time saved").foregroundStyle(Ink.muted)
                    Button("Details") { store.pendingUrge = id; open(nil) }
                    Spacer(); Button("Undo") { store.undoProgressAction(); loggedUrgeID = nil }.disabled(store.undoLabel != "urge log" || store.lastUrgeID != id)
                }.font(.bt(size: 11)).buttonStyle(.borderless)
            }
            HStack {
                Picker("Task view", selection: $showAll) { Text("Remaining").tag(false); Text("All").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 180, height: 26)
                Spacer(); DayActions(store: store, day: store.today).labelStyle(.iconOnly)
            }.frame(height: 26)
            if rest { Text("Resume the day from Day options to check in.").font(.bt(size: 12)).foregroundStyle(Ink.muted) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(tasks) { habit in
                        HabitRow(store: store, habit: habit, day: store.today, onLog: {
                            store.pendingLog = habit.id; open(nil)
                        })
                    }
                    if tasks.isEmpty { Text(score.scheduled > 0 ? "All done. You showed up." : "No check-ins scheduled.").font(.bt(size: 12)).foregroundStyle(Ink.muted).padding(.vertical, 24) }
                }
            }.frame(height: min(250, max(65, CGFloat(tasks.count) * 61)))
            if let error = store.saveError { Text(error).font(.bt(size: 11)).foregroundStyle(.orange).lineLimit(3) }
            PrimaryButton(label: "Open your space  ↗", fullWidth: true) { open("Today") }
            HStack {
                Button { open("Goals") } label: { Label("Goals", systemImage: "scope") }
                Spacer()
                Button { open("Settings") } label: { Label("Reminders", systemImage: "bell") }
            }.buttonStyle(.plain).font(.bt(size: 11)).foregroundStyle(Ink.muted)
        }.padding(18).frame(width: 370).background(Ink.background).tint(Ink.accent).onAppear { store.refreshDay() }.onDisappear { loggedUrgeID = nil }
    }
    private func open(_ destination:String?){
        if let destination{store.pendingScreen=destination}
        if isModal {dismiss();return}
        DispatchQueue.main.async{openWindow(id:"main");NSApp.activate(ignoringOtherApps:true)}
    }
}
