import Foundation

/// A quick log from the phone's Log screen that isn't an urge, meal, dose or check-in: a weigh-in or one gym set.
/// The ID is stable across retries, so a resend is not saved twice.
public struct PhoneLogEntry: Codable, Equatable, Sendable {
    public var id: String
    public var takenAt: Double
    /// "weight" or "set".
    public var type: String
    public var kilograms: Double?
    public var exerciseID: String?
    /// Which set of today's exercise this is, from 0. Sending the same index again replaces it.
    public var setIndex: Int?
    public var weight: Double?
    public var reps: Int?
    public init(id: String, takenAt: Double, type: String, kilograms: Double? = nil, exerciseID: String? = nil, setIndex: Int? = nil, weight: Double? = nil, reps: Int? = nil) {
        self.id = id; self.takenAt = takenAt; self.type = type; self.kilograms = kilograms
        self.exerciseID = exerciseID; self.setIndex = setIndex; self.weight = weight; self.reps = reps
    }
    public enum Checked: Equatable, Sendable {
        case weight(id: String, kilograms: Double, date: Date)
        case set(exerciseID: UUID, index: Int, set: TrainingSet, date: Date)
    }
    public func validated(now: Date = Date()) throws -> Checked {
        guard UUID(uuidString: id) != nil, takenAt.isFinite, takenAt >= 946684800, takenAt <= now.timeIntervalSince1970 + 300 else {
            throw ValidationError(message: "The phone sent an invalid log.")
        }
        let date = Date(timeIntervalSince1970: min(takenAt, now.timeIntervalSince1970))
        switch type {
        case "weight":
            guard let kg = kilograms, kg.isFinite, (20...300).contains(kg) else { throw ValidationError(message: "Enter a weight between 20 and 300 kg.") }
            return .weight(id: "manual-phone-" + id.lowercased(), kilograms: (kg * 100).rounded() / 100, date: date)
        case "set":
            guard let exerciseID = exerciseID.flatMap(UUID.init(uuidString:)), let index = setIndex, (0..<20).contains(index),
                  let weight, weight.isFinite, (0...500).contains(weight), let reps, (1...100).contains(reps) else {
                throw ValidationError(message: "The phone sent an invalid set.")
            }
            return .set(exerciseID: exerciseID, index: index, set: TrainingSet(weight: (weight * 100).rounded() / 100, reps: reps), date: date)
        default:
            throw ValidationError(message: "This version of Ascend doesn’t know that log type. Update the Mac app.")
        }
    }
}

extension BodyArchive {
    /// Adds a phone weigh-in as a manual reading. Returns nil when that reading is already saved.
    public func savingPhoneWeight(id: String, kilograms: Double, date: Date) throws -> Self? {
        try validate()
        guard id.hasPrefix("manual-") else { throw ValidationError(message: "Invalid phone weight ID.") }
        guard !records.contains(where: { $0.id == id }) else { return nil }
        let profile = records.first { !$0.isManual }?.userID ?? "local-manual"
        let row = BodyMeasurement(fields: ["id": .text(id), "userId": .text(profile), "createdAt": .number((date.timeIntervalSince1970 * 1000).rounded()),
                                           "measuredWeight": .number(kilograms), "isManual": .bool(true), "note": .text("from phone")])
        return try merging([row])
    }
    /// The newest reading, scale or manual.
    public var latest: BodyMeasurement? { records.max { $0.date < $1.date } }
}

/// One set, as the phone shows it.
public struct PhoneSet: Codable, Equatable, Sendable {
    public var weight: Double
    public var reps: Int
}
public struct PhoneWorkoutExercise: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var sets: Int
    public var minReps: Int
    public var maxReps: Int
    public var timed: Bool
    /// The most recent earlier session's sets, so the phone can offer "same again".
    public var last: [PhoneSet]
    public var today: [PhoneSet]
    /// The plan's starting weight, offered before the first logged session (assist weight when `assisted`).
    public var start: Double?
    public var assisted: Bool?
}
/// Today's planned session from the Body tab.
public struct PhoneWorkout: Codable, Equatable, Sendable {
    public var name: String
    /// "strength" or "cardio".
    public var kind: String
    public var minutes: Double?
    /// Cardio only, e.g. "Incline treadmill · incline 15 · speed 3".
    public var detail: String?
    public var exercises: [PhoneWorkoutExercise]
}

extension TrainingArchive {
    public func phoneWorkout(now: Date, calendar: Calendar) -> PhoneWorkout? {
        guard let session = today(now, calendar: calendar), session.kind != .rest else { return nil }
        let start = calendar.startOfDay(for: now)
        let list: [PhoneWorkoutExercise] = session.exercises.compactMap { id in
            guard let e = exercises.first(where: { $0.id == id }) else { return nil }
            let mine = logs.filter { $0.exerciseID == id }
            let todays = mine.filter { calendar.isDate($0.date, inSameDayAs: now) }.flatMap(\.sets)
            let earlier = mine.filter { $0.date < start }.max { $0.date < $1.date }?.sets ?? []
            return PhoneWorkoutExercise(id: id.uuidString, name: e.name, sets: e.sets, minReps: e.minReps, maxReps: e.maxReps, timed: e.timed,
                                        last: earlier.map { PhoneSet(weight: $0.weight, reps: $0.reps) },
                                        today: todays.map { PhoneSet(weight: $0.weight, reps: $0.reps) },
                                        start: e.startingWeight > 0 ? e.startingWeight : nil, assisted: e.assisted ? true : nil)
        }
        func n(_ x: Double) -> String { x == x.rounded() ? String(Int(x)) : String(format: "%.1f", x) }
        let detail = session.kind == .cardio
            ? ([session.cardioType] + (session.incline > 0 ? ["incline \(n(session.incline))"] : []) + (session.speed > 0 ? ["speed \(n(session.speed))"] : [])).joined(separator: " · ")
            : nil
        return PhoneWorkout(name: session.name, kind: session.kind.rawValue, minutes: session.kind == .cardio ? session.minutes : nil, detail: detail, exercises: list)
    }
    /// Saves one set from the phone into today's log for that exercise. The same index again replaces that set.
    public mutating func applyPhoneSet(exerciseID: UUID, index: Int, set: TrainingSet, date: Date, calendar: Calendar) throws {
        guard let exercise = exercises.first(where: { $0.id == exerciseID }) else {
            throw ValidationError(message: "That exercise isn’t in your training plan any more.")
        }
        if let i = logs.firstIndex(where: { $0.exerciseID == exerciseID && calendar.isDate($0.date, inSameDayAs: date) }) {
            if index < logs[i].sets.count { logs[i].sets[index] = set } else { logs[i].sets.append(set) }
        } else {
            logs.append(LiftLog(exerciseID: exerciseID, date: date, sets: [set], muscles: exercise.muscles, priorityTags: exercise.priorityTags))
        }
        try validate()
    }
}

/// The one thing the phone's Log screen puts first: the current or next diet slot, or the next routine item.
public struct PhoneNow: Codable, Equatable, Sendable {
    public var kicker: String
    public var title: String
    public var detail: String
    /// "meal" when a photo is the natural way to log it.
    public var kind: String
}

public enum Clock12 {
    /// "4:00 pm", "12:30 am".
    public static func label(_ minute: Int) -> String {
        let m = ((minute % 1440) + 1440) % 1440, h = m / 60
        return "\(h % 12 == 0 ? 12 : h % 12):\(String(format: "%02d", m % 60)) \(h < 12 ? "am" : "pm")"
    }
}

extension TrackerDocument {
    public func phoneNow(at now: Date) -> PhoneNow? {
        let engine = TrackerEngine(document: self)
        let today = engine.key(now), minute = engine.minute(now)
        var slot: (DietSlot, current: Bool)?
        if let diet, diet.effectiveDay <= today {
            let slots = diet.slots.sorted { $0.startMinute < $1.startMinute }
            if let s = slots.first(where: { $0.contains(minute) }) { slot = (s, true) }
            else if let s = slots.first(where: { $0.startMinute > minute }) { slot = (s, false) }
        }
        func dietNow(_ s: DietSlot, current: Bool) -> PhoneNow {
            let numbers = [s.kcal.map { "~\(Int($0)) kcal" }, s.protein.map { "\(Int($0)) g protein" }].compactMap { $0 }.joined(separator: " · ")
            return PhoneNow(kicker: current ? "Now · \(s.name)" : "Next · \(s.name) at \(Clock12.label(s.startMinute))",
                            title: s.portion.isEmpty ? s.name : s.portion, detail: numbers, kind: "meal")
        }
        if let slot, slot.current { return dietNow(slot.0, current: true) }
        let event = engine.nextRoutineEvent(after: now).flatMap { engine.key($0.date) == today ? $0 : nil }
        switch (slot, event) {
        case let (s?, e?) where engine.minute(e.date) < s.0.startMinute:
            return PhoneNow(kicker: "Next · \(Clock12.label(engine.minute(e.date)))", title: e.title, detail: "From your routine", kind: "routine")
        case let (s?, _): return dietNow(s.0, current: false)
        case let (nil, e?): return PhoneNow(kicker: "Next · \(Clock12.label(engine.minute(e.date)))", title: e.title, detail: "From your routine", kind: "routine")
        default: return nil
        }
    }
    /// Urges acted on today, the daily average over the 7 days before today, and spot visits left unanswered in those 8 days.
    public func urgeCounts(at now: Date) -> (actedToday: Int, actedWeekAverage: Double?, unansweredVisits: Int) {
        let engine = TrackerEngine(document: self)
        let today = engine.key(now)
        let acted = urgeLogs.filter { $0.outcome == .acted }
        let days = Set((1...7).map { engine.adding(-$0, to: today) })
        let week = acted.filter { days.contains(engine.key($0.timestamp)) }.count
        let started = acted.map(\.timestamp).min().map(engine.key)
        let visits = urgeLogs.filter { $0.spot != nil && $0.outcome == .unrecorded && (days.contains(engine.key($0.timestamp)) || engine.key($0.timestamp) == today) }.count
        return (acted.filter { engine.key($0.timestamp) == today }.count, started.map { $0 < today } == true ? Double(week) / 7 : nil, visits)
    }
}

extension UrgeLog {
    /// Fills an unanswered visit with the answer the phone sent later, keeping anything already recorded.
    public mutating func upgrade(from later: UrgeLog) {
        outcome = later.outcome
        intensity = intensity ?? later.intensity
        if trigger == nil { trigger = later.trigger; customTrigger = later.customTrigger }
        if note.isEmpty { note = later.note }
        caughtEarly = caughtEarly ?? later.caughtEarly; usedAnchor = usedAnchor ?? later.usedAnchor
        spot = spot ?? later.spot
    }
}

/// A place the phone watches for urge check-ins. Kept in spots.json beside tracker.json, sent only to the paired phone.
public struct UrgeSpot: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public init(id: String = UUID().uuidString, name: String, latitude: Double, longitude: Double) {
        self.id = id; self.name = name; self.latitude = latitude; self.longitude = longitude
    }
}
public struct SpotArchive: Codable, Equatable, Sendable {
    public var version = 1
    public var spots: [UrgeSpot] = []
    public init(spots: [UrgeSpot] = []) { self.spots = spots }
    public func validate() throws {
        guard version == 1, spots.count <= 50, Set(spots.map(\.id)).count == spots.count,
              spots.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 64 && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.name.count <= 40
                  && $0.latitude.isFinite && (-90...90).contains($0.latitude) && $0.longitude.isFinite && (-180...180).contains($0.longitude) }) else {
            throw ValidationError(message: "Invalid spots file. It was left unchanged.")
        }
    }
    /// The saved spots, or none when the file is missing or invalid, so the phone reply never fails over it.
    public static func read(_ url: URL) -> SpotArchive {
        guard let data = try? Data(contentsOf: url), let a = try? JSONDecoder().decode(SpotArchive.self, from: data), (try? a.validate()) != nil else { return SpotArchive() }
        return a
    }
}
