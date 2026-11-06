import AscendCore
import SwiftUI

@MainActor final class TrainingStore: ObservableObject {
  @Published private(set) var archive = TrainingArchive()
  @Published private(set) var error: String?
  let url: URL
  init(folder: URL) {
    url = folder.appendingPathComponent("training.json")
    do { archive = try TrainingStorage.read(url) } catch {
      self.error =
        "Training could not be read. The file was preserved. \(error.localizedDescription)"
    }
  }
  @discardableResult func save(_ candidate: TrainingArchive) -> Bool {
    do {
      try TrainingStorage.save(candidate, to: url)
      archive = candidate
      error = nil
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }
  @discardableResult func change(_ edit: (inout TrainingArchive) -> Void) -> Bool {
    var a = archive
    edit(&a)
    return save(a)
  }
  func complete(
    _ session: TrainingSession?, date: Date, outcome: SessionOutcome, calendar: Calendar
  ) {
    change { a in
      a.completions.removeAll { calendar.isDate($0.date, inSameDayAs: date) }
      a.completions.append(
        .init(
          sessionID: session?.id, date: date, outcome: outcome, kind: session?.kind ?? .rest,
          minutes: session?.minutes ?? 0))
    }
  }
}
extension TrackerStore {
  /// Today's summary for the phone, with the pieces that live outside tracker.json: workout, weight and the current time.
  func phoneToday() -> PhoneToday {
    let now = Date()
    var t = document.phoneToday(today: today)
    t.now = document.phoneNow(at: now)
    t.workout = training.archive.phoneWorkout(now: now, calendar: engine.calendar)
    let urges = document.urgeCounts(at: now)
    t.urgesActedToday = urges.actedToday
    t.urgesActedWeekAverage = urges.actedWeekAverage.map { ($0 * 10).rounded() / 10 }
    t.spotVisitsUnanswered = urges.unansweredVisits
    t.spots = SpotArchive.read(storageURL.deletingLastPathComponent().appendingPathComponent("spots.json")).spots
    if let w = bodyMeasurements.archive.latest {
      t.latestWeight = w.kilograms
      t.latestWeightAt = w.date.timeIntervalSince1970
    }
    return t
  }
  func bodyAssistantSummary() -> String? {
    let a = training.archive
    guard !a.plan.isEmpty || a.goal.targetFat != nil || !a.logs.isEmpty else { return nil }
    let now = Date()
    let r = BodyGoalReport.build(
      records: bodyMeasurements.archive.records, goal: a.goal, now: now, calendar: engine.calendar)
    let score = TrainingScorecard.build(
      training: a, health: document.health, now: now, calendar: engine.calendar)
    var lines = [
      "Body goal: \(a.goal.targetFat.map{String(format:"%.1f%%",$0)} ?? "unset"); target date: \(a.goal.targetDate.map{engine.key($0)} ?? "unset").",
      r.headline,
      "Weekly pace (kg lost/week): \(r.actualLossPerWeek.map{String(format:"%.2f",$0)} ?? "unknown").",
      "This week: strength \(score.strength)/3, cardio \(score.cardio)/3, walking days \(score.walkingDays)/7, long low-intensity \(score.longCardio)/1.",
      "Today: \(a.today(now,calendar:engine.calendar)?.name ?? "No planned session").",
    ]
    for l in a.logs.filter({ $0.date <= now }).sorted(by: { $0.date > $1.date }).prefix(5) {
      let e = a.exercises.first { $0.id == l.exerciseID }
      lines.append(
        "\(e?.name ?? "Exercise"): \(l.sets.map{String(format:"%.2f kg × %d",$0.weight,$0.reps)}.joined(separator:", "))."
      )
    }
    return lines.joined(separator: "\n")
  }
}
