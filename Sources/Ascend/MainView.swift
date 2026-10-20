import SwiftUI
import AppKit
import AscendCore

enum Screen: String, CaseIterable {
    case today = "Today", goals = "Goals", routine = "Routine", meals = "Meals", meds = "Meds", notes = "Notes", health = "Health", patterns = "Patterns", urges = "Urges", calendar = "Calendar", cycle = "Cycle"
    var symbol: String { switch self { case .today: "circle.hexagongrid"; case .goals: "scope"; case .routine: "clock"; case .meals: "fork.knife"; case .meds: "pills"; case .notes: "note.text"; case .health: "heart.text.square"; case .patterns: "point.3.connected.trianglepath.dotted"; case .urges: "circle.dotted"; case .calendar: "calendar"; case .cycle: "chart.bar.xaxis" } }
}
enum Editor: Identifiable {
    case goal(Goal?), habit(Habit?, UUID?), metric(Habit, String), urge(UUID), observation(String), caffeine(CaffeineEntry?, String), routine, aiSettings, settings, quick
    var id: String {
        switch self {
        case .goal(let g): return "goal-\(g?.id.uuidString ?? "new")"
        case .habit(let h, _): return "habit-\(h?.id.uuidString ?? "new")"
        case .metric(let h, let d): return "metric-\(h.id)-\(d)"
        case .urge(let id): return "urge-\(id)"
        case .observation(let day): return "observation-\(day)"
        case .caffeine(let entry, let day): return "caffeine-\(entry?.id.uuidString ?? day)"
        case .routine: return "routine"
        case .aiSettings: return "ai-settings"
        case .settings: return "settings"
        case .quick: return "quick"
        }
    }
}
struct MainView: View {
    @ObservedObject var store: TrackerStore
    // Isolated QA runs (ASCEND_DATA_DIR) can open on a given screen with ASCEND_OPEN_SCREEN, e.g. "Meds".
    @State private var screen: Screen = ProcessInfo.processInfo.environment["ASCEND_DATA_DIR"] == nil ? .today
        : Screen(rawValue: ProcessInfo.processInfo.environment["ASCEND_OPEN_SCREEN"] ?? "") ?? .today
    @State private var selectedDay: String
    @State private var editor: Editor?
    @State private var showAssistant = false
    @Environment(\.openWindow) private var openWindow
    init(store: TrackerStore) { self.store = store; _selectedDay = State(initialValue: store.today) }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 22) {
                header
                if let error = store.saveError {
                    HStack { Image(systemName: "exclamationmark.triangle"); Text(error); Spacer(); Button("Settings") { editor = .settings } }
                        .font(.system(size: 12)).padding(12).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                if let label = store.undoLabel {
                    HStack { Label("Completed: \(label).", systemImage: "checkmark.circle"); Spacer(); if label == "urge log", let id = store.lastUrgeID { Button("Add details") { editor = .urge(id) } }; Button("Undo") { store.undoProgressAction() }; Text("Until next edit · this session").foregroundStyle(Ink.muted) }.font(.system(size: 12)).padding(10).background(Ink.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                Group {
                    switch screen {
                    case .today: TodayView(store: store, day: $selectedDay, editor: $editor)
                    case .goals: GoalsView(store: store, editor: $editor)
                    case .routine: RoutineView(store: store, editor: $editor)
                    case .meals: MealsView(store: store)
                    case .meds: MedsView(store: store)
                    case .notes: NotesView(store: store)
                    case .health: HealthView(store: store)
                    case .patterns: PatternsView(store: store, editor: $editor)
                    case .urges: UrgesView(store: store, editor: $editor)
                    case .calendar: CalendarView(store: store, day: $selectedDay, editor: $editor)
                    case .cycle: CycleView(store: store)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                footer
            }.padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 20)
        }
        .frame(minWidth: 980, minHeight: 720).background(Ink.background).foregroundStyle(.white)
        .tint(Ink.accent)
        .overlay(alignment: .trailing) {
            if showAssistant { AssistantPanel(store: store, controller: store.assistant, close: { showAssistant = false }, settings: { editor = .aiSettings }).shadow(color: .black.opacity(0.35), radius: 18, x: -7) }
        }
        .sheet(item: $editor) { item in
            Group {
                switch item {
                case .goal(let goal): GoalEditor(store: store, goal: goal)
                case .habit(let habit, let goalID): HabitEditor(store: store, habit: habit, goalID: goalID)
                case .metric(let habit, let day): MetricEditor(store: store, habit: habit, day: day)
                case .urge(let id): UrgeEditor(store: store, id: id)
                case .observation(let day): DailyObservationEditor(store: store, day: day)
                case .caffeine(let entry, let day): CaffeineEditor(store: store, entry: entry, day: day)
                case .routine: RoutineEditor(store: store)
                case .aiSettings: ClaudeSettingsEditor(store: store)
                case .settings: SettingsEditor(store: store)
                case .quick: MenuBarPanel(store: store, isModal: true)
                }
            }.preferredColorScheme(.dark).environment(\.calendar, store.engine.calendar).environment(\.timeZone, store.engine.calendar.timeZone)
        }
        .alert("Ascend", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) { Button("OK") { store.notice = nil } } message: { Text(store.notice ?? "") }
        .onChange(of: store.today) { old, new in if selectedDay == old { selectedDay = new } }
        .onChange(of: store.pendingLog, initial: true) { _, id in
            if let id, let habit = store.document.habits.first(where: { $0.id == id }) { editor = .metric(habit, store.today); store.pendingLog = nil }
        }
        .onChange(of: store.pendingUrge) { _, id in
            if let id { editor = .urge(id); store.pendingUrge = nil }
        }
        .onChange(of: store.pendingScreen) { _, value in
            if value == "Routine" { screen = .routine }
            if value == "Patterns" { screen = .patterns }
            if value == "DailyCheckIn" { editor = .observation(store.today) }
            if value == "Caffeine" { editor = .caffeine(nil, store.today) }
            if value == "Urges" { screen = .urges }
            if value == "Meds" { screen = .meds }
            if value == "Notes" { screen = .notes }
            if value == "Assistant" { showAssistant = true }
            if value == "AISettings" { editor = .aiSettings }
            if value == "RoutineSettings" { editor = .routine }
            if value == "Calendar" { screen = .calendar; selectedDay = store.today }
            if value == "Settings" { editor = .settings }
            if value == "Today" { screen = .today; selectedDay = store.today }
            store.pendingScreen = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .ascendNotificationOpened)) { _ in
            screen = .today; selectedDay = store.today; openWindow(id: "main")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshDay(); store.notifications.refresh(store.document)
        }
    }
    private var sidebar: some View {
        VStack(spacing: 18) {
            Text("A↗").font(.system(size: 26, weight: .bold)).tracking(-3).foregroundStyle(.white)
            VStack(spacing: 6) {
                ForEach(Screen.allCases, id: \.self) { item in
                    Button { screen = item; if item == .today { selectedDay = store.today } } label: {
                        VStack(spacing: 6) { Image(systemName: item.symbol).font(.system(size: 18)); Text(item.rawValue).font(.system(size: 10)) }
                            .frame(width: 58, height: 52).background(screen == item ? Ink.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).foregroundStyle(screen == item ? Ink.accent : Ink.muted).accessibilityLabel(item.rawValue)
                }
            }
            Spacer()
            Button { editor = .settings } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 18)).frame(width: 44, height: 44) }.buttonStyle(.plain).foregroundStyle(Ink.muted).help("Settings, avatar finish and backups")
            VStack(spacing: 8) { Circle().fill(Ink.muted).frame(width: 4, height: 4); Kicker("Local") }
        }.padding(.top, 26).padding(.bottom, 18).frame(width: 78).frame(maxHeight: .infinity).overlay(alignment: .trailing) { Rectangle().fill(Ink.line).frame(width: 1) }
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Kicker("Your next version starts here")
                Text(screen == .today ? "Build yourself." : screen == .goals ? "The blueprint." : screen == .calendar ? "Every day counts." : screen == .routine ? "Find your rhythm." : screen == .patterns ? "Connect the dots." : screen == .meals ? "Eat with intent." : screen == .meds ? "Take it as prescribed." : screen == .notes ? "Remember what matters." : screen == .health ? "Know your rhythm." : screen == .urges ? "Notice the pattern." : "The long game.")
                    .font(.system(size: 36, weight: .semibold)).tracking(-1.5).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer()
            Button { editor = .quick } label: { Label("Quick check-in", systemImage: "menubar.rectangle").font(.system(size: 11)).padding(8) }
                .buttonStyle(.plain).background(Ink.panel, in: RoundedRectangle(cornerRadius: 7)).keyboardShortcut("k", modifiers: [.command, .shift])
            Button { store.recordUrge() } label: { Label("Urge", systemImage: "circle.dotted").font(.system(size: 11)).padding(8) }.buttonStyle(.plain).background(Ink.panel, in: RoundedRectangle(cornerRadius: 7)).accessibilityLabel("Log an urge").keyboardShortcut("u", modifiers: [.command, .shift]).help("Log an urge · ⌘⇧U · time saved immediately")
            Button { showAssistant.toggle() } label: { Label("Ask Ascend", systemImage: "sparkles").font(.system(size: 11)).padding(8) }.buttonStyle(.plain).background(showAssistant ? Ink.accent.opacity(0.18) : Ink.panel, in: RoundedRectangle(cornerRadius: 7)).keyboardShortcut("j", modifiers: [.command])
            VStack(alignment: .trailing, spacing: 6) {
                Kicker(store.document.cycle.title).lineLimit(1).help(store.document.cycle.title)
                Text("Day \(store.engine.dayNumber(store.today)) / \(store.engine.days(from: store.document.cycle.start, through: store.document.cycle.end).count)").font(.system(size: 18, weight: .medium))
                Text("\(dateText(store.document.cycle.start, engine: store.engine, pattern: "d MMM")) — \(dateText(store.document.cycle.end, engine: store.engine))").font(.system(size: 11, design: .monospaced)).foregroundStyle(Ink.muted)
            }
        }
    }
    private var footer: some View {
        VStack(spacing: 17) {
            Line()
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 5) { Kicker("Your goals"); Text("One version of you.").font(.system(size: 11)).foregroundStyle(Ink.muted) }.frame(width: 140, alignment: .leading)
                ForEach(store.document.goals.prefix(4)) { goal in
                    let score = store.engine.score(on: store.today, goalID: goal.id)
                    Button { editor = .goal(goal) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(score.completed) OF \(score.scheduled) TODAY").font(.system(size: 10, design: .monospaced)).foregroundStyle(Ink.muted)
                            HStack { Text(goal.title).font(.system(size: 12)).lineLimit(1); Text("↗").foregroundStyle(Ink.accent) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
struct TodayView: View {
    @ObservedObject var store: TrackerStore
    @Binding var day: String
    @Binding var editor: Editor?
    @State private var filter = "Remaining"
    let filters = ["Remaining", "Morning", "Daytime", "Evening", "All"]
    private var score: Score { store.engine.score(on: day) }
    private var tasks: [Habit] {
        store.engine.due(on: day, includeMilestones: true).filter { habit in
            if filter == "Remaining" { return !store.engine.completed(habit, on: day) }
            if filter == "All" { return true }
            return habit.revision(on: day)?.period.rawValue == filter
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            AvatarHero(store: store, score: score).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 15) {
                datePicker
                HStack {
                    Text(day == store.today ? "Today’s protocol" : "Day’s protocol").font(.system(size: 22, weight: .medium)).tracking(-0.6)
                    Spacer()
                    Text("\(score.completed) / \(score.scheduled)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Ink.accent)
                }
                if store.document.restDays.contains(day) {
                    Label("Rest day · check-ins preserved, excluded from score", systemImage: "moon.stars").font(.system(size: 12)).foregroundStyle(Ink.accent)
                }
                Text(targetText).font(.system(size: 12)).foregroundStyle(Ink.muted)
                HStack(spacing: 11) {
                    ForEach(filters, id: \.self) { label in
                        Button { filter = label } label: { Text(label).font(.system(size: 11)).padding(.bottom, 8).overlay(alignment: .bottom) { if filter == label { Rectangle().fill(Ink.accent).frame(height: 2) } } }
                            .buttonStyle(.plain).foregroundStyle(filter == label ? .white : Ink.muted)
                    }
                }.padding(.top, 5)
                Line()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tasks) { habit in
                            HabitRow(store: store, habit: habit, day: day, onLog: { editor = .metric(habit, day) }, onEdit: { editor = .habit(habit, nil) })
                        }
                        if tasks.isEmpty { emptyState.padding(.vertical, 50) }
                    }
                }.frame(maxHeight: .infinity)
                HStack {
                    Label("Private. Offline. Yours.", systemImage: "lock.shield").font(.system(size: 11)).foregroundStyle(Ink.muted)
                    Spacer()
                    Button { editor = .habit(nil, nil) } label: { Label("Habit", systemImage: "plus") }.buttonStyle(.borderless).font(.system(size: 11))
                }
            }.frame(maxWidth: .infinity).padding(.top, 3)
        }
    }
    private var targetText: String {
        if store.document.restDays.contains(day) { return "Use Day options to resume this day before editing recurring tasks." }
        if score.scheduled == 0 { return "No recurring check-ins scheduled for this date." }
        let left = score.remaining(target: store.document.cycle.target)
        return left > 0 ? "\(left) more to hit your \(Int(store.document.cycle.target * 100))% target." : "Target reached. Keep building."
    }
    private var datePicker: some View {
        HStack(spacing: 9) {
            Button { day = store.engine.adding(-1, to: day) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).help("Previous day")
            DatePicker("Check-in date", selection: Binding(get: { store.engine.date(day) ?? Date() }, set: { day = store.engine.key($0) }), in: ...Date(), displayedComponents: .date).labelsHidden().datePickerStyle(.compact).frame(maxWidth: 170)
            Button { day = store.engine.adding(1, to: day) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).disabled(day >= store.today).help("Next day")
            Spacer()
            DayActions(store: store, day: day)
            if day != store.today { Button("Today") { day = store.today }.font(.system(size: 11)).buttonStyle(.borderless) }
        }.foregroundStyle(Ink.muted)
    }
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: score.scheduled > 0 && score.completed == score.scheduled ? "checkmark.seal" : "moon.stars").font(.system(size: 28)).foregroundStyle(Ink.accent)
            Text(score.scheduled > 0 && score.completed == score.scheduled ? "Protocol complete." : "Nothing here for this view.").font(.system(size: 14, weight: .medium))
            Text(filter == "Remaining" ? "Choose All to review your check-ins." : "Your other habits are in the time-of-day tabs.").font(.system(size: 12)).foregroundStyle(Ink.muted)
        }.frame(maxWidth: .infinity)
    }
}
struct AvatarHero: View {
    @ObservedObject var store: TrackerStore
    let score: Score
    @State private var stagePreview: AvatarStage?
    @State private var avatarError: String?
    @State private var reloadID = UUID()
    private var evolution: Double { store.engine.evolution(today: store.today) }
    private var stage: AvatarStage { .resolve(evolution: evolution, appearance: store.document.avatarFinish, preview: stagePreview) }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Label("YOUR AVATAR", systemImage: "circle.fill").font(.system(size: 10, design: .monospaced)).foregroundStyle(Ink.accent); Spacer(); Kicker(stage.rawValue) }.padding(.horizontal, 20).padding(.top, 18)
            ZStack(alignment: .bottom) {
                AvatarView(progress: score.ratio ?? 0, evolution: evolution, finish: store.document.avatarFinish, previewStage: stagePreview, error: $avatarError).id(reloadID)
                if let avatarError {
                    HStack { Text(avatarError).font(.system(size: 11)).lineLimit(2); Button("Retry") { self.avatarError = nil; reloadID = UUID() } }.padding(10).background(Ink.panel).padding(10)
                }
            }.frame(minHeight: 220, maxHeight: .infinity)
            HStack(spacing: 5) {
                ForEach(AvatarStage.allCases) { item in
                    Button { stagePreview = stagePreview == item ? nil : item } label: {
                        HStack(spacing: 5) { Text(String(format: "%02d", item.ordinal)).opacity(0.55); Text(item.rawValue) }
                            .font(.system(size: 10, weight: stage == item ? .semibold : .regular))
                            .padding(.vertical, 7).frame(maxWidth: .infinity)
                            .background(stage == item ? Ink.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(stage == item ? Ink.accent : Ink.muted)
                    }.buttonStyle(.plain).accessibilityLabel("Preview \(item.rawValue)")
                }
            }.padding(.horizontal, 20)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Kicker("Day’s progress")
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(score.percentLabel).font(.system(size: 36, weight: .medium)).tracking(-1.5)
                            Text("\(score.completed) of \(score.scheduled)").font(.system(size: 11)).foregroundStyle(Ink.muted)
                        }
                    }
                    Spacer()
                    Button { stagePreview = stagePreview == nil ? .ascendant : nil } label: { Label(stagePreview != nil ? "Live form" : "Final form", systemImage: "sparkles").font(.system(size: 11)).padding(9) }
                        .buttonStyle(.plain).background(stagePreview != nil ? Ink.accent.opacity(0.2) : Ink.panel, in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.line)).foregroundStyle(Ink.accent)
                }
                ProgressTrack(ratio: score.ratio ?? 0, target: store.document.cycle.target)
                HStack { Kicker(stagePreview != nil ? "Cosmetic preview" : store.document.avatarFinish == "Progress" ? "Live form" : "Fixed appearance"); Spacer(); Kicker("\(Int(store.document.cycle.target * 100))% is the mission") }
            }.padding(20)
        }
        .background(RadialGradient(colors: [Ink.accent.opacity(0.10), Ink.panel.opacity(0.5)], center: .center, startRadius: 10, endRadius: 300), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Ink.line))
    }
}
struct HabitRow: View {
    @ObservedObject var store: TrackerStore
    var habit: Habit
    var day: String
    var onLog: () -> Void
    var onEdit: (() -> Void)? = nil
    private var revision: HabitRevision { habit.revision(on: day) ?? habit.latest }
    private var done: Bool { store.engine.completed(habit, on: day) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Button {
                    if habit.kind == .metric { onLog() } else { store.toggle(habit, day: day) }
                } label: { Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 19)).foregroundStyle(done ? Ink.accent : Ink.muted) }
                    .buttonStyle(.plain).accessibilityLabel("\(done ? "Reopen" : "Complete") \(revision.title)")
                VStack(alignment: .leading, spacing: 4) {
                    Text(revision.title).font(.system(size: 12)).foregroundStyle(done ? Ink.muted : .white)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(Ink.muted).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if habit.kind == .metric {
                    let entry = store.engine.entry(for: habit, day: day)
                    Button { onLog() } label: { Text(entry?.value.map { "\($0.pretty) \(revision.target?.unit ?? "")" } ?? "Log").lineLimit(1).truncationMode(.middle).frame(maxWidth: entry?.value == nil ? nil : 120).font(.system(size: 11, design: .monospaced)).padding(.horizontal, 8).padding(.vertical, 6).background(Ink.panel, in: RoundedRectangle(cornerRadius: 5)) }.buttonStyle(.plain).accessibilityLabel("Log \(revision.title)")
                }
                if let onEdit { Button(action: onEdit) { Image(systemName: "ellipsis").font(.system(size: 12)).frame(width: 18, height: 25) }.buttonStyle(.plain).foregroundStyle(Ink.muted).help("Edit \(revision.title)") }
            }.padding(.vertical, 13)
                .disabled(day > store.today || (store.document.restDays.contains(day) && habit.kind != .milestone))
            Line()
        }
    }
    private var subtitle: String {
        let label = revision.target?.label ?? (revision.note.isEmpty ? revision.schedule.label : revision.note)
        let goal = store.document.goals.first { $0.id == habit.goalID }?.title ?? ""
        return "\(label) · \(goal)"
    }
}
