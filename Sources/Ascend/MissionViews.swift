import SwiftUI
import AscendCore

/// The Goals tab as a briefing room: a classified status line, a radar of the five missions,
/// the three orders most behind plan, and a slim ledger of the missions.
struct MissionBoard: View {
    @ObservedObject var store: TrackerStore
    @ObservedObject var missions: MissionStore
    @Binding var editor: Editor?
    @State private var open: MissionFile?

    var body: some View {
        let facts = MissionFacts(store: store)
        let ms = missions.missions
        let orders = Missions.orders(ms, value: facts.value, today: store.today)
        let level = WeekFacts(store: store).status.level
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text("CLASSIFIED · STATUS AS OF \(Self.stamp())").font(.bt(size: 10, design: .monospaced)).tracking(2).foregroundStyle(Ink.muted)
                Spacer()
                Text("CLEARANCE \(level.mark) · \(level.rank.uppercased())").font(.bt(size: 10, design: .monospaced)).tracking(2).foregroundStyle(Ink.accent)
            }
            Line()
            HStack(alignment: .top, spacing: 28) {
                VStack(spacing: 10) {
                    MissionRadar(values: ms.map { $0.progress(facts.value) ?? 0 }, labels: ms.map(\.id)) { i in open = ms[i] }
                        .frame(width: 300, height: 300)
                    Text("THE SHAPE GROWS TO THE GOLD LINE AS YOU HIT TARGETS").font(.bt(size: 8, design: .monospaced)).tracking(1.5).foregroundStyle(Ink.goldDim)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Kicker("Orders / the three most behind")
                    if orders.isEmpty {
                        Text("All targets on plan. Hold the line.").font(.bt(size: 22, design: .serif)).foregroundStyle(Ink.lamp)
                    }
                    ForEach(Array(orders.enumerated()), id: \.offset) { i, o in
                        Button { open = ms.first { $0.id == o.missionID } } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                Text(String(format: "%02d", i + 1)).font(.bt(size: 22, design: .serif)).foregroundStyle(Ink.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(o.target.title).font(.bt(size: 15, weight: .medium)).foregroundStyle(Ink.ivory)
                                    Text(o.line).font(.bt(size: 11, design: .monospaced)).foregroundStyle(o.value == nil ? Ink.muted : Ink.watch)
                                }
                                Spacer()
                                Text(o.missionID).font(.bt(size: 18, design: .serif)).foregroundStyle(Ink.goldDim)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).help("Open mission \(o.missionID)")
                        Line()
                    }
                    let all = ms.flatMap(\.targets).filter { !$0.checklist }
                    let measured = all.filter { facts.value($0) != nil }.count
                    let behind = Missions.orders(ms, value: facts.value, today: store.today, limit: 99).filter { $0.value != nil }.count
                    HStack(spacing: 26) {
                        stat("\(measured) of \(all.count)", "targets measured")
                        stat("\(behind)", "behind plan")
                        stat("\(ms.flatMap(\.targets).filter { $0.checklist && ($0.current ?? 0) >= 1 }.count)", "milestones done")
                    }.padding(.top, 4)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Line()
            VStack(spacing: 0) {
                ForEach(ms) { m in
                    Button { open = m } label: { MissionLedgerRow(mission: m, facts: facts, today: store.today) }
                        .buttonStyle(.plain).help("Open mission \(m.id): \(m.title)")
                    Line()
                }
            }
            Text("Open a mission for every target, the math and the daily habits.").font(.bt(size: 10)).foregroundStyle(Ink.muted)
        }
        .onAppear {
            // ASCEND_OPEN_MISSION=A opens a mission file on launch, like ASCEND_OPEN_SCREEN.
            if let id = ProcessInfo.processInfo.environment["ASCEND_OPEN_MISSION"], open == nil { open = ms.first { $0.id == id } }
        }
        .sheet(item: $open) { m in
            MissionSheet(missionID: m.id, store: store, missions: missions, facts: facts, today: store.today, close: { open = nil }) { habit in
                // Close the file first; the habit editor is a sheet of its own.
                open = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { editor = .habit(habit, habit?.goalID ?? store.document.goals.first?.id) }
            }
        }
    }

    private func stat(_ big: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(big).font(.bt(size: 20, design: .serif)).foregroundStyle(Ink.ivory)
            Text(label.uppercased()).font(.bt(size: 8, design: .monospaced)).tracking(1.5).foregroundStyle(Ink.muted)
        }
    }

    static func stamp() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "h:mm a, EEE d MMM"
        return f.string(from: Date()).uppercased()
    }
}

private func statusColor(_ t: MissionTarget, _ value: Double?, today: String) -> Color {
    guard let v = value else { return Ink.goldDim }
    if (t.progress(v) ?? 0) >= 1 { return Ink.onTrack }
    guard let plan = t.planned(on: today) else { return Ink.accent }
    let ahead = t.lowerIsBetter ? v <= plan + 0.05 : v >= plan * 0.98
    return ahead ? Ink.onTrack : Ink.watch
}

/// One mission as a dossier index row.
struct MissionLedgerRow: View {
    let mission: MissionFile
    let facts: MissionFacts
    let today: String
    var body: some View {
        let p = mission.progress(facts.value)
        let status = Missions.status(mission, value: facts.value, today: today)
        HStack(spacing: 18) {
            Text(mission.id).font(.bt(size: 26, weight: .medium, design: .serif)).foregroundStyle(Ink.accent).frame(width: 26)
            Text(mission.codename.uppercased()).font(.bt(size: 10, design: .monospaced)).tracking(2).foregroundStyle(Ink.muted).frame(width: 150, alignment: .leading)
            Text(mission.title).font(.bt(size: 18, weight: .medium, design: .serif)).foregroundStyle(Ink.ivory).frame(width: 190, alignment: .leading).lineLimit(1)
            Bar(value: p ?? 0, color: Ink.accent, height: 3)
            Text(p.map { "\(Int(($0 * 100).rounded()))%" } ?? "0%").font(.bt(size: 16, design: .serif)).foregroundStyle(Ink.lamp).frame(width: 48, alignment: .trailing)
            Text(status.rawValue.uppercased())
                .font(.bt(size: 9, design: .monospaced)).tracking(1.5)
                .foregroundStyle(status == .onPlan ? Ink.onTrack : status == .behind ? Ink.watch : Ink.muted)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .overlay(Capsule().stroke(status == .onPlan ? Ink.onTrack.opacity(0.5) : status == .behind ? Ink.watch.opacity(0.5) : Ink.line))
                .frame(width: 100)
            Text(dueLabel(mission.due)).font(.bt(size: 10, design: .monospaced)).tracking(1.5).foregroundStyle(Ink.goldDim).frame(width: 110, alignment: .trailing)
            Image(systemName: "chevron.right").font(.bt(size: 10)).foregroundStyle(Ink.muted)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// Five-axis radar: gold outline = 100%, filled shape = where you are. One sweep when it appears.
struct MissionRadar: View {
    let values: [Double]
    let labels: [String]
    let tap: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = 0.0
    @State private var sweeping = false
    @State private var grown = false

    private func point(_ i: Int, _ r: Double, in size: CGSize) -> CGPoint {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 30
        let a = -Double.pi / 2 + Double(i) * 2 * .pi / Double(values.count)
        return CGPoint(x: c.x + cos(a) * radius * r, y: c.y + sin(a) * radius * r)
    }
    private func polygon(_ r: (Int) -> Double, in size: CGSize) -> Path {
        var p = Path()
        for i in values.indices { let pt = point(i, r(i), in: size); i == 0 ? p.move(to: pt) : p.addLine(to: pt) }
        p.closeSubpath(); return p
    }

    var body: some View {
        GeometryReader { g in
            let size = g.size
            let shown: (Int) -> Double = { i in grown ? max(0.04, min(1, values[i])) : 0.04 }
            ZStack {
                ForEach([0.25, 0.5, 0.75], id: \.self) { r in polygon({ _ in r }, in: size).stroke(Ink.line, lineWidth: 1) }
                ForEach(values.indices, id: \.self) { i in
                    Path { p in p.move(to: point(i, 0, in: size)); p.addLine(to: point(i, 1, in: size)) }.stroke(Ink.line, lineWidth: 1)
                }
                polygon({ _ in 1 }, in: size).stroke(Ink.accent.opacity(0.85), lineWidth: 1.2)
                if sweeping {
                    Circle()
                        .fill(AngularGradient(colors: [Ink.lamp.opacity(0), Ink.lamp.opacity(0.28)], center: .center, startAngle: .degrees(-50), endAngle: .degrees(0)))
                        .frame(width: min(size.width, size.height) - 60, height: min(size.width, size.height) - 60)
                        .rotationEffect(.degrees(sweep - 90))
                        .position(x: size.width / 2, y: size.height / 2)
                        .allowsHitTesting(false)
                }
                polygon(shown, in: size).fill(Ink.accent.opacity(0.22))
                polygon(shown, in: size).stroke(Ink.lamp, lineWidth: 1.6)
                ForEach(values.indices, id: \.self) { i in
                    Circle().fill(Ink.lamp).frame(width: 6, height: 6).position(point(i, shown(i), in: size))
                    Button { tap(i) } label: {
                        VStack(spacing: 0) {
                            Text(labels[i]).font(.bt(size: 18, weight: .medium, design: .serif)).foregroundStyle(Ink.accent)
                            Text("\(Int((values[i] * 100).rounded()))%").font(.bt(size: 9, design: .monospaced)).foregroundStyle(Ink.muted)
                        }.frame(width: 44, height: 40).contentShape(Rectangle())
                    }.buttonStyle(.plain).position(point(i, 1.22, in: size)).help("Open mission \(labels[i])")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mission radar. " + values.indices.map { "\(labels[$0]) \(Int((values[$0] * 100).rounded())) percent" }.joined(separator: ", "))
        .onAppear {
            guard !reduceMotion, ProcessInfo.processInfo.environment["ASCEND_SNAPSHOT"] == nil else { grown = true; return }
            sweeping = true
            withAnimation(.easeInOut(duration: 2.2)) { sweep = 360 }
            withAnimation(.spring(duration: 1.1, bounce: 0.25).delay(0.5)) { grown = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) { withAnimation(.easeOut(duration: 0.4)) { sweeping = false } }
        }
    }
}

struct Bar: View {
    var value: Double
    var color: Color
    var height: CGFloat = 3
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.line)
                Capsule().fill(color).frame(width: max(height, g.size.width * min(1, max(0, value))))
            }
        }.frame(height: height)
    }
}

func dueLabel(_ day: String) -> String {
    guard let d = MissionTargetDate.parse(day) else { return day }
    let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "d MMM yyyy"
    return f.string(from: d).uppercased()
}
enum MissionTargetDate {
    static func parse(_ key: String) -> Date? {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }
}

/// One mission's file, in three plain groups: what syncs by itself, what the app works out, and what you log.
struct MissionSheet: View {
    let missionID: String
    @ObservedObject var store: TrackerStore
    @ObservedObject var missions: MissionStore
    let facts: MissionFacts
    let today: String
    let close: () -> Void
    let editHabit: (Habit?) -> Void
    @State private var drafts: [String: String] = [:]
    @State private var showHabits = false
    @FocusState private var focus: String?

    var body: some View {
        let m = missions.missions.first { $0.id == missionID } ?? Missions.defaults[0]
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(m.id).font(.bt(size: 44, weight: .medium, design: .serif)).foregroundStyle(Ink.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MISSION \(m.id) · \(m.codename.uppercased()) · DUE \(dueLabel(m.due))").font(.bt(size: 10, design: .monospaced)).tracking(1.5).foregroundStyle(Ink.muted)
                    Text(m.title).font(.bt(size: 28, weight: .medium, design: .serif)).foregroundStyle(Ink.ivory)
                }
                Spacer()
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(TargetKind.allCases, id: \.self) { kind in
                        let list = m.targets.filter { $0.kind == kind }
                        if !list.isEmpty { group(kind, list) }
                    }
                    if m.id == "A" { habits }
                }.padding(.trailing, 4)
            }
            .scrollIndicators(.never)
            if let e = missions.saveError { Text(e).font(.bt(size: 11)).foregroundStyle(Ink.offTrack) }
        }
        .padding(28)
        .frame(width: 620, height: 640)
        .background(Ink.background)
        // Don't start with a box selected; click one to type.
        .onAppear { DispatchQueue.main.async { focus = nil } }
    }

    private func group(_ kind: TargetKind, _ list: [MissionTarget]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: kind == .synced ? "arrow.triangle.2.circlepath" : kind == .calculated ? "function" : kind == .dated ? "calendar" : kind == .reminder ? "bell" : "pencil")
                    .font(.bt(size: 11)).foregroundStyle(Ink.accent)
                Text(kind.rawValue.uppercased()).font(.bt(size: 10, design: .monospaced)).tracking(2).foregroundStyle(Ink.accent)
                Spacer()
                Text(kind == .synced ? "Nothing to do" : kind == .calculated ? "Worked out for you" : kind == .dated ? "Add the date when you plan one" : kind == .reminder ? "Pick a date; the next one sets itself" : "Type the number, press return")
                    .font(.bt(size: 10)).foregroundStyle(Ink.muted)
            }.padding(.bottom, 8)
            Line()
            ForEach(list) { t in
                row(t)
                Line()
            }
        }
    }

    private func row(_ t: MissionTarget) -> some View {
        let v = facts.value(t)
        let state = t.state(v, today: today)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(.bt(size: 13, weight: .medium)).foregroundStyle(Ink.ivory)
                Text(t.isDated ? datedLine(t) : t.kind == .manual || t.isVisit ? t.cadence : t.source).font(.bt(size: 10)).foregroundStyle(Ink.muted)
                if t.isDated { plannedChips(t) }
            }
            Spacer(minLength: 8)
            if t.isDated {
                PlanDate { missions.setPlanned(t.id, day: $0, on: true) }
                Text("\(Int(v ?? 0))").font(.bt(size: 13, design: .monospaced)).foregroundStyle(Ink.ivory).frame(width: 24, alignment: .trailing)
            } else if t.isVisit {
                VisitDate(label: "Last", day: t.lastVisit, suggested: nil) { missions.setVisit(t.id, last: .some($0)) }
                VisitDate(label: "Next", day: t.nextVisitDay, suggested: t.nextVisit == nil ? t.nextVisitDay : nil) { missions.setVisit(t.id, next: .some($0)) }
            } else if t.kind == .manual {
                if t.checklist {
                    Toggle("", isOn: Binding(get: { (t.current ?? 0) >= 1 }, set: { missions.setCurrent(t.id, $0 ? 1 : 0) }))
                        .toggleStyle(.checkbox).labelsHidden()
                } else {
                    TextField("—", text: Binding(get: { drafts[t.id] ?? t.current.map(plain) ?? "" }, set: { drafts[t.id] = $0 }))
                        .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                        .font(.bt(size: 13, design: .monospaced)).foregroundStyle(Ink.lamp)
                        .padding(.horizontal, 8).padding(.vertical, 5).frame(width: 78)
                        .background(Ink.panel, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Ink.line))
                        .focused($focus, equals: t.id)
                        .onSubmit { commit(t) }
                    Text(t.unit).font(.bt(size: 10, design: .monospaced)).foregroundStyle(Ink.muted).frame(width: 34, alignment: .leading)
                }
            } else {
                Text(t.format(v)).font(.bt(size: 13, design: .monospaced)).foregroundStyle(Ink.ivory)
            }
            if !t.isVisit { Text(t.checklist ? "" : "→ \(t.format(t.target))").font(.bt(size: 11, design: .monospaced)).foregroundStyle(Ink.goldDim).frame(width: 92, alignment: .leading) }
            Text(state.rawValue.uppercased())
                .font(.bt(size: 9, design: .monospaced)).tracking(1.2)
                .foregroundStyle(state == .done || state == .onPlan || state == .scheduled ? Ink.onTrack : state == .behind || state == .overdue ? Ink.watch : Ink.muted)
                .frame(width: 82, alignment: .trailing)
        }
        .padding(.vertical, 11)
        .help(helpText(t))
        .onDisappear { commit(t) }
    }

    private func helpText(_ t: MissionTarget) -> String {
        var parts = [t.detail]
        if let plan = t.planned(on: today) { parts.append("On plan today: \(t.format((plan * 10).rounded() / 10)).") }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }
    private func datedLine(_ t: MissionTarget) -> String {
        t.nextPlanned(today: today).map { "Next: " + shortDay($0) } ?? "Nothing planned yet"
    }
    private func shortDay(_ key: String) -> String {
        guard let d = MissionFacts.dayFormatter.date(from: key) else { return key }
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f.string(from: d)
    }
    /// This month's and upcoming planned days; click one to remove it.
    @ViewBuilder private func plannedChips(_ t: MissionTarget) -> some View {
        let days = (t.plannedDays ?? []).filter { $0.prefix(7) >= today.prefix(7) }
        if !days.isEmpty {
            HStack(spacing: 5) {
                ForEach(days, id: \.self) { day in
                    Button { missions.setPlanned(t.id, day: day, on: false) } label: {
                        HStack(spacing: 3) { Text(shortDay(day)); Image(systemName: "xmark").font(.system(size: 7, weight: .semibold)) }
                            .font(.bt(size: 10)).foregroundStyle(day <= today ? Ink.ivory : Ink.muted)
                            .padding(.horizontal, 7).padding(.vertical, 2).overlay(Capsule().stroke(Ink.line))
                    }.buttonStyle(.plain).help("Remove \(shortDay(day))")
                }
            }.padding(.top, 3)
        }
    }
    private func plain(_ v: Double) -> String { v.rounded() == v ? String(Int(v)) : String(v) }

    /// Mission A's daily habits (the old habit goals), folded away. Check-ins and history are unchanged.
    private var habits: some View {
        let goals = store.document.goals.map { g in (g, store.document.habits.filter { $0.goalID == g.id && $0.archivedDay == nil && $0.kind != .milestone }) }.filter { !$0.1.isEmpty }
        return VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.2)) { showHabits.toggle() } } label: {
                HStack {
                    Image(systemName: "checklist").font(.bt(size: 11)).foregroundStyle(Ink.accent)
                    Text("DAILY HABITS · \(goals.map(\.1.count).reduce(0, +))").font(.bt(size: 10, design: .monospaced)).tracking(2).foregroundStyle(Ink.accent)
                    Spacer()
                    Text("Ticked on Today").font(.bt(size: 10)).foregroundStyle(Ink.muted)
                    Image(systemName: showHabits ? "chevron.up" : "chevron.down").font(.bt(size: 10)).foregroundStyle(Ink.muted)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.bottom, 8)
            Line()
            if showHabits {
                ForEach(goals, id: \.0.id) { goal, list in
                    ForEach(list) { habit in
                        Button { editHabit(habit) } label: {
                            HStack {
                                Text(habit.latest.title).font(.bt(size: 12)).foregroundStyle(Ink.ivory)
                                Spacer()
                                Text(habit.latest.schedule.label).font(.bt(size: 10)).foregroundStyle(Ink.muted)
                                Image(systemName: "chevron.right").font(.bt(size: 9)).foregroundStyle(Ink.muted)
                            }.padding(.vertical, 9).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Line()
                    }
                }
                Button("+ Habit") { editHabit(nil) }.buttonStyle(.borderless).font(.bt(size: 11)).padding(.top, 10)
            }
        }
    }

    private func commit(_ t: MissionTarget) {
        guard let text = drafts[t.id] else { return }
        drafts[t.id] = nil
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        missions.setCurrent(t.id, trimmed.isEmpty ? nil : Double(trimmed.replacingOccurrences(of: ",", with: "")))
    }
}

/// A day picker for a visit. Empty shows "Pick date"; a suggested day (worked out, not booked) shows dimmed until you change it.
struct VisitDate: View {
    let label: String
    let day: String?
    let suggested: String?
    let set: (String?) -> Void
    private static let utc = TimeZone(identifier: "UTC")!
    private static let f: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.timeZone = utc; f.dateFormat = "yyyy-MM-dd"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased() + (suggested != nil ? " · AUTO" : "")).font(.bt(size: 8, design: .monospaced)).tracking(1.2).foregroundStyle(Ink.muted)
            if let d = day, let date = Self.f.date(from: d) {
                DatePicker("", selection: Binding(get: { date }, set: { set(Self.f.string(from: $0)) }), displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.field)
                    .environment(\.timeZone, Self.utc)
                    .opacity(suggested != nil ? 0.6 : 1)
                    .contextMenu { Button("Clear") { set(nil) } }
            } else {
                Button("Pick date") { set(Self.f.string(from: Date())) }
                    .buttonStyle(.borderless).font(.bt(size: 11)).foregroundStyle(Ink.lamp)
                    .frame(height: 22)
            }
        }.frame(width: 104, alignment: .leading)
    }
}

/// Pick a day and add it to a dated target (a planned meet-up or date).
struct PlanDate: View {
    let add: (String) -> Void
    @State private var day = Date()
    var body: some View {
        HStack(spacing: 6) {
            DatePicker("", selection: $day, displayedComponents: .date)
                .labelsHidden().datePickerStyle(.field)
                .environment(\.timeZone, MissionFacts.dayFormatter.timeZone)
            Button("Add") { add(MissionFacts.dayFormatter.string(from: day)) }
                .buttonStyle(.borderless).font(.bt(size: 11)).foregroundStyle(Ink.lamp)
        }.frame(width: 150, alignment: .trailing)
    }
}

extension MissionFacts {
    /// yyyy-MM-dd in UTC, matching the visit dates.
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone(identifier: "UTC")!; f.dateFormat = "yyyy-MM-dd"; return f
    }()
}
