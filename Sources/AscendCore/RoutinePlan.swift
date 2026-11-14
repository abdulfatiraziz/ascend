import Foundation

// The Routine tab: your day on one dial. Everything here is read from things you already have
// (routine times, diet plan, medicine moments, the watch). It adds nothing to do.

public struct PlanEvent: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case meal, meds, windDown, bed }
    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    /// Minutes from the start of the day; times after midnight but before wake count past 1440.
    public var minute: Int
    public var endMinute: Int?
    public var done: Bool
}

public struct NightOnset: Equatable, Sendable {
    public var day: String
    /// Minutes from midnight; before midnight is negative (11:30 pm = -30).
    public var minute: Int
    public var start: Double
    public var end: Double
}

extension TrackerDocument {
    /// Puts a clock minute on the evening axis: after midnight and before wake counts as late tonight.
    public static func eveningMinute(_ minute: Int, wake: Int) -> Int { minute < wake ? minute + 1440 : minute }

    /// Today's plan in time order: meal slots, medicine moments, wind down and bed.
    public func dayPlan(on day: String, engine: TrackerEngine) -> [PlanEvent] {
        let wake = routine.wakeMinute
        var out: [PlanEvent] = []
        for (slot, logged) in planSlots(on: day, engine: engine) {
            let kcal = slot.kcal.map { " · \(Int($0)) kcal" } ?? ""
            out.append(PlanEvent(id: "meal-\(slot.id)", kind: .meal, title: slot.name,
                                 detail: slot.sweet ? "The planned one" + kcal : (slot.kcal.map { "\(Int($0)) kcal planned" } ?? "Planned"),
                                 minute: Self.eveningMinute(slot.startMinute, wake: wake),
                                 endMinute: Self.eveningMinute(slot.endMinute, wake: wake), done: logged))
        }
        for g in meds.moments(on: day, engine: engine) {
            out.append(PlanEvent(id: "meds-\(g.moment.rawValue)", kind: .meds, title: "\(g.moment.rawValue) meds", detail: g.shortNames,
                                 minute: Self.eveningMinute(g.minute, wake: wake), endMinute: nil, done: g.allTaken))
        }
        if routine.configured {
            out.append(PlanEvent(id: "wind", kind: .windDown, title: "Black tie hours", detail: "Lights low, screens down",
                                 minute: Self.eveningMinute(routine.windDownMinute, wake: wake), endMinute: Self.eveningMinute(routine.bedMinute, wake: wake), done: false))
            out.append(PlanEvent(id: "bed", kind: .bed, title: "Lights out", detail: "Mission 02 · Midnight",
                                 minute: Self.eveningMinute(routine.bedMinute, wake: wake), endMinute: nil, done: false))
        }
        let order: [PlanEvent.Kind: Int] = [.meal: 0, .meds: 1, .windDown: 2, .bed: 3]
        return out.sorted { ($0.minute, order[$0.kind]!) < ($1.minute, order[$1.kind]!) }
    }

    /// What's left of the plan from `now` (evening axis): the meal window you're in, then everything after.
    public func planAhead(on day: String, now: Int, engine: TrackerEngine) -> [PlanEvent] {
        dayPlan(on: day, engine: engine).filter { e in
            e.minute >= now || (e.kind == .meal && !e.done && (e.endMinute ?? e.minute) > now)
        }
    }

    /// When you fell asleep on the night ending on `day`: the start of that day's longest sleep.
    public func onset(endingOn day: String, engine: TrackerEngine) -> NightOnset? {
        guard let s = health.sleepSessions(on: day, engine: engine).first else { return nil }
        let d = Date(timeIntervalSince1970: s.start), c = engine.calendar
        var m = c.component(.hour, from: d) * 60 + c.component(.minute, from: d)
        if m >= 12 * 60 { m -= 1440 }
        return NightOnset(day: day, minute: m, start: s.start, end: s.end)
    }
}
