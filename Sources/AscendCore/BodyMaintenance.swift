import Foundation

public enum MaintenanceSex: String, Codable, CaseIterable, Sendable { case male, female }
public struct MaintenanceDay: Identifiable, Sendable {
  public var key: String
  public var date: Date
  public var calories: Double
  public var meals: Int
  public var complete: Bool
  public var marked: Bool
  public var id: String { key }
}
public struct BodyMaintenanceReport: Sendable {
  public var window: Int
  public var days: [MaintenanceDay] = []
  public var measured: Double?, formula: Double?, bmr: Double?, factor: Double?,
    averageSteps: Double?, deviceActive: Double?
  public var deviceDays = 0
  public var fullDays = 0
  public var requiredFullDays = 12
  public var weighIns = 0
  public var weightDays = 0
  public var startAverage: Double?, endAverage: Double?, weightSpanDays: Double?,
    averageIntake: Double?
  public var missing: [String] = []
  public var formulaMissing: [String] = []
  public var currentTarget: Double?, deficit: Double?, predictedLossPerWeek: Double?,
    suggestedTarget: Double?, goalPace: Double?
  public var lazyDay: Double?, activeDay: Double?
  public var suggestionNote: String?
  public var headline: String {
    measured.map { "Measured estimate · about \(Int(Self.round($0))) kcal/day" }
      ?? "Build enough history to estimate your maintenance."
  }
  public static func round(_ value: Double) -> Double { (value / 50).rounded() * 50 }
  public static func restingEnergy(weight: Double, height: Double, age: Int, sex: MaintenanceSex)
    -> Double?
  {
    guard weight.isFinite, height.isFinite, (20...500).contains(weight),
      (100...250).contains(height), (18...110).contains(age)
    else { return nil }
    return 10 * weight + 6.25 * height - 5 * Double(age) + (sex == .male ? 5 : -161)
  }
  /// Transparent product heuristic, not a measured activity multiplier.
  public static func activityFactor(steps: Double, strengthPerWeek: Double) -> Double {
    if steps >= 10000 && strengthPerWeek >= 3 { return 1.725 }
    if steps >= 7000 || strengthPerWeek >= 3 { return 1.55 }
    if steps >= 5000 || strengthPerWeek >= 1 { return 1.375 }
    return 1.2
  }
  public static func validDay(_ key: String) -> Bool {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd"
    f.isLenient = false
    return key.count == 10 && f.date(from: key).map { f.string(from: $0) == key } == true
  }
  public static func build(
    training a: TrainingArchive, records: [BodyMeasurement], document: TrackerDocument, now: Date,
    window: Int = 14
  ) -> Self {
    let n = window == 28 ? 28 : 14
    let e = TrackerEngine(document: document)
    let c = e.calendar
    let end = c.startOfDay(for: now)
    let start = c.date(byAdding: .day, value: -n, to: end)!
    let keys = (0..<n).map { e.key(c.date(byAdding: .day, value: $0, to: start)!) }
    let allowed = Set(keys)
    let marked = Set(a.completedNutritionDays ?? [])
    // Closed local days only. Unconfirmed estimates and missing days never count as zero intake.
    let meals = Dictionary(
      grouping: document.meals.entries.filter {
        $0.confirmed && $0.takenAt >= start.timeIntervalSince1970
          && $0.takenAt < end.timeIntervalSince1970
      }
    ) { e.key(Date(timeIntervalSince1970: $0.takenAt)) }
    var r = Self(window: n)
    r.requiredFullDays = Int(ceil(Double(n) * 12 / 14))
    r.days = keys.enumerated().map { i, key in
      let rows = meals[key] ?? []
      let kcal = rows.map { $0.values.kcal }.reduce(0, +)
      return .init(
        key: key, date: c.date(byAdding: .day, value: i, to: start)!, calories: kcal,
        meals: rows.count, complete: (rows.count >= 2 && kcal >= 1200) || marked.contains(key),
        marked: marked.contains(key))
    }
    let full = r.days.filter(\.complete)
    r.fullDays = full.count
    if !full.isEmpty { r.averageIntake = full.map(\.calories).reduce(0, +) / Double(full.count) }
    if r.fullDays < r.requiredFullDays {
      r.missing.append(
        "Log \(r.requiredFullDays-r.fullDays) more full days (\(r.fullDays)/\(n) complete).")
    }
    let weights = records.filter { $0.date >= start && $0.date < end }
    r.weighIns = weights.count
    let daily = Dictionary(grouping: weights) { e.key($0.date) }.mapValues {
      $0.map(\.kilograms).reduce(0, +) / Double($0.count)
    }
    r.weightDays = daily.count
    if r.weighIns < 4 { r.missing.append("Add \(4-r.weighIns) more weigh-ins across the window.") }
    let first = keys.prefix(7).enumerated().compactMap { i, key in
      daily[key].map { (Double(i), $0) }
    }
    let last = keys.suffix(7).enumerated().compactMap { i, key in
      daily[key].map { (Double(n - 7 + i), $0) }
    }
    if first.count < 2 || last.count < 2 {
      r.missing.append("Weigh on at least two dates in each end's seven-day block.")
    }
    if first.count >= 2, last.count >= 2 {
      let firstMean = first.map { $0.1 }.reduce(0, +) / Double(first.count)
      let lastMean = last.map { $0.1 }.reduce(0, +) / Double(last.count)
      // Average-weight timestamps are their centroids: typically 7 days apart in a 14-day
      // window and 21 days in a 28-day window. Dividing by the whole window biases the rate.
      let span =
        last.map { $0.0 }.reduce(0, +) / Double(last.count) - first.map { $0.0 }.reduce(0, +)
        / Double(first.count)
      r.startAverage = firstMean
      r.endAverage = lastMean
      r.weightSpanDays = span
      if r.missing.isEmpty, let intake = r.averageIntake, span > 0 {
        let estimate = intake - (lastMean - firstMean) * 7700 / span
        if estimate.isFinite, (500...10000).contains(estimate) {
          r.measured = estimate
        } else {
          r.missing.append("The weight swing is too large for a reliable maintenance estimate.")
        }
      }
    }
    let latest = records.filter { $0.date <= now }.max { $0.date < $1.date }
    if latest == nil { r.formulaMissing.append("a weight reading") }
    if a.heightCM == nil { r.formulaMissing.append("height") }
    if a.age == nil || a.age! < 18 { r.formulaMissing.append("adult age") }
    if a.maintenanceSex == nil { r.formulaMissing.append("formula sex coefficient") }
    var steps: [String: Double] = [:]
    var energy: [String: Double] = [:]
    var strengthDays = Set<String>()
    for row in document.health.records
    where row.start >= start.timeIntervalSince1970 && row.end <= end.timeIntervalSince1970 {
      let key = e.key(Date(timeIntervalSince1970: row.start))
      guard allowed.contains(key) else { continue }
      if row.metric == .steps { steps[key, default: 0] += row.value }
      if row.metric == .activeEnergy { energy[key, default: 0] += row.value }
      if row.metric == .workout && TrainingScorecard.workoutType(row.detail).1 == .strength {
        strengthDays.insert(key)
      }
    }
    for done in a.completions
    where done.date >= start && done.date < end && done.outcome == .done && done.kind == .strength {
      strengthDays.insert(e.key(done.date))
    }
    if !steps.isEmpty { r.averageSteps = steps.values.reduce(0, +) / Double(steps.count) }
    if steps.count < 3 { r.formulaMissing.append("three days of watch steps") }
    if let w = latest?.kilograms, let height = a.heightCM, let age = a.age,
      let sex = a.maintenanceSex
    {
      r.bmr = restingEnergy(weight: w, height: height, age: age, sex: sex)
      if let bmr = r.bmr, steps.count >= 3, let avg = r.averageSteps {
        let factor = activityFactor(
          steps: avg, strengthPerWeek: Double(strengthDays.count) * 7 / Double(n))
        r.factor = factor
        r.formula = bmr * factor
        r.lazyDay = bmr * 1.2
        r.activeDay = bmr * 1.725
      }
    }
    r.deviceDays = energy.count
    if !energy.isEmpty { r.deviceActive = energy.values.reduce(0, +) / Double(energy.count) }
    r.currentTarget = document.mealHabits.calories?.latest.target?.maximum
    // Planning uses intake/weight or formula only. Watch calories never enter this calculation.
    if let base = r.measured ?? r.formula {
      if let target = r.currentTarget {
        r.deficit = base - target
        r.predictedLossPerWeek = (base - target) * 7 / 7700
      }
      let goal = BodyGoalReport.build(records: records, goal: a.goal, now: now, calendar: c)
      if let pace = goal.neededLossPerWeek, pace > 0 {
        r.goalPace = pace
        let target = base - pace * 7700 / 7
        if (a.age ?? 0) >= 18, !goal.aggressive, target >= 1200, base - target <= 1000,
          base - target <= base * 0.3
        {
          r.suggestedTarget = round(target)
        } else {
          r.suggestionNote =
            (a.age ?? 0) < 18
            ? "Add an adult age in settings before calculating a dietary target."
            : "That goal pace calls for a large deficit. Review the deadline; no calorie target is suggested."
        }
      }
    }
    return r
  }
}
