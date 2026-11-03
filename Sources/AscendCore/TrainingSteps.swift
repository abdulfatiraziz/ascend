import Foundation

public enum StepDayKind: String, Codable, CaseIterable, Sendable {
  case every, gym, treadmill, rest
}
public enum StepAnchor: String, Codable, CaseIterable, Sendable {
  case base, morning, lunch, dinner, session
}
public struct StepBlock: Codable, Equatable, Identifiable, Sendable {
  public var id = UUID()
  public var title: String
  public var day: StepDayKind
  public var anchor: StepAnchor
  public var steps: Int
  public var minutes: Int
  public init(title: String, day: StepDayKind, anchor: StepAnchor, steps: Int, minutes: Int) {
    self.title = title
    self.day = day
    self.anchor = anchor
    self.steps = steps
    self.minutes = minutes
  }
  public static var defaults: [Self] {
    [
      .init(title: "Home & desk base", day: .every, anchor: .base, steps: 2250, minutes: 0),
      .init(
        title: "Morning sunlight walk", day: .every, anchor: .morning, steps: 1000, minutes: 10),
      .init(title: "Gym movement", day: .gym, anchor: .session, steps: 1750, minutes: 60),
      .init(title: "Walk after lunch", day: .gym, anchor: .lunch, steps: 1500, minutes: 15),
      .init(title: "Walk after dinner", day: .gym, anchor: .dinner, steps: 1500, minutes: 15),
      .init(
        title: "Incline treadmill", day: .treadmill, anchor: .session, steps: 4000, minutes: 45),
      .init(title: "Walk after dinner", day: .treadmill, anchor: .dinner, steps: 1500, minutes: 15),
      .init(title: "Easy walking pad", day: .rest, anchor: .session, steps: 5500, minutes: 55),
    ]
  }
}
public struct StepBlockStatus: Identifiable, Sendable {
  public var block: StepBlock
  public var evidence: String?
  public var checked: Bool
  public var id: UUID { block.id }
}
public struct TrainingStepsReport: Sendable {
  public var steps: Double?
  public var target: Double?
  public var floor: Int
  public var headline: String
  public var blocks: [StepBlockStatus]
  public var remaining: String
  public var railsHint: Bool
  public static func build(
    training a: TrainingArchive, health: HealthArchive, document: TrackerDocument, now: Date
  ) -> Self {
    let engine = TrackerEngine(document: document)
    let c = engine.calendar
    let key = engine.key(now)
    let start = c.startOfDay(for: now)
    let end = c.date(byAdding: .day, value: 1, to: start)!
    let steps = health.steps(on: key, engine: engine)
    let target = document.healthHabits.steps?.latest.target?.minimum
    let floor = a.rules.stepsFloor
    let headline: String
    if let steps {
      headline =
        steps >= Double(floor)
        ? (target.map { steps >= $0 } == true
          ? "Daily target met." : "Floor met. Every extra walk helps.")
        : "A few planned walks will close the gap."
    } else {
      headline = "Waiting for today’s watch steps."
    }
    let session = a.today(now, calendar: c)
    let kind: StepDayKind =
      session?.kind == .strength ? .gym : session?.kind == .cardio ? .treadmill : .rest
    let workouts = health.records.filter {
      $0.metric == .workout && $0.start >= start.timeIntervalSince1970
        && $0.end <= min(now, end).timeIntervalSince1970
    }
    let meals = document.meals.entries.map { Date(timeIntervalSince1970: $0.takenAt) }.filter {
      c.isDate($0, inSameDayAs: now)
    }
    func minute(_ date: Date) -> Int {
      c.component(.hour, from: date) * 60 + c.component(.minute, from: date)
    }
    var usedStepIDs = Set<String>()
    var usedWorkoutIDs = Set<String>()
    let blocks = a.stepBlocks.filter { $0.day == .every || $0.day == kind }.map {
      b -> StepBlockStatus in
      var evidence: String?
      var from: Date?
      var to: Date?
      switch b.anchor {
      case .morning:
        from = c.date(byAdding: .minute, value: document.routine.wakeMinute + 30, to: start)
        to = c.date(byAdding: .minute, value: document.routine.wakeMinute + 90, to: start)
      case .lunch, .dinner:
        let range = b.anchor == .lunch ? 11 * 60..<16 * 60 : 17 * 60..<24 * 60
        if let meal = meals.first(where: { range.contains(minute($0)) }) {
          from = meal
          to = meal.addingTimeInterval(Double(30 + b.minutes) * 60)
        }
      case .session:
        let expected: TrainingKind = kind == .gym ? .strength : .cardio
        if let workout = workouts.first(where: {
          !usedWorkoutIDs.contains($0.id) && TrainingScorecard.workoutType($0.detail).1 == expected
            && ($0.end - $0.start) / 60 >= Double(b.minutes) * 0.75
        }) {
          evidence = "Watch workout"
          usedWorkoutIDs.insert(workout.id)
        }
      case .base: break  // Daily aggregate cannot prove a specific base block.
      }
      if let from, let to, to <= now {
        let bursts = health.records.filter {
          $0.metric == .steps && !usedStepIDs.contains($0.id)
            && $0.start >= from.timeIntervalSince1970 && $0.end <= to.timeIntervalSince1970
            && $0.end - $0.start <= 7200
        }
        if bursts.map(\.value).reduce(0, +) >= Double(b.steps) {
          evidence = "Watch steps in this window"
          usedStepIDs.formUnion(bursts.map(\.id))
        }
      }
      return .init(
        block: b, evidence: evidence,
        checked: evidence != nil || (a.stepChecks[key] ?? []).contains(b.id))
    }
    let deficit = max(0, Double(floor) - (steps ?? 0))
    let walk =
      blocks.first { $0.block.anchor == .dinner && !$0.checked }
      ?? blocks.first { !$0.checked && $0.block.anchor != .base }
    let remaining: String
    if steps == nil {
      remaining = "Sync your watch to see what’s left."
    } else if deficit == 0 {
      remaining =
        target.map { "\(Int(max(0,$0-steps!)).formatted()) steps to your habit target." }
        ?? "Floor met; no steps habit target configured."
    } else if let walk {
      remaining =
        "\(Int(deficit).formatted()) steps to the floor · \(walk.block.title.lowercased()) ≈ \(walk.block.steps.formatted()) steps\(Double(walk.block.steps)>=deficit ? " gets you there":" toward it")."
    } else {
      remaining = "\(Int(deficit).formatted()) steps to the floor."
    }
    let rails =
      a.railsHintEnabled && session?.cardioType.lowercased().contains("treadmill") == true
      && workouts.contains { w in
        guard TrainingScorecard.workoutType(w.detail).1 == .cardio, w.end > w.start else {
          return false
        }
        let samples = health.records.filter {
          $0.metric == .steps && $0.start >= w.start && $0.end <= w.end
        }
        return !samples.isEmpty
          && samples.map(\.value).reduce(0, +) / ((w.end - w.start) / 60) < a.railsStepsPerMinute
      }
    return .init(
      steps: steps, target: target, floor: floor, headline: headline, blocks: blocks,
      remaining: remaining, railsHint: rails)
  }
}
