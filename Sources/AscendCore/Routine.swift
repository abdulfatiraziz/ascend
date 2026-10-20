import Foundation

public struct RoutinePreferences: Codable, Equatable, Sendable {
    public var configured = false
    public var wakeMinute = 7 * 60
    public var bedMinute = 23 * 60
    public var windDownMinutes = 120
    public var morningMinutes = 180
    public init() {}
    public var awakeMinutes: Int { Self.forward(from: wakeMinute, to: bedMinute) }
    public var windDownMinute: Int { (bedMinute - windDownMinutes + 1440) % 1440 }
    public var morningEndMinute: Int { (wakeMinute + morningMinutes) % 1440 }
    public static func forward(from start: Int, to end: Int) -> Int { (end - start + 1440) % 1440 }
    public func validate() throws {
        guard (0..<1440).contains(wakeMinute), (0..<1440).contains(bedMinute),
              (15...360).contains(morningMinutes), (15...360).contains(windDownMinutes),
              awakeMinutes > morningMinutes + windDownMinutes, awakeMinutes <= 22 * 60 else {
            throw ValidationError(message: "Choose different wake and bed times, with room for morning, daytime and wind-down. Sleep must be at least two hours.")
        }
    }
    public func phase(at minute: Int) -> RoutinePhase {
        let elapsed = Self.forward(from: wakeMinute, to: minute)
        if elapsed >= awakeMinutes { return .sleep }
        if elapsed < morningMinutes { return .morning }
        if elapsed >= awakeMinutes - windDownMinutes { return .windDown }
        return .daytime
    }
}
public enum RoutinePhase: String, CaseIterable, Sendable {
    case sleep = "Sleep", morning = "Morning", daytime = "Daytime", windDown = "Wind-down"
}
public struct RoutineEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let date: Date
    public let title: String
    public let habitID: UUID?
    public let isAnchor: Bool
}
public extension TrackerEngine {
    func minute(_ date: Date) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
    func time(on day: String, minute: Int) -> Date? {
        guard (0..<1440).contains(minute), let date = date(day) else { return nil }
        // Calendar resolves missing spring-forward times and chooses the first repeated fall-back time.
        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: date)
    }
    func routineEvents(on day: String) -> [RoutineEvent] {
        guard document.routine.configured else { return [] }
        var events: [RoutineEvent] = []
        for (name, minute) in [("Wake up", document.routine.wakeMinute), ("Wind down", document.routine.windDownMinute), ("Sleep", document.routine.bedMinute)] {
            if let date = time(on: day, minute: minute) { events.append(RoutineEvent(id: "\(day)-\(name)", date: date, title: name, habitID: nil, isAnchor: true)) }
        }
        for h in due(on: day, includeMilestones: true) where !document.restDays.contains(day) || h.kind == .milestone {
            if let minute = h.revision(on: day)?.scheduledMinute, let date = time(on: day, minute: minute) {
                events.append(RoutineEvent(id: "\(day)-\(h.id)", date: date, title: h.revision(on: day)!.title, habitID: h.id, isAnchor: false))
            }
        }
        return events.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
    func nextRoutineEvent(after now: Date) -> RoutineEvent? {
        let today = key(now)
        return [today, adding(1, to: today)].flatMap { routineEvents(on: $0) }.filter { event in
            guard event.date > now else { return false }
            if let id = event.habitID, let habit = document.habits.first(where: { $0.id == id }) {
                return !completed(habit, on: key(event.date))
            }
            return true
        }.min { $0.date < $1.date }
    }
}
public enum UrgeTrigger: String, Codable, CaseIterable, Sendable {
    case stress = "Stress", coffee = "Coffee", meal = "After a meal", social = "Social", boredom = "Boredom", other = "Other"
}
public enum UrgeOutcome: String, Codable, CaseIterable, Sendable {
    case unrecorded = "Not recorded", passed = "Let it pass", acted = "Acted on it"
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let value = try c.decode(String.self)
        switch value {
        case "Passed without smoking": self = .passed
        case "Smoked": self = .acted
        default:
            guard let outcome = Self(rawValue: value) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid urge outcome.") }
            self = outcome
        }
    }
}
public struct UrgeLog: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var intensity: Int?
    public var trigger: UrgeTrigger?
    public var customTrigger: String?
    public var outcome: UrgeOutcome
    public var note: String
    public var category: String?
    public init(id: UUID = UUID(), timestamp: Date = Date(), intensity: Int? = nil,
                trigger: UrgeTrigger? = nil, outcome: UrgeOutcome = .unrecorded, note: String = "", category: String? = nil, customTrigger: String? = nil) {
        self.id = id; self.timestamp = timestamp; self.intensity = intensity
        self.trigger = trigger; self.outcome = outcome; self.note = note; self.category = category
        let custom = customTrigger?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.customTrigger = trigger == .other && custom?.isEmpty == false ? custom : nil
    }
    public var triggerLabel: String? { trigger == .other ? (customTrigger ?? trigger?.rawValue) : trigger?.rawValue }
}
