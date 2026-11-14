import SwiftUI
import AscendCore

/// Today: what needs you on the left, what Ascend fills itself on the right, missions as one strip.
struct TodayView: View {
    @ObservedObject var store: TrackerStore
    @ObservedObject var lifestyle: LifestyleStore
    @Binding var day: String
    @Binding var editor: Editor?
    var open: (Screen) -> Void
    private var engine: TrackerEngine { store.engine }
    /// The memo shows on the Brief on Sunday and Monday; it lives in the Dossier all week.
    private var memoDay: Bool { let w = engine.calendar.component(.weekday, from: Date()); return w == 1 || w == 2 }

    var body: some View {
        let f = BriefFacts(store: store, day: day)
        let weeks = WeekFacts(store: store)
        let status = weeks.status
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                lede(f)
                if status.level.rawValue > lifestyle.lifestyle.seenLevel {
                    LevelUpCard(level: status.level, reward: lifestyle.lifestyle.rewards[status.level.mark] ?? "Set one in the Dossier.") {
                        lifestyle.update { $0.seenLevel = status.level.rawValue }
                    }
                }
                if memoDay, day == store.today, let m = weeks.debriefMonday { DebriefCard(store: store, monday: m, memo: Debrief.compose(weeks.debriefWeek(m))) }
                HStack(alignment: .top, spacing: 22) {
                    TodayTapsCard(store: store, day: day, editor: $editor, open: open).frame(maxWidth: .infinity)
                    TodayGlanceCard(store: store, day: day, editor: $editor).frame(maxWidth: .infinity)
                }
                HStack(spacing: 12) {
                    ForEach(f.missions) { m in
                        Button { open(.goals) } label: { MissionChip(mission: m) }.buttonStyle(.plain).help("Open Goals")
                    }
                }
            }.padding(.bottom, 8)
        }.scrollIndicators(.never)
        .onAppear { if status.level.rawValue < lifestyle.lifestyle.seenLevel { lifestyle.update { $0.seenLevel = status.level.rawValue } } }
    }

    private func lede(_ f: BriefFacts) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(f.focusLine).font(.bt(size: 25)).foregroundStyle(Ink.ivory).lineLimit(1).layoutPriority(1)
            Text(f.focusDetail).font(.bt(size: 12)).foregroundStyle(Ink.muted).lineLimit(1)
            Spacer(minLength: 12)
            HStack(spacing: 9) {
                Button { day = engine.adding(-1, to: day) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).help("Previous day")
                Text(dateText(day, engine: engine, pattern: "EEE d MMM")).font(.bt(size: 11, design: .monospaced))
                Button { day = engine.adding(1, to: day) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).disabled(day >= store.today).help("Next day")
                if day != store.today { Button("Today") { day = store.today }.font(.bt(size: 11)).buttonStyle(.borderless) }
                DayActions(store: store, day: day)
            }.foregroundStyle(Ink.muted).fixedSize()
        }
    }
}

// MARK: - Your taps

struct TodayTapsCard: View {
    @ObservedObject var store: TrackerStore
    let day: String
    @Binding var editor: Editor?
    var open: (Screen) -> Void
    var body: some View {
        let engine = store.engine, doc = store.document
        let auto = doc.autoHabitIDs
        let manual = engine.due(on: day, includeMilestones: true).filter { !auto.contains($0.id) }
        let moments = doc.meds.moments(on: day, engine: engine)
        let left = manual.filter { engine.entry(for: $0, day: day) == nil }.count + moments.filter { !$0.allTaken }.count
        let meals = doc.meals.on(day).sorted { $0.takenAt < $1.takenAt }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                CardTitle("Your taps"); Spacer()
                Text(left == 0 ? "All done" : "\(left) left today").font(.bt(size: 12)).foregroundStyle(left == 0 ? Ink.onTrack : Ink.muted)
            }
            if doc.restDays.contains(day) {
                Label("Rest day · check-ins kept, not scored", systemImage: "moon.stars").font(.bt(size: 12)).foregroundStyle(Ink.accent).padding(.top, 10)
            }
            MedMomentsStrip(store: store, day: day, large: true).padding(.top, 14)
            if !manual.isEmpty {
                SubKicker("Today")
                ForEach(manual) { habit in
                    TapRow(store: store, habit: habit, day: day, onLog: { editor = .metric(habit, day) }, onEdit: { editor = .habit(habit, nil) })
                }
            }
            SubKicker(meals.isEmpty ? "Meals" : "Meals · \(meals.count) logged")
            ForEach(meals) { m in
                HStack {
                    Text(mealTitle(m)).font(.bt(size: 13)).foregroundStyle(Ink.ivory).lineLimit(1)
                    Spacer()
                    if m.confirmed {
                        Text("\(Int(m.kcal ?? 0)) kcal · \(Int(m.protein ?? 0)) g").font(.bt(size: 11, design: .monospaced)).foregroundStyle(Ink.muted)
                    } else { Text("ESTIMATING").font(.bt(size: 9.5, design: .monospaced)).tracking(1.2).foregroundStyle(Ink.watch) }
                }.padding(.vertical, 6)
            }
            HStack(spacing: 8) {
                Button { open(.meals) } label: {
                    Text("+ Log a meal").font(.bt(size: 12)).padding(.horizontal, 12).padding(.vertical, 7)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Ink.goldDim, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }.buttonStyle(.plain).foregroundStyle(Ink.accent)
                PlannedMealButton(store: store, day: day)
            }.padding(.top, 10)
        }.panel(padding: 22)
    }
    private func mealTitle(_ m: MealEntry) -> String {
        if let name = m.estimate?.name, !name.isEmpty { return name }
        return m.note.isEmpty ? "Meal" : m.note
    }
}

/// Logs the plan meal due now in one tap; the menu offers the plan's other open slots.
struct PlannedMealButton: View {
    @ObservedObject var store: TrackerStore
    let day: String
    var body: some View {
        let engine = store.engine
        let now = Date()
        let minute = day == store.today ? engine.calendar.component(.hour, from: now) * 60 + engine.calendar.component(.minute, from: now) : 24 * 60
        let open = store.document.planSlots(on: day, engine: engine).filter { !$0.logged }.map(\.slot)
        if let next = store.document.suggestedPlanSlot(on: day, minute: minute, engine: engine) {
            Menu {
                ForEach(open) { s in
                    Button("\(s.name) as planned · \(Int(s.kcal ?? 0)) kcal") { store.logPlanned(s, day: day) }
                }
            } label: { Text("\(next.name) as planned").font(.bt(size: 12)) } primaryAction: { store.logPlanned(next, day: day) }
            .menuStyle(.borderlessButton).fixedSize()
            .padding(.horizontal, 12).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Ink.line))
            .help("Logs \(next.name) with your plan's calories and protein. The arrow lists the other meals still open today.")
            .disabled(day > store.today)
        }
    }
}

/// A habit you answer yourself: two buttons, or Log for a number.
struct TapRow: View {
    @ObservedObject var store: TrackerStore
    let habit: Habit
    let day: String
    var onLog: () -> Void
    var onEdit: () -> Void
    var body: some View {
        let engine = store.engine
        let rev = habit.revision(on: day) ?? habit.latest
        let entry = engine.entry(for: habit, day: day)
        let words = Self.words(rev.title)
        VStack(spacing: 0) {
            Line()
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rev.title).font(.bt(size: 14, weight: .medium)).foregroundStyle(Ink.ivory)
                    Text(subtitle(rev)).font(.bt(size: 11)).foregroundStyle(Ink.muted).lineLimit(1)
                }
                Spacer()
                if habit.kind == .metric {
                    Button(action: onLog) { Text(entry?.value.map { "\($0.pretty) \(rev.target?.unit ?? "")" } ?? "Log").font(.bt(size: 12, design: .monospaced)) }
                        .buttonStyle(AnswerStyle(on: entry?.value != nil, good: true))
                } else {
                    Button(words.no) { store.answer(habit, day: day, done: false) }.buttonStyle(AnswerStyle(on: entry?.completed == false, good: false))
                    Button(words.yes) { store.answer(habit, day: day, done: true) }.buttonStyle(AnswerStyle(on: entry?.completed == true, good: true))
                }
                Button(action: onEdit) { Image(systemName: "ellipsis").font(.bt(size: 12)).frame(width: 18, height: 24) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).help("Edit \(rev.title)")
            }.padding(.vertical, 11)
            .disabled(day > store.today || (store.document.restDays.contains(day) && habit.kind != .milestone))
        }
    }
    static func words(_ title: String) -> (no: String, yes: String) {
        let t = title.lowercased()
        if t.hasPrefix("no ") { return ("Slipped", "Held") }
        if t.contains("accent") || t.contains("practi") { return ("Didn't", "Practised") }
        return ("Skipped", "Done")
    }
    private func subtitle(_ rev: HabitRevision) -> String {
        let engine = store.engine
        let monday = WeekFacts(store: store).monday(of: day)
        let n = engine.days(from: monday, through: day).filter { engine.completed(habit, on: $0) }.count
        let week = "\(n) this week"
        return rev.note.isEmpty ? week : "\(rev.note) · \(week)"
    }
}

struct AnswerStyle: ButtonStyle {
    var on: Bool
    var good: Bool
    func makeBody(configuration: Configuration) -> some View {
        let tint = good ? Ink.onTrack : Ink.offTrack
        configuration.label.font(.bt(size: 12.5)).padding(.horizontal, 13).padding(.vertical, 7)
            .foregroundStyle(on ? tint : Ink.ivory)
            .background(on ? tint.opacity(0.12) : Ink.panel2, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? tint.opacity(0.45) : Ink.line))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Ascend is tracking

struct GlanceLine: Identifiable {
    enum State { case done, going, waiting, missed }
    let id: String
    let title: String
    let state: State
    let value: String
    var note: String? = nil
    var ratio: Double? = nil
    var habit: Habit? = nil
}

struct TodayGlanceCard: View {
    @ObservedObject var store: TrackerStore
    let day: String
    @Binding var editor: Editor?
    var body: some View {
        let lines = Self.lines(store: store, day: day)
        let score = store.engine.score(on: day)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) { CardTitle("Ascend is tracking"); Spacer(); Text("Nothing to tap here").font(.bt(size: 12)).foregroundStyle(Ink.muted) }
                .padding(.bottom, 6)
            ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                if i > 0 { Line() }
                GlanceRow(store: store, line: line, day: day, onEdit: { if let h = line.habit { editor = .habit(h, nil) } })
            }
            Line().padding(.top, 6)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(score.completed) / \(score.scheduled)").font(.bt(size: 24)).foregroundStyle(Ink.ivory)
                Text(scoreText(score)).font(.bt(size: 11.5)).foregroundStyle(Ink.muted).lineLimit(1)
                Spacer(minLength: 8)
                if let sync = syncWarning {
                    Text(sync).font(.bt(size: 10.5, design: .monospaced)).foregroundStyle(Ink.watch).lineLimit(1)
                        .help("Sleep and steps come from the phone. Open Ascend Bridge on the Pixel to sync.")
                }
            }.padding(.top, 14)
        }.panel(padding: 22)
    }
    private func scoreText(_ s: Score) -> String {
        let target = store.document.cycle.target
        if s.scheduled == 0 { return "nothing scheduled" }
        let left = s.remaining(target: target)
        return "done today · \(Int(target * 100))% is the mission · " + (left > 0 ? "\(left) to go" : "hit")
    }
    /// Shown only when the phone's sleep and steps are more than 18 hours old.
    private var syncWarning: String? {
        guard day == store.today else { return nil }
        guard let last = store.document.phoneLastSync else { return "Phone not synced yet · open Bridge" }
        let age = Date().timeIntervalSince1970 - last
        guard age > 18 * 3600 else { return nil }
        let f = DateFormatter(); f.calendar = store.engine.calendar; f.timeZone = store.engine.calendar.timeZone; f.dateFormat = "EEE d MMM"
        return "Phone last synced \(f.string(from: Date(timeIntervalSince1970: last))) · open Bridge"
    }

    @MainActor static func lines(store: TrackerStore, day: String) -> [GlanceLine] {
        let doc = store.document, engine = store.engine, cal = engine.calendar
        var out: [GlanceLine] = []
        let health = doc.healthHabits, meal = doc.mealHabits
        // Sleep: last night, asleep by 1 am.
        if let h = health.sleep, engine.isDue(h, on: day) || engine.entry(for: h, day: day) != nil {
            if let s = doc.health.sleepSessions(on: day, engine: engine).first {
                let start = Date(timeIntervalSince1970: s.start)
                var minute = cal.component(.hour, from: start) * 60 + cal.component(.minute, from: start)
                if minute < 12 * 60 { minute += 1440 }
                let late = minute > 25 * 60
                let hours = (s.end - s.start) / 3600
                out.append(GlanceLine(id: "sleep", title: "Sleep", state: late ? .missed : .done,
                                      value: "\(Int(hours)) h \(String(format: "%02d", Int((hours * 60).rounded()) % 60)) · asleep \(HealthReport.clock(minute))",
                                      ratio: min(1, hours / 7.5), habit: h))
            } else { out.append(GlanceLine(id: "sleep", title: "Sleep", state: .waiting, value: "Not synced", note: "From the watch, via the phone", habit: h)) }
        }
        if let h = health.steps, engine.isDue(h, on: day) {
            let steps = doc.health.steps(on: day, engine: engine)
            out.append(GlanceLine(id: "steps", title: "Steps", state: steps == nil ? .waiting : (steps! >= 10_000 ? .done : .going),
                                  value: steps.map { "\(Int($0).formatted()) / 10,000" } ?? "Not synced", ratio: steps.map { $0 / 10_000 }, habit: h))
        }
        let totals = doc.meals.totals(day)
        if let h = meal.calories, engine.isDue(h, on: day), let max = engine.target(for: h, on: day)?.maximum {
            let over = totals.kcal > max
            out.append(GlanceLine(id: "kcal", title: "Calories", state: over ? .missed : .going,
                                  value: over ? "\(Int(totals.kcal - max)) over" : "\(Int(max - totals.kcal).formatted()) left", ratio: totals.kcal / max, habit: h))
        }
        if let h = meal.protein, engine.isDue(h, on: day), let min = engine.target(for: h, on: day)?.minimum {
            let hit = totals.protein >= min
            out.append(GlanceLine(id: "protein", title: "Protein", state: hit ? .done : .going,
                                  value: hit ? "\(Int(totals.protein)) g · hit" : "\(Int(min - totals.protein)) g to go", ratio: totals.protein / min, habit: h))
        }
        if let h = doc.gymHabit {
            let minutes = doc.gymMinutes(on: day, engine: engine)
            if minutes >= TrackerDocument.gymMinimumMinutes || engine.completed(h, on: day) {
                out.append(GlanceLine(id: "gym", title: "Gym", state: .done, value: "Done",
                                      note: minutes > 0 ? "Watch · strength \(Int(minutes)) min" : "Ticked by hand", habit: h))
            } else if engine.isDue(h, on: day) {
                out.append(GlanceLine(id: "gym", title: "Gym", state: .going, value: "Not yet", note: "Ticks itself when the watch records a gym workout", habit: h))
            }
        }
        let moments = doc.meds.moments(on: day, engine: engine)
        if let h = doc.medHabit, !moments.isEmpty {
            let taken = moments.filter(\.allTaken).count
            out.append(GlanceLine(id: "meds", title: doc.medHabit.map { ($0.revision(on: day) ?? $0.latest).title } ?? "Meds",
                                  state: taken == moments.count ? .done : .going, value: "\(taken) / \(moments.count)", note: "From your medicine taps", habit: h))
        }
        if let h = doc.sweetsHabit, engine.isDue(h, on: day), let diet = doc.diet {
            let slips = diet.unplannedSweets(doc.meals, day: day, calendar: cal)
            let done = engine.completed(h, on: day)
            out.append(GlanceLine(id: "sweets", title: "No sweets", state: !slips.isEmpty ? .missed : done ? .done : .waiting,
                                  value: !slips.isEmpty ? "Unplanned sweet" : done ? "Held" : (day == store.today ? "Tonight" : "No meals logged"),
                                  note: slips.isEmpty && !done ? "Decided from your logged meals" : nil, habit: h))
        }
        if let h = doc.windDownHabit, engine.isDue(h, on: day) {
            let e = engine.entry(for: h, day: day)
            out.append(GlanceLine(id: "wind", title: "Wind down", state: e?.completed == true ? .done : day >= store.today ? .waiting : (e == nil ? .waiting : .missed),
                                  value: e?.completed == true ? "Done" : day >= store.today ? "Tomorrow" : (e == nil ? "No screen data" : "Missed"),
                                  note: "15 min of screens or less in the 2 hours before sleep", habit: h))
        }
        return out
    }
}

struct GlanceRow: View {
    @ObservedObject var store: TrackerStore
    let line: GlanceLine
    let day: String
    var onEdit: () -> Void
    @State private var hover = false
    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 18, height: 18)
            Text(line.title).font(.bt(size: 14, weight: .medium)).foregroundStyle(Ink.ivory).frame(width: 104, alignment: .leading).lineLimit(1)
            if let ratio = line.ratio {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Ink.ivory.opacity(0.08))
                        Capsule().fill(color).frame(width: g.size.width * min(1, max(0, ratio)))
                    }
                }.frame(height: 4)
            } else {
                Text(line.note ?? "").font(.bt(size: 11.5)).foregroundStyle(Ink.muted).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(line.value).font(.bt(size: 11.5, design: .monospaced)).foregroundStyle(valueColor).lineLimit(1).frame(minWidth: 96, alignment: .trailing)
            Menu {
                if let h = line.habit {
                    Button("Mark done") { store.answer(h, day: day, done: true) }
                    Button("Mark not done") { store.answer(h, day: day, done: false) }
                    Divider()
                    Button("Edit habit…", action: onEdit)
                }
            } label: { Image(systemName: "ellipsis").font(.bt(size: 12)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().opacity(hover ? 1 : 0)
            .disabled(line.habit == nil || day > store.today)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .help(line.ratio != nil ? (line.note ?? "") : "")
    }
    private var color: Color { switch line.state { case .done: Ink.onTrack; case .missed: Ink.offTrack; default: Ink.accent } }
    private var valueColor: Color { switch line.state { case .done: Ink.onTrack; case .missed: Ink.offTrack; case .waiting: Ink.muted; case .going: Ink.ivory } }
    @ViewBuilder private var icon: some View {
        switch line.state {
        case .done: Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Ink.onTrack).frame(width: 18, height: 18).background(Ink.onTrack.opacity(0.16), in: Circle())
        case .missed: Text("!").font(.system(size: 11, weight: .bold)).foregroundStyle(Ink.offTrack).frame(width: 18, height: 18).background(Ink.offTrack.opacity(0.16), in: Circle())
        case .going: Circle().fill(Ink.accent).frame(width: 7, height: 7)
        case .waiting: Capsule().fill(Ink.muted).frame(width: 9, height: 1.5)
        }
    }
}

// MARK: - Pieces

struct CardTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text.uppercased()).font(.bt(size: 10.5, weight: .medium, design: .monospaced)).tracking(2.4).foregroundStyle(Ink.accent) }
}
struct SubKicker: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Kicker(text).padding(.top, 20).padding(.bottom, 8) }
}

/// One mission as a compact strip card: area, codename, status.
struct MissionChip: View {
    let mission: Mission
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("MISSION \(mission.number) · \(mission.area.uppercased())").font(.bt(size: 9, design: .monospaced)).tracking(1.4).foregroundStyle(Ink.goldDim)
            Text(mission.codename).font(.bt(size: 18)).foregroundStyle(Ink.ivory)
            Text("\(mission.value) \(mission.unit) · \(mission.statusText)".uppercased()).font(.bt(size: 9, design: .monospaced)).tracking(1.1).foregroundStyle(mission.status.color).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Ink.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ink.line))
        .contentShape(Rectangle())
    }
}
