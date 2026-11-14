import Foundation
import AscendCore

/// missions.json: the five missions (A–E) and the values typed by hand. Stays on this Mac.
@MainActor
final class MissionStore: ObservableObject {
    @Published private(set) var missions: [MissionFile]
    @Published private(set) var saveError: String?
    let url: URL

    init(folder: URL) {
        url = folder.appendingPathComponent("missions.json")
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([MissionFile].self, from: data), decoded.count == 5 {
            missions = decoded
        } else {
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.moveItem(at: url, to: folder.appendingPathComponent("missions-unreadable-\(Int(Date().timeIntervalSince1970)).json"))
            }
            missions = Missions.defaults
            save()
        }
    }

    func setCurrent(_ targetID: String, _ value: Double?) {
        guard value.map({ $0.isFinite && abs($0) < 1e9 }) ?? true else { saveError = "That number is out of range."; return }
        for m in missions.indices {
            if let t = missions[m].targets.firstIndex(where: { $0.id == targetID }) { missions[m].targets[t].current = value }
        }
        save()
    }

    private func save() {
        do {
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(missions).write(to: url, options: [.atomic])
            saveError = nil
        } catch { saveError = "Couldn't save the missions: \(error.localizedDescription)" }
    }
}

/// Live readings for auto targets, from the app's own data. Falls back to the typed value.
@MainActor
struct MissionFacts {
    let store: TrackerStore
    private var engine: TrackerEngine { store.engine }
    private var last7: [String] { engine.days(from: engine.adding(-6, to: store.today), through: store.today) }

    var latestKg: Double? { store.bodyMeasurements.archive.records.max { $0.date < $1.date }?.kilograms }

    func value(_ t: MissionTarget) -> Double? { auto(t) ?? t.current }

    /// Whether the shown value comes from the app's data rather than a typed number.
    func isLive(_ t: MissionTarget) -> Bool { auto(t) != nil }

    private func auto(_ t: MissionTarget) -> Double? {
        let health = store.document.health
        switch t.auto {
        case "weight": return latestKg
        case "ffmi":
            let bf = store.missions.missions.flatMap(\.targets).first { $0.id == "a.bodyfat" }?.current
            guard let kg = latestKg, let bf else { return nil }
            return (Missions.ffmi(kg: kg, bodyFatPercent: bf) * 10).rounded() / 10
        case "sleep":
            let s = WeekFacts(store: store).sleep(last7)
            return s.known == 0 ? nil : Double(s.byOne)
        case "stress":
            let evening = last7.flatMap { health.records(.stress, on: $0, engine: engine) }
                .filter { engine.calendar.component(.hour, from: Date(timeIntervalSince1970: $0.start)) >= 18 }
            return evening.isEmpty ? nil : (evening.map(\.value).reduce(0, +) / Double(evening.count)).rounded()
        case "rhr":
            let r = last7.flatMap { health.records(.restingHeartRate, on: $0, engine: engine) }
            return r.isEmpty ? nil : (r.map(\.value).reduce(0, +) / Double(r.count)).rounded()
        case "steps":
            let s = last7.compactMap { health.steps(on: $0, engine: engine) }
            return s.isEmpty ? nil : (s.reduce(0, +) / Double(s.count)).rounded()
        case "protein":
            let days = last7.filter { store.document.meals.totals($0).kcal > 0 }
            return days.isEmpty ? nil : (days.map { store.document.meals.totals($0).protein }.reduce(0, +) / Double(days.count)).rounded()
        case "wardrobe":
            let owned = store.lifestyle.lifestyle.items(in: .wardrobe).filter { $0.tag == "Owned" && !$0.placeholder }
            return Double(owned.count)
        case "skills":
            let p = store.lifestyle.lifestyle.items(in: .skills).filter { !$0.placeholder }.compactMap(\.progress)
            return p.isEmpty ? nil : (p.reduce(0, +) / Double(p.count) * 100).rounded()
        default: return nil
        }
    }

    var summary: String { Missions.summary(store.missions.missions, value: value) }
}
