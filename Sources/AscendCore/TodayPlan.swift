import Foundation

// The Today screen splits habits into the ones you tap and the ones Ascend fills itself.

extension TrackerDocument {
    /// Habits that fill themselves: from the watch, meals, medicine taps or screen time. They show as glance lines, not to-dos.
    public var autoHabitIDs: Set<UUID> {
        let meal = mealHabits, health = healthHabits
        return Set([medHabit, gymHabit, windDownHabit, sweetsHabit, health.sleep, health.steps, meal.calories, meal.protein].compactMap { $0?.id })
    }

    /// Diet plan slots in time order with whether a meal already covers each one that day
    /// (a confirmed meal noted with the slot's name, or one eaten inside its window).
    public func planSlots(on day: String, engine: TrackerEngine) -> [(slot: DietSlot, logged: Bool)] {
        guard let diet else { return [] }
        let meals = self.meals.on(day).filter(\.confirmed)
        let cal = engine.calendar
        var used = Set<UUID>()
        return diet.slots.sorted { $0.startMinute < $1.startMinute }.map { slot in
            let hit = meals.first { m in
                guard !used.contains(m.id) else { return false }
                if m.note.lowercased().hasPrefix(slot.name.lowercased()) { return true }
                let d = Date(timeIntervalSince1970: m.takenAt)
                let minute = cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d)
                return (slot.startMinute...max(slot.startMinute, slot.endMinute)).contains(minute)
            }
            if let hit { used.insert(hit.id) }
            return (slot, hit != nil)
        }
    }

    /// The slot "as planned" should log now: the open slot whose window holds `minute`, else the last open one already started, else the first open one.
    public func suggestedPlanSlot(on day: String, minute: Int, engine: TrackerEngine) -> DietSlot? {
        let open = planSlots(on: day, engine: engine).filter { !$0.logged }.map(\.slot)
        return open.first { (($0.startMinute)...max($0.startMinute, $0.endMinute)).contains(minute) }
            ?? open.last { $0.startMinute <= minute } ?? open.first
    }

    /// Logs one plan slot as eaten, with its planned calories and protein, and updates the calorie and protein habits.
    public mutating func logPlanned(_ slot: DietSlot, day: String, now: Date, engine: TrackerEngine, today: String) throws {
        guard day <= today, let noon = engine.date(day) else { throw ValidationError(message: "Pick today or an earlier day.") }
        let midnight = engine.calendar.startOfDay(for: noon)
        let windowMiddle = midnight.addingTimeInterval(Double(slot.startMinute + max(0, slot.endMinute - slot.startMinute) / 2) * 60)
        let at = min(now, windowMiddle) < midnight ? midnight : min(now, windowMiddle)
        var entry = MealEntry(takenAt: at.timeIntervalSince1970, day: day, note: slot.portion.isEmpty ? slot.name : "\(slot.name) · \(slot.portion)", photo: "", source: "mac")
        entry.kcal = slot.kcal; entry.protein = slot.protein
        entry.dietKind = slot.sweet ? .sweet : slot.cafeReplacement ? .cafe : .standard
        entry.confirmed = true
        meals.entries.append(entry)
        applyMealTotals(on: day, today: today)
    }

    /// When the phone last sent sleep or steps (the end of the newest record), or nil before any sync.
    public var phoneLastSync: Double? {
        health.records.filter { $0.metric == .steps || $0.metric == .sleep }.map(\.end).max()
    }
}
