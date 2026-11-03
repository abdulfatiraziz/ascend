import Foundation

public struct BodyCheckpoint: Codable, Equatable, Identifiable, Sendable {
  public var id = UUID()
  public var targetFat = 18.0
  public var targetWeight: Double?
  public var date = Date()
  public init() {}
}
public struct BodyGoal: Codable, Equatable, Sendable {
  public var targetFat: Double?
  public var targetDate: Date?
  public var targetWeight: Double?
  public var checkpoints: [BodyCheckpoint] = []
  public init(targetFat: Double? = nil, targetDate: Date? = nil, targetWeight: Double? = nil) {
    self.targetFat = targetFat
    self.targetDate = targetDate
    self.targetWeight = targetWeight
  }
}
public struct BodyWeeklyWeight: Identifiable, Sendable {
  public var date: Date
  public var kilograms: Double
  public var id: Date { date }
}
public struct BodyGoalReport: Sendable {
  public var weight: Double?, fat: Double?, leanMass: Double?, goalWeight: Double?
  public var weekly: [BodyWeeklyWeight] = []
  /// Positive means loss. Regression uses weekly averages rather than single weigh-ins.
  public var actualLossPerWeek: Double?, neededLossPerWeek: Double?
  public var projectedDate: Date?, earliestDate: Date?, gentlerDate: Date?
  public var aggressive = false
  public var stale = false
  public var headline = "Set a goal, then build a trend."
  public static func build(
    records: [BodyMeasurement], goal: BodyGoal, now: Date, calendar: Calendar
  ) -> Self {
    let sorted = records.filter { $0.date <= now }.sorted { $0.date < $1.date }
    var r = Self()
    r.weight = sorted.last?.kilograms
    let f = sorted.last {
      !$0.isManual && ($0.value("bodyFatPercentage").map { $0 > 0 && $0 < 100 } ?? false)
    }
    r.fat = f?.value("bodyFatPercentage")
    if let fat = r.fat, let weight = r.weight { r.leanMass = weight * (1 - fat / 100) }
    r.goalWeight =
      goal.targetWeight ?? goal.targetFat.flatMap { fat in r.leanMass.map { $0 / (1 - fat / 100) } }
    let groups = Dictionary(grouping: sorted) {
      calendar.dateInterval(of: .weekOfYear, for: $0.date)!.start
    }
    r.weekly = groups.keys.sorted().map { date in
      .init(
        date: date,
        kilograms: groups[date]!.map(\.kilograms).reduce(0, +) / Double(groups[date]!.count))
    }
    let cutoff = calendar.date(byAdding: .day, value: -28, to: now)!
    let recent = r.weekly.filter { $0.date >= cutoff }
    if recent.count >= 3, let first = recent.first, let last = recent.last,
      last.date.timeIntervalSince(first.date) >= 12 * 86400
    {
      let xs = recent.map { $0.date.timeIntervalSince(first.date) / 604800 }
      let ys = recent.map(\.kilograms)
      let xm = xs.reduce(0, +) / Double(xs.count)
      let ym = ys.reduce(0, +) / Double(ys.count)
      let denom = xs.map { pow($0 - xm, 2) }.reduce(0, +)
      if denom > 0 {
        r.actualLossPerWeek = -zip(xs, ys).map { ($0 - xm) * ($1 - ym) }.reduce(0, +) / denom
      }
    }
    r.stale = sorted.last.map { now.timeIntervalSince($0.date) > 14 * 86400 } ?? true
    guard let w = r.weight, let target = r.goalWeight else { return r }
    let loss = w - target
    if loss <= 0 {
      r.headline = "At your weight goal. Review body composition over time."
      return r
    }
    if let due = goal.targetDate {
      let weeks = due.timeIntervalSince(now) / 604800
      if weeks > 0 {
        r.neededLossPerWeek = loss / weeks
        r.aggressive = loss / weeks > w * 0.01
      } else {
        r.headline = "Target date has passed. Choose a new date."
        return r
      }
    }
    // Planning bounds are heuristics, not individual prescriptions.
    r.earliestDate = now.addingTimeInterval(loss / (w * 0.0075) * 604800)
    r.gentlerDate = now.addingTimeInterval(loss / (w * 0.005) * 604800)
    if let pace = r.actualLossPerWeek, pace > 0.02, !r.stale {
      r.projectedDate = now.addingTimeInterval(loss / pace * 604800)
    }
    if r.aggressive {
      r.headline = "This deadline is too aggressive: over 1% of body weight a week."
    } else if r.stale {
      r.headline = "Log a recent weight to update your pace."
    } else if let pace = r.actualLossPerWeek {
      if pace < 0.02 {
        r.headline = "Weight is flat or rising over the last four weeks."
      } else if let needed = r.neededLossPerWeek {
        r.headline =
          pace >= needed
          ? "On pace. Keep the week consistent."
          : "Progress is steady; the deadline needs more time."
      } else {
        r.headline = "Your weekly average is trending down."
      }
    } else {
      r.headline = "More weekly readings will reveal your pace."
    }
    return r
  }
  public static func weekNumber(_ date: Date, weekOne: Date, calendar: Calendar) -> Int {
    let days =
      calendar.dateComponents(
        [.day], from: calendar.startOfDay(for: weekOne), to: calendar.startOfDay(for: date)
      ).day ?? 0
    return Int(floor(Double(days) / 7)) + 1
  }
}
