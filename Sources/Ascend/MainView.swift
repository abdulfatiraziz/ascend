import SwiftUI
import AppKit
import AscendCore

enum Screen: String, CaseIterable {
    case today = "Today", chat = "Chat", goals = "Goals", routine = "Routine", meals = "Meals", meds = "Meds", notes = "Notes", photos = "Photos", screenTime = "Screen time", health = "Health", body = "Body", patterns = "Patterns", urges = "Urges", dossier = "Dossier"
    var symbol: String { switch self { case .today: "circle.hexagongrid"; case .chat: "sparkles"; case .goals: "scope"; case .routine: "clock"; case .meals: "fork.knife"; case .meds: "pills"; case .notes: "note.text"; case .photos: "person.crop.rectangle.stack"; case .screenTime: "hourglass"; case .health: "heart.text.square"; case .body: "figure.strengthtraining.traditional"; case .patterns: "point.3.connected.trianglepath.dotted"; case .urges: "circle.dotted"; case .dossier: "folder" } }
}
/// The four sidebar tabs. Every old screen lives inside one of them as a sub-tab; Chat opens from Ask Ascend.
enum Tab: String, CaseIterable {
    case brief = "Brief", condition = "Condition", fieldLog = "Field log", dossier = "Dossier"
    var screens: [Screen] {
        switch self {
        case .brief: [.goals, .today, .routine]
        case .condition: [.health, .body, .screenTime]
        case .fieldLog: [.meals, .meds, .urges, .notes]
        case .dossier: [.dossier]
        }
    }
    var symbol: String { switch self { case .brief: "doc.text"; case .condition: "waveform.path.ecg"; case .fieldLog: "square.and.pencil"; case .dossier: "folder" } }
    static func of(_ screen: Screen) -> Tab? { allCases.first { $0.screens.contains(screen) } }
}
extension Screen {
    /// Sub-tab label inside its tab.
    var subLabel: String { self == .today ? "Today" : rawValue }
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
    @State private var screen: Screen = ProcessInfo.processInfo.environment["ASCEND_DATA_DIR"] == nil ? .goals
        : Screen(rawValue: ProcessInfo.processInfo.environment["ASCEND_OPEN_SCREEN"] ?? "") ?? .goals
    @State private var selectedDay: String
    @State private var editor: Editor?
    @State private var sheetIsPresented=false
    @State private var queuedEditor:Editor?
    @State private var queuedDestination:String?
    @Environment(\.openWindow) private var openWindow
    @State private var eyesOnly = false
    /// The sub-tab each tab was last left on, so switching tabs comes back to the same place.
    @State private var lastScreen: [Tab: Screen] = [:]
    init(store: TrackerStore) { self.store = store; _selectedDay = State(initialValue: store.today); let env = ProcessInfo.processInfo.environment; _eyesOnly = State(initialValue: env["ASCEND_DATA_DIR"] != nil && env["ASCEND_EYES_ONLY"] == "1") }
    /// Eyes only: seals the window behind the vault (⌘⇧E); Touch ID or the Mac password opens it.
    private func setEyesOnly(_ on: Bool) { eyesOnly = on }
    var body: some View {
        mainContent
            // No grey system scroll bars on the felt; scrolling still works with trackpad and wheel.
            .scrollIndicators(.never)
            .allowsHitTesting(!eyesOnly).accessibilityHidden(eyesOnly)
            .overlay { if eyesOnly { EyesOnlyCover { setEyesOnly(false) } } }
    }
    private var mainContent: some View {
        HStack(spacing: 0) {
            sidebar
            // The chat fills the whole content area, like a chat app; other screens keep the header and goals footer.
            if screen == .chat { ChatView(store: store, settings: { editor = .aiSettings }) } else {
            VStack(alignment: .leading, spacing: 22) {
                header
                subTabs
                if let error = store.saveError {
                    HStack { Image(systemName: "exclamationmark.triangle"); Text(error); Spacer(); Button("Settings") { editor = .settings } }
                        .font(.bt(size: 12)).padding(12).background(Ink.watch.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                if let label = store.undoLabel {
                    HStack { Label("Completed: \(label).", systemImage: "checkmark.circle"); Spacer(); if label == "urge log", let id = store.lastUrgeID { Button("Add details") { editor = .urge(id) } }; Button("Undo") { store.undoProgressAction() }; Text("Until next edit · this session").foregroundStyle(Ink.muted) }.font(.bt(size: 12)).padding(10).background(Ink.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                Group {
                    switch screen {
                    case .today: TodayView(store: store, lifestyle: store.lifestyle, day: $selectedDay, editor: $editor, open: { screen = $0 })
                    case .chat: EmptyView()
                    case .goals: GoalsView(store: store, editor: $editor)
                    case .routine: RoutineView(store: store, editor: $editor)
                    case .meals: MealsView(store: store)
                    case .meds: MedsView(store: store)
                    case .notes: NotesView(store: store)
                    case .photos: PhotosView(store: store)
                    case .screenTime: ConditionScreenTimeView(store: store)
                    case .health: HealthView(store: store)
                    case .body: BodyView(store:store)
                    case .patterns: PatternsView(store: store, editor: $editor)
                    case .urges: UrgesView(store: store, editor: $editor)
                    case .dossier: DossierView(store: store, lifestyle: store.lifestyle)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 20)
            }
        }
        .frame(minWidth: 980, minHeight: 720).background(Ink.background).foregroundStyle(Ink.ivory)
        .tint(Ink.accent)
        .sheet(item: $editor,onDismiss:editorDismissed) { item in
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
            }.preferredColorScheme(.dark).environment(\.calendar, store.engine.calendar).environment(\.timeZone, store.engine.calendar.timeZone).onAppear{sheetIsPresented=true}
        }
        .alert("Ascend", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) { Button("OK") { store.notice = nil } } message: { Text(store.notice ?? "") }
        .onChange(of: store.today) { old, new in if selectedDay == old { selectedDay = new } }
        .onChange(of: store.pendingLog, initial: true) { _, id in
            if let id, let habit = store.document.habits.first(where: { $0.id == id }) { present(.metric(habit, store.today)); store.pendingLog = nil }
        }
        .onChange(of: store.pendingUrge) { _, id in
            if let id { present(.urge(id)); store.pendingUrge = nil }
        }
        .onChange(of: store.pendingScreen) { _, value in
            guard let value else{return}
            store.pendingScreen=nil
            if sheetIsPresented || editor != nil {
                queuedDestination=value;queuedEditor=nil;editor=nil
            } else {navigate(value)}
        }
        .onReceive(NotificationCenter.default.publisher(for: .ascendNotificationOpened)) { _ in
            screen = .today; selectedDay = store.today; openWindow(id: "main")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshDay(); store.notifications.refresh(store.document)
        }
    }
    private func present(_ next:Editor){
        if sheetIsPresented || editor != nil {queuedEditor=next;queuedDestination=nil;editor=nil}
        else{editor=next}
    }
    private func editorDismissed(){
        sheetIsPresented=false
        if let destination=queuedDestination{queuedDestination=nil;navigate(destination)}
        else if let next=queuedEditor{queuedEditor=nil;editor=next}
    }
    private func navigate(_ value:String){
            if value == "Routine" { screen = .routine }
            if value == "Goals" { screen = .goals }
            if value == "Patterns" { screen = .health }
            if value == "DailyCheckIn" { editor = .observation(store.today) }
            if value == "Caffeine" { editor = .caffeine(nil, store.today) }
            if value == "Urges" { screen = .urges }
            if value == "Meds" { screen = .meds }
            if value == "Health" { screen = .health }
            if value == "Meals" { screen = .meals }
            if value == "Notes" { screen = .notes }
            if value == "ScreenTime" { screen = .screenTime }
            if value == "QuickCheckIn" { editor = .quick }
            if value == "Body" { screen = .body }
            if value == "Photos" { screen = .body }
            if value == "Dossier" { screen = .dossier }
            if value == "Assistant" { screen = .chat }
            if value == "AISettings" { editor = .aiSettings }
            if value == "RoutineSettings" { editor = .routine }
            // Old "Calendar" links: history now lives behind Today's date arrows.
            if value == "Calendar" { screen = .today; selectedDay = store.today }
            if value == "Settings" { editor = .settings }
            if value == "Today" { screen = .today; selectedDay = store.today }
    }
    private var sidebar: some View {
        VStack(spacing: 12) {
            Text("A↗").font(.bt(size: 26, weight: .bold)).tracking(-3).foregroundStyle(.white)
            // Thirteen screens don't fit a short window; the list scrolls instead of clipping.
            VStack(spacing: 6) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    let on = Tab.of(screen) == tab
                    Button { open(tab) } label: {
                        VStack(spacing: 5) { Image(systemName: tab.symbol).font(.bt(size: 18)); Text(tab.rawValue).font(.bt(size: 10.5)) }
                            .frame(width: 64, height: 56).background(on ? Ink.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .leading) { if on { Capsule().fill(Ink.accent).frame(width: 2, height: 22).offset(x: -7) } }
                    }.buttonStyle(.plain).foregroundStyle(on ? Ink.accent : Ink.muted).accessibilityLabel(tab.rawValue)
                    .keyboardShortcut(KeyEquivalent(Character(String(Tab.allCases.firstIndex(of: tab)! + 1))), modifiers: .command)
                    .help("\(tab.rawValue) · ⌘\(Tab.allCases.firstIndex(of: tab)! + 1)")
                }
            }
            Spacer(minLength: 0)
            Button { editor = .settings } label: { Image(systemName: "slider.horizontal.3").font(.bt(size: 18)).frame(width: 44, height: 44) }.buttonStyle(.plain).foregroundStyle(Ink.muted).help("Settings, avatar finish and backups")
            VStack(spacing: 8) { Circle().fill(Ink.muted).frame(width: 4, height: 4); Kicker("Local") }
        }.padding(.top, 26).padding(.bottom, 18).frame(width: 78).frame(maxHeight: .infinity).overlay(alignment: .trailing) { Rectangle().fill(Ink.line).frame(width: 1) }
    }
    private func open(_ tab: Tab) {
        if Tab.of(screen) == tab, screen != tab.screens[0] { screen = tab.screens[0] } else { screen = lastScreen[tab] ?? tab.screens[0] }
        if screen == .today { selectedDay = store.today }
    }
    /// Sub-tabs for the current tab (hidden when the tab has one screen).
    @ViewBuilder private var subTabs: some View {
        if let tab = Tab.of(screen), tab.screens.count > 1 {
            HStack(spacing: 4) {
                ForEach(tab.screens, id: \.self) { item in
                    let on = item == screen
                    Button { screen = item; if item == .today { selectedDay = store.today } } label: {
                        Label(item.subLabel, systemImage: item.symbol).font(.bt(size: 12, weight: on ? .semibold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(on ? Ink.accent.opacity(0.14) : .clear, in: Capsule())
                            .overlay(Capsule().stroke(on ? Ink.accent.opacity(0.5) : Ink.line))
                    }.buttonStyle(.plain).foregroundStyle(on ? Ink.lamp : Ink.muted)
                }
                Spacer()
            }
            .onChange(of: screen, initial: true) { _, new in if let t = Tab.of(new) { lastScreen[t] = new } }
        }
    }
    /// The line above the title: what this page is.
    private var kicker: String {
        switch screen {
        case .health:
            let f = DateFormatter(); f.dateFormat = "EEEE d MMM · h:mm a"
            return "Condition report · " + f.string(from: Date())
        case .body:
            let a = store.missions.missions.first { $0.id == "A" }
            return a.map { "Mission A · \($0.codename)" } ?? "Mission A"
        case .screenTime: return "Your attention"
        default: return "Your next version starts here"
        }
    }
    private var header: some View {
        // Title and countdown share one baseline, with matching kickers above them.
        HStack(alignment: .lastTextBaseline, spacing: 28) {
            VStack(alignment: .leading, spacing: 7) {
                Kicker(kicker)
                Text(screen == .today ? "The Brief." : screen == .goals ? "The blueprint." : screen == .routine ? "Find your rhythm." : screen == .patterns ? "Connect the dots." : screen == .meals ? "Eat with intent." : screen == .meds ? "Take it as prescribed." : screen == .notes ? "Remember what matters." : screen == .photos ? "See the change." : screen == .screenTime ? "Own your attention." : screen == .body ? "Build strength. See change." : screen == .health ? "Know your rhythm." : screen == .urges ? "Notice the pattern." : screen == .dossier ? "The Dossier." : "The long game.")
                    .font(.bt(size: 36, weight: .semibold)).tracking(-1.5).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer()
            Button { setEyesOnly(true) } label: { Label("Eyes only", systemImage: "eye.slash").font(.bt(size: 11)).padding(8) }
                .buttonStyle(.plain).background(Ink.panel, in: RoundedRectangle(cornerRadius: 7)).keyboardShortcut("e", modifiers: [.command, .shift]).help("Eyes only · ⌘⇧E · hides everything until you open it again")
            if let next = store.missions.missions.filter({ $0.due >= store.today }).min(by: { $0.due < $1.due }) {
                let left = store.engine.days(from: store.today, through: next.due).count - 1
                VStack(alignment: .trailing, spacing: 7) {
                    Kicker("Mission \(next.id) · \(next.codename) · \(dateText(next.due, engine: store.engine))").lineLimit(1)
                    Text("\(left) days").font(.bt(size: 36, weight: .medium)).tracking(-1)
                }.help("The next mission deadline: \(next.title)")
            }
        }
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
            HStack { Label("YOUR AVATAR", systemImage: "circle.fill").font(.bt(size: 10, design: .monospaced)).foregroundStyle(Ink.accent); Spacer(); Kicker(stage.rawValue) }.padding(.horizontal, 20).padding(.top, 18)
            ZStack(alignment: .bottom) {
                AvatarView(progress: score.ratio ?? 0, evolution: evolution, finish: store.document.avatarFinish, previewStage: stagePreview, error: $avatarError).id(reloadID)
                if let avatarError {
                    HStack { Text(avatarError).font(.bt(size: 11)).lineLimit(2); Button("Retry") { self.avatarError = nil; reloadID = UUID() } }.padding(10).background(Ink.panel).padding(10)
                }
            }.frame(minHeight: 220, maxHeight: .infinity)
            HStack(spacing: 5) {
                ForEach(AvatarStage.allCases) { item in
                    Button { stagePreview = stagePreview == item ? nil : item } label: {
                        HStack(spacing: 5) { Text(String(format: "%02d", item.ordinal)).opacity(0.55); Text(item.rawValue) }
                            .font(.bt(size: 10, weight: stage == item ? .semibold : .regular))
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
                            Text(score.percentLabel).font(.bt(size: 36, weight: .medium)).tracking(-1.5)
                            Text("\(score.completed) of \(score.scheduled)").font(.bt(size: 11)).foregroundStyle(Ink.muted)
                        }
                    }
                    Spacer()
                    Button { stagePreview = stagePreview == nil ? .ascendant : nil } label: { Label(stagePreview != nil ? "Live form" : "Final form", systemImage: "sparkles").font(.bt(size: 11)).padding(9) }
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
                } label: { Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.bt(size: 19)).foregroundStyle(done ? Ink.accent : Ink.muted) }
                    .buttonStyle(.plain).accessibilityLabel("\(done ? "Reopen" : "Complete") \(revision.title)")
                VStack(alignment: .leading, spacing: 4) {
                    Text(revision.title).font(.bt(size: 12)).foregroundStyle(done ? Ink.muted : .white)
                    Text(subtitle).font(.bt(size: 10)).foregroundStyle(Ink.muted).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if habit.kind == .metric {
                    let entry = store.engine.entry(for: habit, day: day)
                    Button { onLog() } label: { Text(entry?.value.map { "\($0.pretty) \(revision.target?.unit ?? "")" } ?? "Log").lineLimit(1).truncationMode(.middle).frame(maxWidth: entry?.value == nil ? nil : 120).font(.bt(size: 11, design: .monospaced)).padding(.horizontal, 8).padding(.vertical, 6).background(Ink.panel, in: RoundedRectangle(cornerRadius: 5)) }.buttonStyle(.plain).accessibilityLabel("Log \(revision.title)")
                }
                if let onEdit { Button(action: onEdit) { Image(systemName: "ellipsis").font(.bt(size: 12)).frame(width: 18, height: 25) }.buttonStyle(.plain).foregroundStyle(Ink.muted).help("Edit \(revision.title)") }
            }.padding(.vertical, 13)
                .disabled(day > store.today || (store.document.restDays.contains(day) && habit.kind != .milestone))
            Line()
        }
    }
    private var subtitle: String {
        let label = store.engine.target(for: habit, on: day)?.label ?? (revision.note.isEmpty ? revision.schedule.label : revision.note)
        let goal = store.document.goals.first { $0.id == habit.goalID }?.title ?? ""
        if let auto = store.document.autoTickSource(habit, day: day) { return "Auto · \(auto) · \(goal)" }
        return "\(label) · \(goal)"
    }
}

/// One button per medicine moment: a tap logs every dose in it. Hover lists the medicines.
struct MedMomentsStrip: View {
    @ObservedObject var store: TrackerStore
    let day: String
    var large = false
    var body: some View {
        let groups = store.document.meds.moments(on: day, engine: store.engine)
        let now = store.engine.calendar.component(.hour, from: Date()) * 60 + store.engine.calendar.component(.minute, from: Date())
        if !groups.isEmpty {
            HStack(spacing: large ? 10 : 8) {
                ForEach(groups) { g in
                    let due = !g.allTaken && day == store.today && now >= g.minute
                    Button { store.setMoment(g.moment, day: day, taken: !g.allTaken, source: "mac") } label: {
                        HStack(alignment: .top, spacing: 7) {
                            if !large { Image(systemName: g.allTaken ? "checkmark.circle.fill" : "pills").font(.bt(size: 11)) }
                            VStack(alignment: .leading, spacing: large ? 4 : 1) {
                                HStack {
                                    Text(g.moment.rawValue).font(.bt(size: large ? 14 : 11, weight: .medium))
                                    if large && g.allTaken { Spacer(); Image(systemName: "checkmark").font(.bt(size: 12)) }
                                }
                                Text(status(g, due: due)).font(.bt(size: large ? 10 : 9, design: .monospaced))
                                    .foregroundStyle(g.allTaken ? Ink.onTrack : due ? Ink.accent : Ink.muted)
                                if large { Text(g.shortNames).font(.bt(size: 11)).foregroundStyle(Ink.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(g.allTaken ? Ink.onTrack : Ink.ivory)
                        .padding(.horizontal, large ? 13 : 10).padding(.vertical, large ? 11 : 7).frame(maxWidth: .infinity, alignment: .leading)
                        .background(g.allTaken ? Ink.onTrack.opacity(0.10) : Ink.panel2, in: RoundedRectangle(cornerRadius: large ? 11 : 8))
                        .overlay(RoundedRectangle(cornerRadius: large ? 11 : 8).stroke(g.allTaken ? Ink.onTrack.opacity(0.35) : due ? Ink.goldDim : Ink.line))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(day > store.today)
                    .help(g.names + (g.allTaken ? " · click to undo" : " · click when taken"))
                    .accessibilityLabel("\(g.moment.rawValue) medicines, \(g.taken) of \(g.slots.count) taken")
                }
            }
        }
    }
    private func status(_ g: MedMomentGroup, due: Bool) -> String {
        if g.allTaken {
            let first = g.slots.compactMap(\.taken).map(\.takenAt).min()
            return first.map { "TAKEN \(clock12($0))" } ?? "TAKEN"
        }
        return "\(due ? "DUE " : "")\(HealthReport.clock(g.minute).uppercased()) · \(g.taken)/\(g.slots.count)"
    }
    private func clock12(_ t: Double) -> String {
        let c = store.engine.calendar, d = Date(timeIntervalSince1970: t)
        return HealthReport.clock(c.component(.hour, from: d) * 60 + c.component(.minute, from: d)).uppercased()
    }
}
