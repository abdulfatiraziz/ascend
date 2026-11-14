import SwiftUI
import AscendCore

/// The five missions (A–E) at the top of the Goals tab.
struct MissionBoard: View {
    @ObservedObject var store: TrackerStore
    @ObservedObject var missions: MissionStore
    @Binding var editor: Editor?
    @State private var open: MissionFile?

    var body: some View {
        let facts = MissionFacts(store: store)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Kicker("Missions / top 1% by design")
                Spacer()
                Text("Age 30 · 180 cm · open a file for every target and the daily habits").font(.bt(size: 10, design: .monospaced)).foregroundStyle(Ink.muted)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                ForEach(missions.missions) { m in
                    Button { open = m } label: { MissionCard(mission: m, facts: facts, today: store.today) }
                        .buttonStyle(.plain)
                        .help("Open mission \(m.id): \(m.title)")
                }
            }
        }
        .sheet(item: $open) { m in
            MissionSheet(missionID: m.id, store: store, missions: missions, facts: facts, today: store.today, close: { open = nil }) { habit in
                // Close the file first; the habit editor is a sheet of its own.
                open = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { editor = .habit(habit, habit?.goalID ?? store.document.goals.first?.id) }
            }
        }
    }
}

private func statusColor(_ t: MissionTarget, _ value: Double?, today: String) -> Color {
    guard let v = value else { return Ink.goldDim }
    if (t.progress(v) ?? 0) >= 1 { return Ink.onTrack }
    guard let plan = t.planned(on: today) else { return Ink.accent }
    let ahead = t.lowerIsBetter ? v <= plan + 0.05 : v >= plan * 0.98
    return ahead ? Ink.onTrack : Ink.watch
}

struct MissionCard: View {
    let mission: MissionFile
    let facts: MissionFacts
    let today: String
    var body: some View {
        let p = mission.progress(facts.value)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(mission.id).font(.bt(size: 34, weight: .medium, design: .serif)).foregroundStyle(Ink.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mission.codename.uppercased()).font(.bt(size: 9, design: .monospaced)).tracking(2).foregroundStyle(Ink.muted)
                    Text(mission.title).font(.bt(size: 19, weight: .medium, design: .serif)).foregroundStyle(Ink.ivory).lineLimit(1).minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
                Text(p.map { "\(Int(($0 * 100).rounded()))%" } ?? "—").font(.bt(size: 20, design: .serif)).foregroundStyle(Ink.lamp)
            }
            Bar(value: p ?? 0, color: Ink.accent)
            Text("DUE " + dueLabel(mission.due)).font(.bt(size: 9, design: .monospaced)).tracking(1.5).foregroundStyle(Ink.goldDim)
            Line()
            ForEach(mission.targets.prefix(3)) { t in
                let v = facts.value(t)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t.title).font(.bt(size: 11)).foregroundStyle(Ink.ivory).lineLimit(1)
                        Spacer()
                        Text("\(t.format(v)) → \(t.format(t.target))").font(.bt(size: 10, design: .monospaced)).foregroundStyle(statusColor(t, v, today: today))
                    }
                    Bar(value: t.progress(v) ?? 0, color: statusColor(t, v, today: today), height: 2)
                }
            }
            if mission.targets.count > 3 {
                Text("+ \(mission.targets.count - 3) more in the file").font(.bt(size: 10)).foregroundStyle(Ink.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .panel(padding: 18)
        .contentShape(Rectangle())
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

/// Every target in one mission, with the math, and fields for the numbers you type by hand.
struct MissionSheet: View {
    let missionID: String
    @ObservedObject var store: TrackerStore
    @ObservedObject var missions: MissionStore
    let facts: MissionFacts
    let today: String
    let close: () -> Void
    let editHabit: (Habit?) -> Void
    @State private var drafts: [String: String] = [:]

    var body: some View {
        let m = missions.missions.first { $0.id == missionID } ?? Missions.defaults[0]
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(m.id).font(.bt(size: 44, weight: .medium, design: .serif)).foregroundStyle(Ink.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MISSION \(m.id) · \(m.codename.uppercased()) · DUE \(dueLabel(m.due))").font(.bt(size: 10, design: .monospaced)).tracking(1.5).foregroundStyle(Ink.muted)
                    Text(m.title).font(.bt(size: 28, weight: .medium, design: .serif)).foregroundStyle(Ink.ivory)
                }
                Spacer()
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
            Text(m.brief).font(.bt(size: 13)).foregroundStyle(Ink.ivory.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
            Line()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(m.targets) { t in row(t) }
                    if m.id == "A" { habits }
                }.padding(.trailing, 6)
            }
            if let e = missions.saveError { Text(e).font(.bt(size: 11)).foregroundStyle(Ink.offTrack) }
        }
        .padding(28)
        .frame(width: 640, height: 620)
        .background(Ink.background)
    }

    @ViewBuilder private func row(_ t: MissionTarget) -> some View {
        let v = facts.value(t)
        let live = facts.isLive(t)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(t.title).font(.bt(size: 13, weight: .medium)).foregroundStyle(Ink.ivory)
                if live { Text("LIVE").font(.bt(size: 8, design: .monospaced)).tracking(1.5).foregroundStyle(Ink.onTrack) }
                Spacer()
                if t.checklist && !live {
                    Toggle("", isOn: Binding(get: { (t.current ?? 0) >= 1 }, set: { missions.setCurrent(t.id, $0 ? 1 : 0) }))
                        .toggleStyle(.checkbox).labelsHidden()
                } else if !live {
                    TextField("—", text: Binding(get: { drafts[t.id] ?? t.current.map { t.format($0).filter { "0123456789.-".contains($0) } } ?? "" },
                                                 set: { drafts[t.id] = $0 }))
                        .textFieldStyle(.roundedBorder).frame(width: 90).font(.bt(size: 12, design: .monospaced))
                        .onSubmit { commit(t) }
                }
                Text(t.checklist ? t.format(v) : "\(t.format(v)) → \(t.format(t.target))")
                    .font(.bt(size: 12, design: .monospaced)).foregroundStyle(statusColor(t, v, today: today)).frame(minWidth: 140, alignment: .trailing)
            }
            Bar(value: t.progress(v) ?? 0, color: statusColor(t, v, today: today), height: 2)
            if let plan = t.planned(on: today) {
                Text("On plan today: \(t.format((plan * 10).rounded() / 10))").font(.bt(size: 10, design: .monospaced)).foregroundStyle(Ink.goldDim)
            }
            if !t.detail.isEmpty { Text(t.detail).font(.bt(size: 11)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true) }
        }
        .onDisappear { commit(t) }
    }

    /// Mission A's daily habits (the old habit goals), grouped by goal. Check-ins and history are unchanged.
    private var habits: some View {
        VStack(alignment: .leading, spacing: 10) {
            Line().padding(.top, 8)
            HStack { Kicker("Daily habits / scored every day"); Spacer(); Button("+ Habit") { editHabit(nil) }.font(.bt(size: 11)) }
            ForEach(store.document.goals) { goal in
                let list = store.document.habits.filter { $0.goalID == goal.id && $0.archivedDay == nil && $0.kind != .milestone }
                if !list.isEmpty {
                    Text(goal.title.uppercased()).font(.bt(size: 9, design: .monospaced)).tracking(1.5).foregroundStyle(Ink.goldDim).padding(.top, 4)
                    ForEach(list) { habit in
                        Button { editHabit(habit) } label: {
                            HStack {
                                Image(systemName: habit.kind == .metric ? "number" : "circle").frame(width: 16).foregroundStyle(Ink.accent)
                                Text(habit.latest.title).font(.bt(size: 12)).foregroundStyle(Ink.ivory)
                                Spacer()
                                Text(habit.latest.schedule.label).font(.bt(size: 10)).foregroundStyle(Ink.muted)
                                Image(systemName: "chevron.right").font(.bt(size: 9)).foregroundStyle(Ink.muted)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
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
