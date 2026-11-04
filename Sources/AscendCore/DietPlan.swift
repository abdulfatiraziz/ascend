import Foundation

public enum MealDietKind: String, Codable, CaseIterable, Sendable {
    case standard, sweet, cafe
    public var label: String { switch self { case .standard: "Meal"; case .sweet: "Sweet"; case .cafe: "Café swap" } }
}
public struct DietSlot: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var portion: String
    public var startMinute: Int
    public var endMinute: Int
    public var kcal: Double?
    public var protein: Double?
    public var sweet: Bool
    public var cafeReplacement: Bool
    public init(name: String, portion: String = "", startMinute: Int, endMinute: Int, kcal: Double? = nil, protein: Double? = nil, sweet: Bool = false, cafeReplacement: Bool = false) {
        self.name=name; self.portion=portion; self.startMinute=startMinute; self.endMinute=endMinute; self.kcal=kcal; self.protein=protein; self.sweet=sweet; self.cafeReplacement=cafeReplacement
    }
    public func contains(_ minute: Int) -> Bool { (startMinute..<endMinute).contains(minute) }
}
public struct FoodReference: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var tablespoonGrams: Double?
    public var sprayGrams: Double?
    public init(name: String, kcal: Double, protein: Double = 0, carbs: Double = 0, fat: Double = 0, tablespoonGrams: Double? = nil, sprayGrams: Double? = nil) {
        self.name=name; self.kcal=kcal; self.protein=protein; self.carbs=carbs; self.fat=fat; self.tablespoonGrams=tablespoonGrams; self.sprayGrams=sprayGrams
    }
    public func values(grams: Double) -> MealTotals {
        var t=MealTotals(); t.kcal=kcal*grams/100; t.protein=protein*grams/100; t.carbs=carbs*grams/100; t.fat=fat*grams/100; return t
    }
}
public struct DietCheckpoint: Codable, Equatable, Identifiable, Sendable {
    public var day: String
    public var weight: Double
    public var id: String { day }
    public init(day: String, weight: Double) { self.day=day; self.weight=weight }
}
public struct DietPlan: Codable, Equatable, Sendable {
    public var version = 1
    public var effectiveDay: String
    public var slots: [DietSlot] = []
    public var sweetOptions: [String] = []
    public var references: [FoodReference] = []
    public var checkpoints: [DietCheckpoint] = []
    public var checkpointTolerance: Double = 0.25
    public var sweetsHabitID: UUID?
    public var sourceNoteID: UUID?
    public init(effectiveDay: String) { self.effectiveDay=effectiveDay }
    public func validate(engine: TrackerEngine, habits: [Habit]) throws {
        func fail(_ condition: Bool, _ message: String) throws { if !condition { throw ValidationError(message: message) } }
        try fail(version == 1 && engine.date(effectiveDay) != nil, "Invalid diet plan version or start date.")
        try fail(slots.count <= 30 && references.count <= 300 && checkpoints.count <= 200 && sweetOptions.count <= 40, "Diet plan is too large.")
        try fail(Set(slots.map(\.id)).count == slots.count && Set(references.map(\.id)).count == references.count && Set(checkpoints.map(\.day)).count == checkpoints.count, "Duplicate diet plan entries.")
        try fail(checkpointTolerance.isFinite && (0...5).contains(checkpointTolerance), "Invalid checkpoint tolerance.")
        if let id=sweetsHabitID { try fail(habits.contains { $0.id == id && $0.kind == .check }, "Select an existing check-in for the sweets rule.") }
        let ordered=slots.sorted { $0.startMinute < $1.startMinute }
        for (i,slot) in ordered.enumerated() {
            try fail(!slot.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && slot.name.count <= 100 && slot.portion.count <= 1000, "Give meal slots a short name and portion description.")
            try fail((0..<1440).contains(slot.startMinute) && (1...1440).contains(slot.endMinute) && slot.startMinute < slot.endMinute, "Meal windows must start before they end, within one day.")
            if i>0 { try fail(ordered[i-1].endMinute <= slot.startMinute, "Meal windows overlap; give each meal one slot.") }
            for value in [slot.kcal,slot.protein].compactMap({$0}) { try fail(value.isFinite && (0...10000).contains(value), "Invalid planned nutrition.") }
        }
        try fail(sweetOptions.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 200 }, "Sweet options must be short, nonempty names.")
        try fail(Set(references.map { $0.name.lowercased() }).count == references.count, "Food reference names must be unique.")
        for r in references {
            try fail(!r.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && r.name.count <= 100, "Name every food reference.")
            try fail([r.kcal,r.protein,r.carbs,r.fat].allSatisfy { $0.isFinite && (0...1000).contains($0) }, "Invalid nutrition per 100 g.")
            for n in [r.tablespoonGrams,r.sprayGrams].compactMap({$0}) { try fail(n.isFinite && n>0 && n<=100, "Calibrate oil portions in grams greater than zero.") }
        }
        for c in checkpoints { try fail(engine.date(c.day) != nil && c.weight.isFinite && (20...500).contains(c.weight), "Invalid weight checkpoint.") }
    }
    public func slot(for meal: MealEntry, calendar: Calendar) -> DietSlot? {
        let date=Date(timeIntervalSince1970: meal.takenAt)
        let minute=calendar.component(.hour,from:date)*60+calendar.component(.minute,from:date)
        return slots.first { slot in
            (slot.contains(minute) || (meal.dietKind == .cafe && slot.cafeReplacement && (max(0,slot.startMinute-30)..<slot.startMinute).contains(minute))) && (meal.dietKind == .cafe ? slot.cafeReplacement : meal.dietKind == .sweet ? slot.sweet : !slot.sweet)
        }
    }
    public func unplannedSweets(_ log: MealLog, day: String, calendar: Calendar) -> [MealEntry] {
        guard day >= effectiveDay else { return [] }
        return log.on(day).filter { $0.confirmed && $0.dietKind == .sweet && slot(for:$0,calendar:calendar) == nil }
    }
}
public struct DietBudget: Sendable {
    public var start: String
    public var planned: Double
    public var consumed: Double
    public var loggedDays: Int
    public var targetDays: Int
    public var remaining: Double { planned-consumed }
    public static func build(document: TrackerDocument, day: String) -> Self? {
        let e=TrackerEngine(document:document)
        guard let date=e.date(day), let habit=document.mealHabits.calories else { return nil }
        var cal=e.calendar;cal.firstWeekday=2
        guard let start=cal.dateInterval(of:.weekOfYear,for:date)?.start else { return nil }
        var result=Self(start:e.key(start),planned:0,consumed:0,loggedDays:0,targetDays:0)
        for i in 0..<7 {
            let d=e.key(cal.date(byAdding:.day,value:i,to:start)!)
            if let r=habit.revision(on:d), let date=e.date(d), r.schedule.weekdays.contains(cal.component(.weekday,from:date)), let limit=e.target(for:habit,on:d)?.maximum { result.planned += limit; result.targetDays += 1 }
            let meals=document.meals.totals(d)
            if meals.confirmed>0 { result.consumed += meals.kcal; result.loggedDays += 1 }
            else if let value=e.entry(for:habit,day:d)?.value { result.consumed += value;result.loggedDays += 1 }
        }
        return result.targetDays>0 ? result:nil
    }
}
public struct FoodCalculation: Sendable {
    public var reference: FoodReference
    public var grams: Double
    public var totals: MealTotals { reference.values(grams:grams) }
    /// Pure parser; never creates a meal or changes a calorie target.
    public static func parse(_ input: String, references: [FoodReference]) throws -> Self {
        let text=input.trimmingCharacters(in:.whitespacesAndNewlines).lowercased().replacingOccurrences(of:"×",with:"x")
        var candidates=references.filter { text.contains($0.name.lowercased()) }.sorted { $0.name.count > $1.name.count }
        if candidates.isEmpty && (text.contains("spray") || text.contains("x")) {
            let oils=references.filter{$0.sprayGrams != nil || $0.tablespoonGrams != nil}; if oils.count==1 {candidates=oils}
        }
        guard let r=candidates.first else { throw ValidationError(message:"Use the name of a saved food reference.") }
        var amountText=text.replacingOccurrences(of:r.name.lowercased(),with:"").replacingOccurrences(of:"+",with:"").trimmingCharacters(in:.whitespaces)
        let unit: String
        if amountText.contains("tbsp") { unit="tbsp";amountText=amountText.replacingOccurrences(of:"tbsp",with:"") }
        else if amountText.contains("spray") || amountText.contains("x") { unit="spray";amountText=amountText.replacingOccurrences(of:"sprays",with:"").replacingOccurrences(of:"spray",with:"").replacingOccurrences(of:"x",with:"") }
        else { unit="g";amountText=amountText.replacingOccurrences(of:"grams",with:"").replacingOccurrences(of:"g",with:"") }
        guard let amount=Double(amountText.trimmingCharacters(in:.whitespaces)),amount.isFinite,amount>0 else { throw ValidationError(message:"Enter a positive amount, for example rice 85 g or oil 1 tbsp.") }
        let multiplier:Double
        switch unit { case "tbsp": guard let n=r.tablespoonGrams else { throw ValidationError(message:"Set grams per tablespoon for this food first.") };multiplier=n
        case "spray": guard let n=r.sprayGrams else { throw ValidationError(message:"Calibrate grams per spray for this food first.") };multiplier=n
        default:multiplier=1 }
        let grams=amount*multiplier
        guard grams.isFinite,grams<=10000,r.values(grams:grams).kcal<=10000 else { throw ValidationError(message:"This portion is too large.") }
        return Self(reference:r,grams:grams)
    }
}

public struct DietCheckpointReport: Sendable {
    public var checkpoint: DietCheckpoint?
    public var average: Double?
    public var days: Int
    public var label: String
    public static func build(plan: DietPlan, records: [BodyMeasurement], day: String, calendar: Calendar) -> Self {
        let formatter=DateFormatter();formatter.calendar=calendar;formatter.timeZone=calendar.timeZone;formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="yyyy-MM-dd";formatter.isLenient=false
        guard let checkpoint=plan.checkpoints.filter({$0.day<=day}).max(by:{$0.day<$1.day}), let end=formatter.date(from:checkpoint.day),let begin=calendar.date(byAdding:.day,value:-6,to:end),let finish=calendar.date(byAdding:.day,value:1,to:end) else { return .init(checkpoint:nil,average:nil,days:0,label:"Your first checkpoint is ahead.") }
        let daily=Dictionary(grouping:records.filter{$0.date>=begin && $0.date<finish},by:{formatter.string(from:$0.date)}).values.map { group in group.reduce(0){$0+$1.kilograms}/Double(group.count) }
        guard daily.count>=2 else {return .init(checkpoint:checkpoint,average:nil,days:daily.count,label:"Need two weigh-in dates around \(checkpoint.day) to compare.")}
        let average=daily.reduce(0,+)/Double(daily.count),difference=average-checkpoint.weight
        let status=abs(difference)<=plan.checkpointTolerance ? "On pace" : difference>0 ? "Behind checkpoint" : "Ahead of checkpoint"
        return .init(checkpoint:checkpoint,average:average,days:daily.count,label:"\(status) · \(String(format:"%.2f",average)) kg average vs \(String(format:"%.2f",checkpoint.weight)) kg target · \(checkpoint.day)")
    }
}

extension TrackerDocument {
    /// Atomic model update: callers persist only after validation succeeds.
    public mutating func applyDietPlan(_ plan: DietPlan, weekdayLimits: [Int: Double]?, today: String) throws {
        var candidate=self
        candidate.diet=plan
        if let limits=weekdayLimits {
            guard limits.count==7,Set(limits.keys)==Set(1...7),limits.values.allSatisfy({$0.isFinite && $0>0 && $0<=10000}),let habit=mealHabits.calories,let index=habits.firstIndex(where:{$0.id==habit.id}) else {throw ValidationError(message:"Use seven valid weekday limits and an existing calorie habit.")}
            var revision=habit.latest
            let targets=limits.mapValues{MetricTarget(maximum:$0,unit:"kcal")}
            if revision.weekdayTargets != targets || Set(revision.schedule.weekdays) != Set(1...7) {
                revision.effectiveDay=today;revision.weekdayTargets=targets;revision.schedule=Schedule()
                candidate.habits[index].revise(revision)
                candidate.applyMealTotals(on:today,today:today)
            }
        }
        try candidate.validate()
        self=candidate
    }
}
