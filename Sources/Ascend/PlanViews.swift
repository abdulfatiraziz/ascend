import SwiftUI
import AppKit
import AscendCore

struct GoalsView: View {
    @ObservedObject var store: TrackerStore
    @Binding var editor: Editor?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Kicker("Goals / recurring habits / milestones"); Spacer(); Button("+ Goal") { editor = .goal(nil) }; Button("+ Habit or task") { editor = .habit(nil, nil) } }.font(.system(size: 12))
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(store.document.goals) { goal in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack { Image(systemName: goal.symbol).foregroundStyle(Ink.accent); Spacer(); Button { editor = .goal(goal) } label: { Image(systemName: "square.and.pencil") }.buttonStyle(.plain).foregroundStyle(Ink.muted).help("Edit \(goal.title)") }
                            Text(goal.title).font(.system(size: 18, weight: .medium)).tracking(-0.4).lineLimit(1).help(goal.title)
                            HStack { Kicker(dateText(goal.latest.start, engine: store.engine)); Text("→").foregroundStyle(Ink.muted); Kicker(dateText(goal.latest.end, engine: store.engine)) }
                            Line()
                            ForEach(store.document.habits.filter { $0.goalID == goal.id && $0.archivedDay == nil }) { habit in
                                Button { editor = .habit(habit, nil) } label: {
                                    HStack(alignment: .top) {
                                        Image(systemName: habit.kind == .milestone ? "calendar" : habit.kind == .metric ? "number" : "circle").frame(width: 16).foregroundStyle(Ink.accent)
                                        VStack(alignment: .leading, spacing: 3) { Text(habit.latest.title).font(.system(size: 12)); Text(habit.latest.schedule.label).font(.system(size: 10)).foregroundStyle(Ink.muted) }
                                        Spacer(); Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Ink.muted)
                                    }
                                }.buttonStyle(.plain)
                            }
                            Button("+ Add to this goal") { editor = .habit(nil, goal.id) }.buttonStyle(.borderless).font(.system(size: 11))
                        }.frame(maxWidth: .infinity, alignment: .topLeading).panel()
                    }
                }
                milestones.padding(.top, 24)
            }
        }
    }
    private var milestones: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker("One-off milestones / separate from habit score")
            ForEach(store.document.habits.filter { $0.kind == .milestone && $0.archivedDay == nil }.sorted { ($0.latest.schedule.once ?? "") < ($1.latest.schedule.once ?? "") }) { habit in
                HStack {
                    Button { store.completeMilestone(habit) } label: { Image(systemName: store.engine.milestoneCompleted(habit) ? "checkmark.circle.fill" : "circle").foregroundStyle(store.engine.milestoneCompleted(habit) ? Ink.accent : Ink.muted) }.buttonStyle(.plain).accessibilityLabel("Complete \(habit.latest.title)")
                    Text(habit.latest.title).font(.system(size: 12)); Spacer()
                    Text(habit.latest.schedule.once.map { dateText($0, engine: store.engine) } ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(Ink.muted)
                    Button { editor = .habit(habit, nil) } label: { Image(systemName: "ellipsis") }.buttonStyle(.plain)
                }.padding(.vertical, 7)
                Line()
            }
        }
    }
}
struct CycleView: View {
    @ObservedObject var store: TrackerStore
    @State private var selectedWeek = 0
    private var weeks: [[String]] {
        let days = store.engine.days(from: store.document.cycle.start, through: store.document.cycle.end)
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }
    private var closed: Score { store.engine.closedScore(today: store.today) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 10) {
                        Kicker("Consistency / closed days")
                        Text(closed.percentLabel).font(.system(size: 70, weight: .regular)).tracking(-4)
                        Text(closed.scheduled == 0 ? "No closed days yet. Your first review starts tomorrow." : "\(closed.completed) of \(closed.scheduled) scheduled check-ins completed.").font(.system(size: 12)).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 9) { Text("Consistency, over perfection.").font(.system(size: 17, weight: .medium)); Text("Aim for \(Int(store.document.cycle.target * 100))%. No streak resets.").font(.system(size: 12)).foregroundStyle(Ink.muted) }
                }.panel(padding: 26)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(weeks.indices, id: \.self) { index in
                        let range = weeks[index]
                        let score = store.engine.score(from: range.first!, through: min(range.last!, store.engine.adding(-1, to: store.today)))
                        Button { selectedWeek = index } label: {
                            VStack(spacing: 12) { Kicker("W\(String(format: "%02d", index + 1))"); Text(range.first! > store.today ? "—" : score.percentLabel).font(.system(size: 16, weight: .medium)) }
                                .frame(maxWidth: .infinity).padding(.vertical, 18).background(selectedWeek == index ? Ink.accent.opacity(0.12) : Ink.panel, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedWeek == index ? Ink.accent : Ink.line))
                        }.buttonStyle(.plain).disabled(range.first! > store.today)
                    }
                }
                if weeks.indices.contains(selectedWeek) {
                    let range = weeks[selectedWeek]
                    let score = store.engine.score(from: range.first!, through: min(range.last!, store.engine.adding(-1, to: store.today)))
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Week \(selectedWeek + 1) · \(dateText(range.first!, engine: store.engine, pattern: "d MMM")) – \(dateText(range.last!, engine: store.engine, pattern: "d MMM"))").font(.system(size: 16, weight: .medium))
                        ProgressTrack(ratio: score.ratio ?? 0, target: store.document.cycle.target)
                        Text(score.scheduled == 0 ? "No closed-day check-ins in this week yet." : "\(score.completed) of \(score.scheduled) check-ins · \(score.percentLabel)").font(.system(size: 12)).foregroundStyle(Ink.muted)
                    }
                }
                HStack(alignment: .top, spacing: 30) {
                    rule("01", "Daily habits", "Each scheduled check-in counts once. Unlogged past check-ins count as missed.")
                    rule("02", "Gym & rest days", "Only your selected training days count. Rest days stay out of the denominator.")
                    rule("03", "Milestones", "One-off tasks use due dates and stay separate from consistency.")
                }.padding(.top, 10)
                Text("Today’s open check-ins are shown in Today. Schedule edits apply from the edit date; earlier days keep their original rules.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            }
        }.onAppear { selectedWeek = max(0, min(weeks.count - 1, (max(1, store.engine.dayNumber(store.today)) - 1) / 7)) }
    }
    private func rule(_ number: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Kicker(number); Text(title).font(.system(size: 13, weight: .medium)); Text(text).font(.system(size: 12)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true) }.frame(maxWidth: .infinity, alignment: .leading)
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
                Text("ASCEND ↗").font(.system(size: 13, weight: .semibold)).tracking(3)
                Spacer()
                Menu {
                    Button("Daily check-in") { open("DailyCheckIn") }
                    Button("Log caffeine") { open("Caffeine") }
                    Button("Patterns") { open("Patterns") }
                    Divider()
                    Button("Calendar & history") { open("Calendar") }
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
                    Text(rest ? "Rest day." : score.percentLabel).font(.system(size: 34, weight: .medium)).tracking(-1.3)
                    Text(rest ? "Recovery counts, too." : "\(score.completed) of \(score.scheduled) check-ins").font(.system(size: 12)).foregroundStyle(Ink.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if showClock {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in RoutineDial(store: store, now: timeline.date, compact: true) }.frame(width: 94, height: 100)
                } else {
                    AvatarView(progress: score.ratio ?? 0, evolution: store.engine.evolution(today: store.today), finish: store.document.avatarFinish, compact: true, error: $avatarError)
                        .frame(width: 94, height: 100).clipped()
                }
            }.padding(.leading, 16).background(Ink.panel, in: RoundedRectangle(cornerRadius: 10))
            ProgressTrack(ratio: score.ratio ?? 0, target: store.document.cycle.target)
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                Button { open(store.document.routine.configured ? "Routine" : "RoutineSettings") } label: {
                    HStack {
                        if let next = store.engine.nextRoutineEvent(after: timeline.date) { Text("Next · \(next.title)").lineLimit(1); Spacer(); Text("\(timeText(next.date, engine: store.engine))\(store.engine.key(next.date) == store.today ? "" : " tomorrow")").monospacedDigit() }
                        else { Text("Set your routine clock"); Spacer(); Text("Example windows  ↗") }
                    }.font(.system(size: 11)).foregroundStyle(Ink.muted)
                }.buttonStyle(.plain)
            }
            Button { loggedUrgeID = store.recordUrge() } label: { Label("Log an urge", systemImage: "circle.dotted").font(.system(size: 12)).frame(maxWidth: .infinity).padding(.vertical, 9).background(Ink.panel, in: RoundedRectangle(cornerRadius: 7)) }.buttonStyle(.plain).accessibilityLabel("Log an urge")
            if let id = loggedUrgeID, store.document.urgeLogs.contains(where: { $0.id == id }) {
                HStack {
                    Text("Time saved").foregroundStyle(Ink.muted)
                    Button("Details") { open(nil); Task { @MainActor in try? await Task.sleep(for: .milliseconds(200)); store.pendingUrge = id } }
                    Spacer(); Button("Undo") { store.undoProgressAction(); loggedUrgeID = nil }.disabled(store.undoLabel != "urge log" || store.lastUrgeID != id)
                }.font(.system(size: 11)).buttonStyle(.borderless)
            }
            HStack {
                Picker("Task view", selection: $showAll) { Text("Remaining").tag(false); Text("All").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 180, height: 26)
                Spacer(); DayActions(store: store, day: store.today).labelStyle(.iconOnly)
            }.frame(height: 26)
            if rest { Text("Resume the day from Day options to check in.").font(.system(size: 12)).foregroundStyle(Ink.muted) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(tasks) { habit in
                        HabitRow(store: store, habit: habit, day: store.today, onLog: {
                            store.pendingLog = habit.id; open(nil)
                        })
                    }
                    if tasks.isEmpty { Text(score.scheduled > 0 ? "All done. You showed up." : "No check-ins scheduled.").font(.system(size: 12)).foregroundStyle(Ink.muted).padding(.vertical, 24) }
                }
            }.frame(height: min(165, max(65, CGFloat(tasks.count) * 61)))
            if let error = store.saveError { Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(3) }
            PrimaryButton(label: "Open your space  ↗", fullWidth: true) { open("Today") }
            HStack {
                Button { open("Calendar") } label: { Label("History", systemImage: "calendar") }
                Spacer()
                Button { open("Settings") } label: { Label("Reminders", systemImage: "bell") }
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Ink.muted)
        }.padding(18).frame(width: 370).background(Ink.background).tint(Ink.accent).onAppear { store.refreshDay() }.onDisappear { loggedUrgeID = nil }
    }
    private func open(_ destination: String?) {
        if isModal { dismiss() }
        openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
        // Let the quick sheet finish dismissing before presenting another editor.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            if let destination { store.pendingScreen = destination }
        }
    }
}
