import SwiftUI
import AscendCore

extension DailyMemoFacts {
    /// Yesterday's numbers, last night's sleep and the three missions, as of now. Urges are never read.
    @MainActor init(store: TrackerStore) {
        let engine = store.engine, doc = store.document, today = store.today, yesterday = engine.adding(-1, to: today)
        let rest = doc.restDays.contains(yesterday)
        let due = rest ? [] : engine.due(on: yesterday)
        let missed = due.filter { !engine.completed($0, on: yesterday) }.map { $0.latest.title }
        let night = doc.health.sleepSessions(on: today, engine: engine).first
        let onset: Int? = night.map {
            let start = Date(timeIntervalSince1970: $0.start)
            let m = engine.calendar.component(.hour, from: start) * 60 + engine.calendar.component(.minute, from: start)
            return m < 12 * 60 ? m + 1440 : m
        }
        let totals = doc.meals.totals(yesterday), habits = doc.mealHabits
        let gym = doc.habits.first { $0.latest.title.localizedCaseInsensitiveContains("gym") }
        let records = store.bodyMeasurements.archive.records.sorted { $0.date < $1.date }
        let last = records.last
        let weekAgo = last.flatMap { l in records.last { $0.date <= l.date.addingTimeInterval(-7 * 86400) } }
        let facts = BriefFacts(store: store, day: today)
        self.init(
            day: yesterday, checkIns: engine.score(on: yesterday), missed: missed,
            sleepMinutes: night.map { Int(($0.value * 60).rounded()) }, onsetMinute: onset,
            steps: doc.health.steps(on: yesterday, engine: engine),
            kcal: totals.confirmed > 0 ? totals.kcal : nil,
            kcalLimit: habits.calories.flatMap { engine.target(for: $0, on: yesterday)?.maximum },
            protein: totals.confirmed > 0 ? totals.protein : nil,
            proteinGoal: habits.protein.flatMap { engine.target(for: $0, on: yesterday)?.minimum },
            gymDone: gym.flatMap { g in engine.isDue(g, on: yesterday) && !rest ? engine.completed(g, on: yesterday) : nil },
            gymToday: gym.map { engine.isDue($0, on: today) && !engine.completed($0, on: today) && !doc.restDays.contains(today) } ?? false,
            weightKg: last?.kilograms, weightWeekAgoKg: weekAgo?.kilograms,
            goals: facts.missions.map { m in
                Goal(name: m.codename, status: m.statusText, line: m.detail,
                     onTrack: m.status == .onTrack ? true : m.status == .none ? nil : m.status == .offTrack ? false : nil)
            },
            daysLeft: facts.daysLeft, cycleEnd: dateText(doc.cycle.end, engine: engine, pattern: "d MMM"))
    }
}

/// M's morning memo on cream paper: yesterday, the goals, and up to three orders for today. Urges are never in it.
struct DailyMemoCard: View {
    @ObservedObject var store: TrackerStore
    @State private var folded = false
    private let paper = Color(hex: 0xF1E8D4), ink = Color(hex: 0x1D2A24), red = Color(hex: 0x9E2B33), green = Color(hex: 0x2F6B4A)

    var body: some View {
        let facts = DailyMemoFacts(store: store), memo = DailyMemo.compose(facts)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("MEMORANDUM · FROM M · DAILY").font(.bt(size: 10, weight: .semibold, design: .monospaced)).tracking(2)
                Spacer()
                Text(dateText(store.today, engine: store.engine, pattern: "EEE d MMM").uppercased()).font(.bt(size: 10, design: .monospaced))
                Button { withAnimation(.easeInOut(duration: 0.2)) { folded.toggle() } } label: { Image(systemName: folded ? "chevron.down" : "chevron.up") }
                    .buttonStyle(.plain).help(folded ? "Open the memo" : "Fold the memo")
            }.foregroundStyle(ink.opacity(0.7))
            Rectangle().fill(ink.opacity(0.25)).frame(height: 1)
            Text("007. " + memo.opening).font(.custom(Typeface.serif, fixedSize: 19).italic()).foregroundStyle(ink)
            if !folded {
                HStack(alignment: .top, spacing: 26) {
                    column("Yesterday · \(dateText(facts.day, engine: store.engine, pattern: "EEE d MMM"))", memo.yesterday)
                    column("Goals", memo.goals)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("TODAY").font(.bt(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(red)
                    ForEach(Array(memo.orders.enumerated()), id: \.offset) { i, order in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1).").font(.bt(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(red)
                            Text(order).font(.custom(Typeface.serif, fixedSize: 18).weight(.semibold)).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            HStack {
                Text("Written from your Cipher data · urges stay in the Urges tab").font(.bt(size: 10)).foregroundStyle(ink.opacity(0.55))
                Spacer()
                Text("— M").font(.custom(Typeface.serif, fixedSize: 18).italic()).foregroundStyle(ink.opacity(0.8))
            }
        }
        .padding(22).background(paper, in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .contextMenu { Button("Copy memo") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(memo.text, forType: .string) } }
    }

    private func column(_ title: String, _ lines: [DailyMemo.Line]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).font(.bt(size: 10, weight: .bold, design: .monospaced)).tracking(1.6).foregroundStyle(ink.opacity(0.6))
            ForEach(lines, id: \.label) { line in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle().fill(line.good == true ? green : line.good == false ? red : ink.opacity(0.3)).frame(width: 6, height: 6)
                    (Text(line.label + "  ").font(.bt(size: 12, weight: .semibold)) + Text(line.text).font(.bt(size: 12)))
                        .foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
