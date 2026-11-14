import Foundation
import AscendCore

/// lifestyle.json: the Dossier, clearance rewards and what's been seen. Starts from placeholders; stays on this Mac.
@MainActor
final class LifestyleStore: ObservableObject {
    @Published private(set) var lifestyle: Lifestyle
    @Published private(set) var saveError: String?
    let url: URL

    init(folder: URL) {
        url = folder.appendingPathComponent("lifestyle.json")
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(Lifestyle.self, from: data), (try? decoded.validate()) != nil {
            lifestyle = decoded
        } else {
            if FileManager.default.fileExists(atPath: url.path) {
                // Keep an unreadable file for recovery instead of overwriting it.
                try? FileManager.default.moveItem(at: url, to: folder.appendingPathComponent("lifestyle-unreadable-\(Int(Date().timeIntervalSince1970)).json"))
            }
            lifestyle = .placeholder
            save()
        }
    }

    func update(_ change: (inout Lifestyle) -> Void) {
        var next = lifestyle
        change(&next)
        do { try next.validate(); lifestyle = next; save() } catch { saveError = error.localizedDescription }
    }

    func upsert(_ item: DossierItem) {
        update { l in
            if let i = l.items.firstIndex(where: { $0.id == item.id }) { l.items[i] = item } else { l.items.append(item) }
        }
    }
    func delete(_ id: UUID) { update { $0.items.removeAll { $0.id == id } } }
    func setReward(_ mark: String, _ text: String) { update { $0.rewards[mark] = text.trimmingCharacters(in: .whitespacesAndNewlines) } }

    private func save() {
        do {
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(lifestyle).write(to: url, options: [.atomic])
            saveError = nil
        } catch { saveError = "Couldn't save the Dossier: \(error.localizedDescription)" }
    }
}

/// Finished weeks (Monday to Sunday) from the cycle's start, measured the same way as the Brief's dials.
@MainActor
struct WeekFacts {
    let store: TrackerStore
    private var engine: TrackerEngine { store.engine }
    private var cal: Calendar { engine.calendar }
    static let goalKg = 70.0

    func monday(of day: String) -> String {
        guard let d = engine.date(day) else { return day }
        return engine.adding(-((cal.component(.weekday, from: d) + 5) % 7), to: day)
    }
    var finishedWeeks: [String] {
        var m = monday(of: store.document.cycle.start)
        let current = monday(of: store.today)
        var weeks: [String] = []
        while m < current && weeks.count < 60 { weeks.append(m); m = engine.adding(7, to: m) }
        return weeks
    }
    var status: ClearanceStatus { Clearance.evaluate(finishedWeeks.map(clearanceWeek)) }
    /// Clean-week progress for the week in progress (Monday to today), for the "this week" hint.
    var thisWeek: ClearanceWeek { clearanceWeek(monday(of: store.today), through: store.today) }

    /// The memo's week: on Sunday from 10 am, this week; otherwise the last finished one.
    var debriefMonday: String? {
        let now = Date()
        let isSundayMorningOn = cal.component(.weekday, from: now) == 1 && cal.component(.hour, from: now) >= 10
        let m = isSundayMorningOn ? monday(of: store.today) : engine.adding(-7, to: monday(of: store.today))
        return m >= monday(of: store.document.cycle.start) ? m : nil
    }

    private func week(_ m: String, through end: String? = nil) -> [String] {
        let last = min(end ?? engine.adding(6, to: m), engine.adding(6, to: m))
        return engine.days(from: m, through: last)
    }

    func gym(_ days: [String]) -> Int {
        guard let g = store.document.habits.first(where: { $0.latest.title.localizedCaseInsensitiveContains("gym") }) else { return 0 }
        return days.filter { engine.completed(g, on: $0) }.count
    }
    func sleep(_ days: [String]) -> (byOne: Int, known: Int, average: Int?) {
        var on = 0, onsets: [Int] = []
        for d in days {
            guard let s = store.document.health.sleepSessions(on: d, engine: engine).first else { continue }
            let start = Date(timeIntervalSince1970: s.start)
            var minute = cal.component(.hour, from: start) * 60 + cal.component(.minute, from: start)
            if minute < 12 * 60 { minute += 1440 }
            onsets.append(minute)
            if minute <= 25 * 60 { on += 1 }
        }
        return (on, onsets.count, onsets.isEmpty ? nil : onsets.reduce(0, +) / onsets.count)
    }
    private var records: [BodyMeasurement] { store.bodyMeasurements.archive.records.sorted { $0.date < $1.date } }
    private var startKg: Double? {
        let r = records
        guard let startDate = engine.date(store.document.cycle.start) else { return r.first?.kilograms }
        return (r.last { $0.date <= startDate } ?? r.first { $0.date >= startDate })?.kilograms
    }
    private func kg(before date: Date) -> BodyMeasurement? { records.last { $0.date < date } }

    func clearanceWeek(_ m: String) -> ClearanceWeek { clearanceWeek(m, through: nil) }
    func clearanceWeek(_ m: String, through end: String?) -> ClearanceWeek {
        let days = week(m, through: end)
        let s = sleep(days)
        let score = engine.score(from: days.first ?? m, through: days.last ?? m)
        let weekEnd = engine.date(engine.adding(1, to: days.last ?? m)) ?? Date()
        let last = kg(before: weekEnd)
        let down: Double? = { if let a = startKg, let b = last?.kilograms { return a - b }; return nil }()
        return ClearanceWeek(start: m, gym: gym(days), nightsByOne: s.byOne, nightsKnown: s.known, checkIns: score.ratio ?? 0,
                             kgDown: down, atGoal: (last?.kilograms ?? 99) <= Self.goalKg)
    }

    func debriefWeek(_ m: String) -> DebriefWeek {
        let days = week(m)
        let s = sleep(days)
        let weekStart = engine.date(m) ?? Date(), weekEnd = engine.date(engine.adding(7, to: m)) ?? Date()
        let inWeek = records.filter { $0.date >= weekStart && $0.date < weekEnd }
        let before = kg(before: weekStart) ?? inWeek.first
        let steps = days.compactMap { store.document.health.steps(on: $0, engine: engine) }
        let mealDays = days.filter { store.document.meals.totals($0).kcal > 0 }
        let proteinHabit = store.document.mealHabits.protein
        let proteinDays = proteinHabit.map { h in mealDays.filter { d in engine.target(for: h, on: d)?.minimum.map { store.document.meals.totals(d).protein >= $0 } ?? false }.count }
        return DebriefWeek(start: m, checkIns: engine.score(from: m, through: days.last ?? m), gym: gym(days), nightsByOne: s.byOne, nightsKnown: s.known,
                           averageOnsetMinute: s.average, kgStart: inWeek.isEmpty ? nil : before?.kilograms, kgEnd: inWeek.last?.kilograms,
                           averageSteps: steps.isEmpty ? nil : steps.reduce(0, +) / Double(steps.count),
                           proteinDays: mealDays.isEmpty ? nil : proteinDays, loggedDays: mealDays.count)
    }
}

