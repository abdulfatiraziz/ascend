import Foundation

/// Claude's rough nutrition estimate for one meal photo.
public struct MealEstimate: Codable, Equatable, Sendable {
    public var name: String
    public var items: [String]
    public var kcal: Double
    public var kcalLow: Double
    public var kcalHigh: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var confidence: String
    public var notes: String
    public init(name: String, items: [String] = [], kcal: Double, kcalLow: Double, kcalHigh: Double, protein: Double, carbs: Double, fat: Double, confidence: String = "medium", notes: String = "") {
        self.name = name; self.items = items; self.kcal = kcal; self.kcalLow = kcalLow; self.kcalHigh = kcalHigh
        self.protein = protein; self.carbs = carbs; self.fat = fat; self.confidence = confidence; self.notes = notes
    }
    /// Rejects impossible values and keeps the range around the central estimate.
    public func validated() throws -> MealEstimate {
        let values = [kcal, kcalLow, kcalHigh, protein, carbs, fat]
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }), kcal <= 10_000, kcalHigh <= 15_000, [protein, carbs, fat].allSatisfy({ $0 <= 1_000 }) else {
            throw ValidationError(message: "Claude returned an impossible nutrition estimate.")
        }
        var result = self
        result.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)); if result.name.isEmpty { result.name = "Meal" }
        result.items = Array(items.prefix(20)).map { String($0.prefix(120)) }
        result.kcalLow = min(kcalLow, kcal); result.kcalHigh = max(kcalHigh, kcal)
        result.confidence = ["low", "medium", "high"].contains(confidence.lowercased()) ? confidence.lowercased() : "medium"
        result.notes = String(notes.prefix(600))
        return result
    }
}
public struct MealEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var takenAt: Double
    public var day: String
    public var note: String
    /// File name in the Meals folder beside tracker.json.
    public var photo: String
    /// Further photos of the same meal, such as each step of a plate built up on a kitchen scale.
    public var morePhotos: [String]?
    /// How many photos the phone said this meal has; the estimate waits until they've all arrived.
    public var expectedPhotos: Int?
    /// "phone" or "mac".
    public var source: String
    public var estimate: MealEstimate?
    public var kcal: Double?
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?
    public var confirmed: Bool
    public var error: String?
    public init(id: UUID = UUID(), takenAt: Double, day: String, note: String = "", photo: String, source: String) {
        self.id = id; self.takenAt = takenAt; self.day = day; self.note = note; self.photo = photo; self.source = source
        confirmed = false
    }
    /// Every photo of the meal in the order taken. Photos of one meal are named `<meal id>-<part>`, so they sort by part.
    public var photos: [String] { morePhotos.map { ([photo] + $0).sorted() } ?? [photo] }
    /// Photos still on their way from the phone.
    public var missingPhotos: Int { max(0, (expectedPhotos ?? 0) - photos.count) }
    /// Values the user accepted, falling back to the estimate.
    public var values: (kcal: Double, protein: Double, carbs: Double, fat: Double) {
        (kcal ?? estimate?.kcal ?? 0, protein ?? estimate?.protein ?? 0, carbs ?? estimate?.carbs ?? 0, fat ?? estimate?.fat ?? 0)
    }
}
public struct MealTotals: Equatable, Sendable {
    public var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0
    public var confirmed = 0, pending = 0
}
public struct MealLog: Codable, Equatable, Sendable {
    public var entries: [MealEntry] = []
    /// Days whose Calorie/Protein check-ins were written from meals, so removing the last meal can clear them.
    public var filledDays: Set<String> = []
    public static let maxPhotos = 10
    public init() {}
    /// File name for one photo of a multi-photo meal.
    public static func photoName(meal: UUID, part: Int, ext: String) -> String { String(format: "%@-%02d.%@", meal.uuidString.lowercased(), part, ext) }
    public func validate() throws {
        guard entries.count <= 20_000, Set(entries.map(\.id)).count == entries.count, filledDays.count <= 20_000 else {
            throw ValidationError(message: "Invalid meal log.")
        }
        for e in entries {
            let numbers = [e.kcal, e.protein, e.carbs, e.fat].compactMap { $0 }
            guard e.takenAt.isFinite, (946684800...7289654399).contains(e.takenAt), e.note.count <= 500,
                  e.photos.count <= Self.maxPhotos, e.photos.allSatisfy({ !$0.isEmpty && $0.count <= 100 && !$0.contains("/") }),
                  (1...Self.maxPhotos).contains(e.expectedPhotos ?? 1), ["phone", "mac"].contains(e.source), numbers.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 10_000 }),
                  (e.error?.count ?? 0) <= 600 else { throw ValidationError(message: "Invalid meal entry.") }
            if let estimate = e.estimate { _ = try estimate.validated() }
        }
    }
    public func on(_ day: String) -> [MealEntry] { entries.filter { $0.day == day }.sorted { $0.takenAt < $1.takenAt } }
    public func totals(_ day: String) -> MealTotals {
        var t = MealTotals()
        for e in on(day) {
            guard e.confirmed else { t.pending += 1; continue }
            let v = e.values
            t.kcal += v.kcal; t.protein += v.protein; t.carbs += v.carbs; t.fat += v.fat; t.confirmed += 1
        }
        return t
    }
}
extension TrackerDocument {
    /// The active metric habits that confirmed meals fill: a kcal habit and a protein habit measured in grams.
    public var mealHabits: (calories: Habit?, protein: Habit?) {
        let metrics = habits.filter { $0.archivedDay == nil && $0.kind == .metric }
        return (metrics.first { $0.latest.target?.unit.lowercased() == "kcal" },
                metrics.first { $0.latest.target?.unit.lowercased() == "g" && $0.latest.title.localizedCaseInsensitiveContains("protein") })
    }
    /// Sets that day's Calorie and Protein check-ins to the confirmed meal totals. When no confirmed meals remain,
    /// clears only values that meals wrote earlier, never a number typed by hand.
    public mutating func applyMealTotals(on day: String, today: String) {
        let engine = TrackerEngine(document: self)
        guard day <= today, engine.date(day) != nil, !restDays.contains(day) else { return }
        let totals = meals.totals(day), targets = mealHabits
        for (habit, value) in [(targets.calories, totals.kcal), (targets.protein, totals.protein)] {
            guard let habit, engine.isDue(habit, on: day) else { continue }
            if totals.confirmed > 0 { setEntry(CheckIn(habitID: habit.id, day: day, value: value.rounded())) }
            else if meals.filledDays.contains(day) { checkIns.removeAll { $0.habitID == habit.id && $0.day == day } }
        }
        if totals.confirmed > 0 { meals.filledDays.insert(day) } else { meals.filledDays.remove(day) }
    }
}
