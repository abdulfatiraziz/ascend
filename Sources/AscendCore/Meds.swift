import Foundation

public enum MedFrequency: String, Codable, CaseIterable, Sendable {
    case daily, weekdays, everyNDays, asNeeded
    public var label: String {
        switch self { case .daily: "Every day"; case .weekdays: "Certain days"; case .everyNDays: "Every few days"; case .asNeeded: "Only when needed" }
    }
}
public enum MedFood: String, Codable, CaseIterable, Sendable {
    case any, before, with, after, empty
    public var label: String {
        switch self { case .any: "Any time"; case .before: "Before food"; case .with: "With food"; case .after: "After food"; case .empty: "Empty stomach" }
    }
}
/// When to take a medicine, as the doctor prescribed. Ascend never sets or changes this on its own.
public struct MedSchedule: Codable, Equatable, Sendable {
    public var frequency: MedFrequency = .daily
    /// 1 = Sunday … 7 = Saturday, for `.weekdays`.
    public var weekdays: [Int] = []
    /// For `.everyNDays`, counted from `start`.
    public var interval = 2
    /// Local minutes after midnight, 1–4 doses a day.
    public var times: [Int] = [9 * 60]
    public var amount = ""
    public var food: MedFood = .any
    public var start: String
    public var end: String?
    public init(start: String) { self.start = start }
    public func validate(engine: TrackerEngine) throws {
        guard engine.date(start) != nil, end.map({ engine.date($0) != nil && $0 >= start }) ?? true,
              frequency == .asNeeded || (1...4).contains(times.count), times.allSatisfy({ (0..<1440).contains($0) }), Set(times).count == times.count,
              frequency != .weekdays || (!weekdays.isEmpty && weekdays.allSatisfy({ (1...7).contains($0) })),
              frequency != .everyNDays || (2...60).contains(interval), amount.count <= 60 else {
            throw ValidationError(message: "Check the medicine schedule: 1–4 times a day, at least one weekday, every 2–60 days, and an end date after the start.")
        }
    }
    public func isDue(on day: String, engine: TrackerEngine) -> Bool {
        guard day >= start, end.map({ day <= $0 }) ?? true, let date = engine.date(day) else { return false }
        switch frequency {
        case .daily: return true
        case .weekdays: return weekdays.contains(engine.calendar.component(.weekday, from: date))
        case .everyNDays: return (engine.days(from: start, through: day).count - 1) % interval == 0
        case .asNeeded: return false
        }
    }
    public var summary: String {
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let how: String
        switch frequency {
        case .daily: how = "Daily"
        case .weekdays: how = weekdays.sorted().map { names[$0] }.joined(separator: ", ")
        case .everyNDays: how = "Every \(interval) days"
        case .asNeeded: return ["As needed", amount, food == .any ? "" : food.label.lowercased()].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return [how, times.sorted().map(clockTime).joined(separator: ", "), amount, food == .any ? "" : food.label.lowercased()].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
public struct Medicine: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name = ""
    public var ingredients: [String] = []
    public var strength = ""
    public var form = ""
    /// For example "Hair loss · DHT blocker".
    public var category = ""
    /// What it's for, in the user's or label's words.
    public var purpose = ""
    public var notes = ""
    /// Claude's remark about what it read and how sure it is.
    public var reading = ""
    public var confidence = ""
    /// File names in the Meds folder, one per side photographed.
    public var photos: [String] = []
    public var schedule: MedSchedule?
    public var confirmed = false
    public var archived = false
    public var error: String?
    public init(id: UUID = UUID(), name: String = "", photos: [String] = []) { self.id = id; self.name = name; self.photos = photos }
    public var title: String {
        guard !name.isEmpty else { return "Unnamed medicine" }
        return strength.isEmpty || name.localizedCaseInsensitiveContains(strength) ? name : "\(name) \(strength)"
    }
    var active: Bool { confirmed && !archived }
}
/// A medicine photo that hasn't been sorted onto a card yet, or that Claude couldn't place.
public struct MedPhoto: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var photo: String
    public var takenAt: Double
    public var batch: UUID
    /// True once sorting finished without placing this photo.
    public var unsure = false
    public init(photo: String, takenAt: Double, batch: UUID) { self.photo = photo; self.takenAt = takenAt; self.batch = batch }
}
/// Photos taken together in one go. Claude sorts a batch once every photo has arrived, or when asked to.
public struct MedBatch: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var expected: Int
    public var source: String
    public var error: String?
    public init(id: UUID, expected: Int, source: String) { self.id = id; self.expected = expected; self.source = source }
}
public struct MedDose: Codable, Equatable, Sendable {
    public var medID: UUID
    public var day: String
    public var minute: Int
    public var takenAt: Double
    public var source: String
    public init(medID: UUID, day: String, minute: Int, takenAt: Double, source: String) {
        self.medID = medID; self.day = day; self.minute = minute; self.takenAt = takenAt; self.source = source
    }
}
/// One scheduled dose on a given day.
public struct MedSlot: Equatable, Sendable, Identifiable {
    public var medicine: Medicine
    public var day: String
    public var minute: Int
    public var taken: MedDose?
    public var id: String { "\(medicine.id.uuidString)|\(day)|\(minute)" }
}
public struct MedCabinet: Codable, Equatable, Sendable {
    public var medicines: [Medicine] = []
    public var inbox: [MedPhoto] = []
    public var batches: [MedBatch] = []
    public var doses: [MedDose] = []
    /// Days whose meds habit was ticked from doses, so untaking a dose can clear it.
    public var filledDays: Set<String> = []
    public init() {}
    public func validate(engine: TrackerEngine) throws {
        let files = medicines.flatMap(\.photos) + inbox.map(\.photo)
        guard medicines.count <= 500, inbox.count <= 500, batches.count <= 200, doses.count <= 100_000, filledDays.count <= 20_000,
              Set(medicines.map(\.id)).count == medicines.count, Set(files).count == files.count,
              files.allSatisfy({ !$0.isEmpty && $0.count <= 100 && !$0.contains("/") }),
              medicines.allSatisfy({ $0.photos.count <= 20 && [$0.name, $0.strength, $0.form, $0.confidence].allSatisfy { $0.count <= 120 }
                  && $0.category.count <= 120 && $0.purpose.count <= 300 && $0.notes.count <= 1000 && $0.reading.count <= 1000
                  && $0.ingredients.count <= 20 && ($0.error?.count ?? 0) <= 600 }),
              batches.allSatisfy({ (1...40).contains($0.expected) && ["phone", "mac"].contains($0.source) }),
              doses.allSatisfy({ $0.takenAt.isFinite && (0..<1440).contains($0.minute) && engine.date($0.day) != nil }) else {
            throw ValidationError(message: "Invalid medicine list.")
        }
        for medicine in medicines { try medicine.schedule?.validate(engine: engine) }
    }
    public func batchPhotos(_ batch: UUID) -> [MedPhoto] { inbox.filter { $0.batch == batch && !$0.unsure }.sorted { $0.takenAt < $1.takenAt } }
    public var unsure: [MedPhoto] { inbox.filter(\.unsure) }
    /// A batch is ready to sort once all its photos are here.
    public func ready(_ batch: MedBatch) -> Bool { batch.error == nil && batchPhotos(batch.id).count >= batch.expected }
    public func dose(_ medID: UUID, day: String, minute: Int) -> MedDose? {
        doses.first { $0.medID == medID && $0.day == day && $0.minute == minute }
    }
    public func slots(on day: String, engine: TrackerEngine) -> [MedSlot] {
        medicines.filter(\.active).flatMap { medicine -> [MedSlot] in
            guard let schedule = medicine.schedule, schedule.isDue(on: day, engine: engine) else { return [] }
            return schedule.times.map { MedSlot(medicine: medicine, day: day, minute: $0, taken: dose(medicine.id, day: day, minute: $0)) }
        }.sorted { $0.minute == $1.minute ? $0.medicine.name < $1.medicine.name : $0.minute < $1.minute }
    }
    /// Doses taken vs missed over `days` days ending yesterday, plus today's progress.
    public func adherence(today: String, days: Int, engine: TrackerEngine) -> (taken: Int, missed: Int) {
        guard days > 0 else { return (0, 0) }
        var taken = 0, missed = 0
        for day in engine.days(from: engine.adding(-days, to: today), through: engine.adding(-1, to: today)) {
            for slot in slots(on: day, engine: engine) { if slot.taken != nil { taken += 1 } else { missed += 1 } }
        }
        return (taken, missed)
    }
}

/// Claude's reading of a batch: which photos show which medicine.
public struct MedReading: Codable, Equatable, Sendable {
    public var name: String
    public var ingredients: [String]
    public var strength: String
    public var form: String
    public var category: String
    public var purpose: String
    public var confidence: String
    public var notes: String
    /// 1-based photo numbers.
    public var photos: [Int]
    public init(name: String, ingredients: [String] = [], strength: String = "", form: String = "", category: String = "", purpose: String = "", confidence: String = "medium", notes: String = "", photos: [Int]) {
        self.name = name; self.ingredients = ingredients; self.strength = strength; self.form = form; self.category = category
        self.purpose = purpose; self.confidence = confidence; self.notes = notes; self.photos = photos
    }
}
public struct MedSorting: Codable, Equatable, Sendable {
    public var medicines: [MedReading]
    public var unsure: [Int]
    public init(medicines: [MedReading], unsure: [Int] = []) { self.medicines = medicines; self.unsure = unsure }
    /// Keeps each photo on at most one medicine, drops out-of-range numbers and medicines left without photos,
    /// and puts every unplaced photo in `unsure`.
    public func validated(photoCount: Int) -> MedSorting {
        var used = Set<Int>()
        var result: [MedReading] = []
        for var reading in medicines.prefix(40) {
            reading.photos = reading.photos.filter { (1...photoCount).contains($0) && used.insert($0).inserted }
            guard !reading.photos.isEmpty else { continue }
            reading.name = String(reading.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
            reading.ingredients = Array(reading.ingredients.prefix(20)).map { String($0.prefix(120)) }
            reading.strength = String(reading.strength.prefix(120)); reading.form = String(reading.form.prefix(120))
            reading.category = String(reading.category.prefix(120)); reading.purpose = String(reading.purpose.prefix(300))
            reading.confidence = ["low", "medium", "high"].contains(reading.confidence.lowercased()) ? reading.confidence.lowercased() : "medium"
            reading.notes = String(reading.notes.prefix(1000))
            result.append(reading)
        }
        return MedSorting(medicines: result, unsure: (1...max(photoCount, 1)).filter { $0 <= photoCount && !used.contains($0) })
    }
}

extension Medicine {
    /// Fills the label fields from Claude's reading; schedule, notes and photos stay as they are.
    public mutating func apply(_ label: MedReading) {
        name = label.name; ingredients = label.ingredients; strength = label.strength; form = label.form
        category = label.category; purpose = label.purpose; confidence = label.confidence; reading = label.notes
        error = nil
    }
}

/// A dose sent to the phone so it can list today's medicines and set reminders without its own schedule logic.
public struct PhoneMedDose: Codable, Equatable, Sendable {
    public var medID: String
    public var name: String
    public var detail: String
    public var day: String
    public var minute: Int
    public var at: Double
    public var taken: Bool
    public init(medID: String, name: String, detail: String, day: String, minute: Int, at: Double, taken: Bool) {
        self.medID = medID; self.name = name; self.detail = detail; self.day = day; self.minute = minute; self.at = at; self.taken = taken
    }
}
/// A Taken (or undo) tap from the phone. The ID is stable across retries.
public struct PhoneDose: Codable, Equatable, Sendable {
    public var id: String
    public var medID: String
    public var day: String
    public var minute: Int
    public var takenAt: Double
    public var taken: Bool
    public init(id: String, medID: String, day: String, minute: Int, takenAt: Double, taken: Bool) {
        self.id = id; self.medID = medID; self.day = day; self.minute = minute; self.takenAt = takenAt; self.taken = taken
    }
}
/// One photo of a phone batch.
public struct PhoneMedPhoto: Codable, Equatable, Sendable {
    public var id: String
    public var batch: String
    public var batchSize: Int
    public var takenAt: Double
    public var mediaType: String
    public var image: String
    public init(id: String, batch: String, batchSize: Int, takenAt: Double, mediaType: String = "image/jpeg", image: String) {
        self.id = id; self.batch = batch; self.batchSize = batchSize; self.takenAt = takenAt; self.mediaType = mediaType; self.image = image
    }
    public func validated(now: Date = Date()) throws -> (id: UUID, batch: UUID, data: Data) {
        guard let uuid = UUID(uuidString: id), let batchID = UUID(uuidString: batch), (1...40).contains(batchSize),
              takenAt.isFinite, takenAt >= 946684800, takenAt <= now.timeIntervalSince1970 + 300, ["image/jpeg", "image/png"].contains(mediaType),
              let data = Data(base64Encoded: image), !data.isEmpty, data.count <= 8_000_000 else {
            throw ValidationError(message: "The phone sent an invalid medicine photo.")
        }
        return (uuid, batchID, data)
    }
}

extension TrackerDocument {
    /// The active check habit that taking every scheduled dose fills, such as "Take medication".
    public var medHabit: Habit? {
        habits.first { $0.archivedDay == nil && $0.kind == .check && $0.latest.title.range(of: #"\bmed(s|icine|icines|ication|ications)?\b"#, options: [.regularExpression, .caseInsensitive]) != nil }
    }
    /// Ticks the meds habit when every scheduled dose that day is taken. Clears only a tick it wrote, never one made by hand.
    public mutating func applyMedDoses(on day: String, today: String) {
        let engine = TrackerEngine(document: self)
        guard day <= today, engine.date(day) != nil, !restDays.contains(day), let habit = medHabit, engine.isDue(habit, on: day) else { return }
        let slots = meds.slots(on: day, engine: engine)
        let complete = !slots.isEmpty && slots.allSatisfy { $0.taken != nil }
        let current = engine.entry(for: habit, day: day)
        if complete {
            guard current == nil || meds.filledDays.contains(day) else { return }
            setEntry(CheckIn(habitID: habit.id, day: day, completed: true)); meds.filledDays.insert(day)
        } else if meds.filledDays.contains(day) {
            if current?.completed == true { checkIns.removeAll { $0.habitID == habit.id && $0.day == day } }
            meds.filledDays.remove(day)
        }
    }
    /// Marks a scheduled dose taken or not taken and updates the meds habit for that day.
    public mutating func setDose(_ medID: UUID, day: String, minute: Int, taken: Bool, at: Date, source: String, today: String) throws {
        let engine = TrackerEngine(document: self)
        guard day <= today, meds.slots(on: day, engine: engine).contains(where: { $0.medicine.id == medID && $0.minute == minute }) else {
            throw ValidationError(message: "That dose isn’t scheduled for \(day).")
        }
        meds.doses.removeAll { $0.medID == medID && $0.day == day && $0.minute == minute }
        if taken { meds.doses.append(MedDose(medID: medID, day: day, minute: minute, takenAt: at.timeIntervalSince1970, source: source)) }
        applyMedDoses(on: day, today: today)
    }
    /// Doses from today through the next `days` days, for the phone's list and reminders.
    public func phoneMedDoses(today: String, days: Int = 14) -> [PhoneMedDose] {
        let engine = TrackerEngine(document: self)
        return engine.days(from: today, through: engine.adding(days - 1, to: today)).flatMap { day in
            meds.slots(on: day, engine: engine).compactMap { slot -> PhoneMedDose? in
                guard let at = engine.time(on: day, minute: slot.minute) else { return nil }
                let s = slot.medicine.schedule
                let detail = [slot.medicine.strength, s?.amount ?? "", s.map { $0.food == .any ? "" : $0.food.label.lowercased() } ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                return PhoneMedDose(medID: slot.medicine.id.uuidString, name: slot.medicine.name.isEmpty ? "Medicine" : slot.medicine.name,
                                    detail: detail, day: day, minute: slot.minute, at: at.timeIntervalSince1970, taken: slot.taken != nil)
            }
        }
    }
}
