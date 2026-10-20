import Foundation
import AscendCore

private var failures = 0
private func failure(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    failures += 1
    print("FAIL: \(message) [\(file):\(line)]")
}
private func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) {
    if a != b { failure("\(a) != \(b)", file: file, line: line) }
}
private func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { if !value { failure("Expected true", file: file, line: line) } }
private func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { expectTrue(!value, file: file, line: line) }
private func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { if value != nil { failure("Expected nil", file: file, line: line) } }
private func expectThrows(_ expression: @autoclosure () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
    do { try expression(); failure("Expected validation error", file: file, line: line) } catch { }
}

struct TrackerEngineChecks {
    let monday = "2026-10-19"
    func testSeedStartsEmptyAndHasAllUserPriorities() throws {
        let doc = TrackerDocument.seeded(today: monday)
        try doc.validate()
        expectEqual(doc.goals.count, 4)
        expectEqual(doc.habits.filter { $0.kind != .milestone }.count, 15)
        expectEqual(doc.habits.filter { $0.kind == .milestone }.count, 2)
        expectTrue(doc.checkIns.isEmpty)
        expectEqual(TrackerEngine(document: doc).score(on: monday), Score(completed: 0, scheduled: 15))
    }
    func testTwelveWeeksIs84DaysInclusive() {
        let doc = TrackerDocument.seeded(today: monday), e = TrackerEngine(document: doc)
        expectEqual(doc.cycle.end, "2027-01-10")
        expectEqual(e.days(from: doc.cycle.start, through: doc.cycle.end).count, 84)
        expectEqual(e.dayNumber(monday), 1)
    }
    func testGymRestDaysAreExcluded() {
        let doc = TrackerDocument.seeded(today: monday), e = TrackerEngine(document: doc)
        expectEqual(e.score(on: "2026-10-20").scheduled, 14)
        expectEqual(e.score(on: "2026-10-21").scheduled, 15)
        expectEqual(e.score(from: monday, through: "2026-10-25").scheduled, 102)
    }
    func testMilestonesNeverInflateHabitScore() {
        var doc = TrackerDocument.seeded(today: monday)
        let milestone = doc.habits.first { $0.kind == .milestone }!
        let due = milestone.latest.schedule.once!
        let before = TrackerEngine(document: doc).score(on: due)
        doc.setEntry(CheckIn(habitID: milestone.id, day: due, completed: true))
        let e = TrackerEngine(document: doc)
        expectEqual(e.score(on: due), before)
        expectTrue(e.milestoneCompleted(milestone))
    }
    func testNoClosedScoreOnFirstDay() {
        let e = TrackerEngine(document: .seeded(today: monday))
        expectNil(e.closedScore(today: monday).ratio)
    }
    func testClosedScoreExcludesOpenDayAndCountsMisses() {
        var doc = TrackerDocument.seeded(today: monday)
        let check = doc.habits.first { $0.kind == .check }!
        doc.setEntry(CheckIn(habitID: check.id, day: monday, completed: true))
        doc.setEntry(CheckIn(habitID: check.id, day: "2026-10-20", completed: true))
        let score = TrackerEngine(document: doc).closedScore(today: "2026-10-20")
        expectEqual(score.completed, 1)
        expectEqual(score.scheduled, 15)
    }
    func testMetricRequiresLoggedValueWithinTarget() {
        var doc = TrackerDocument.seeded(today: monday)
        let h = doc.habits.first { $0.latest.title == "Sleep" }!
        expectFalse(TrackerEngine(document: doc).completed(h, on: monday))
        doc.setEntry(CheckIn(habitID: h.id, day: monday, value: 6.9))
        expectFalse(TrackerEngine(document: doc).completed(h, on: monday))
        doc.setEntry(CheckIn(habitID: h.id, day: monday, value: 7.5))
        expectTrue(TrackerEngine(document: doc).completed(h, on: monday))
        doc.setEntry(CheckIn(habitID: h.id, day: monday, value: 8.5))
        expectFalse(TrackerEngine(document: doc).completed(h, on: monday))
    }
    func testCaloriesStayStrictlyBelow1700() {
        var doc = TrackerDocument.seeded(today: monday)
        let h = doc.habits.first { $0.latest.title == "Calorie target" }!
        doc.setEntry(CheckIn(habitID: h.id, day: monday, value: 1700))
        expectFalse(TrackerEngine(document: doc).completed(h, on: monday))
        doc.setEntry(CheckIn(habitID: h.id, day: monday, value: 1699))
        expectTrue(TrackerEngine(document: doc).completed(h, on: monday))
    }
    func testEntryUpdatesDoNotDoubleCount() {
        var doc = TrackerDocument.seeded(today: monday)
        let h = doc.habits.first { $0.kind == .check }!
        doc.setEntry(CheckIn(habitID: h.id, day: monday, completed: true))
        doc.setEntry(CheckIn(habitID: h.id, day: monday, completed: true))
        expectEqual(doc.checkIns.count, 1)
        expectEqual(TrackerEngine(document: doc).score(on: monday).completed, 1)
    }
    func testScheduleEditDoesNotRewritePastDay() {
        var doc = TrackerDocument.seeded(today: monday)
        let i = doc.habits.firstIndex { $0.latest.title == "Gym session" }!
        var r = doc.habits[i].latest
        r.effectiveDay = "2026-10-20"; r.schedule.weekdays = [1]
        doc.habits[i].revise(r)
        let e = TrackerEngine(document: doc)
        expectTrue(e.isDue(doc.habits[i], on: monday))
        expectFalse(e.isDue(doc.habits[i], on: "2026-10-21"))
        expectTrue(e.isDue(doc.habits[i], on: "2026-10-25"))
    }
    func testTargetEditPreservesHistoricalCompletion() {
        var doc = TrackerDocument.seeded(today: monday)
        let i = doc.habits.firstIndex { $0.latest.title == "Protein target" }!
        doc.setEntry(CheckIn(habitID: doc.habits[i].id, day: monday, value: 105))
        var r = doc.habits[i].latest
        r.effectiveDay = "2026-10-20"; r.target = MetricTarget(minimum: 120, unit: "g")
        doc.habits[i].revise(r)
        expectTrue(TrackerEngine(document: doc).completed(doc.habits[i], on: monday))
    }
    func testGoalWindowEditPreservesHistory() {
        var doc = TrackerDocument.seeded(today: monday)
        doc.goals[0].revise(GoalWindow(effectiveDay: "2026-10-20", start: "2026-10-21", end: "2026-10-22"))
        let e = TrackerEngine(document: doc)
        expectEqual(e.score(on: monday).scheduled, 15)
        expectFalse(e.due(on: "2026-10-20").contains { $0.goalID == doc.goals[0].id })
    }
    func testArchivePreservesPastDenominator() {
        var doc = TrackerDocument.seeded(today: monday)
        doc.habits[0].archivedDay = "2026-10-20"
        let e = TrackerEngine(document: doc)
        expectEqual(e.score(on: monday).scheduled, 15)
        expectEqual(e.score(on: "2026-10-20").scheduled, 13)
    }
    func testNewHabitNeverCreatesHistoricalMisses() {
        var doc = TrackerDocument.seeded(today: monday)
        doc.habits.append(Habit(goalID: doc.goals[0].id, kind: .check, createdDay: "2026-10-21", revisions: [HabitRevision(effectiveDay: "2026-10-21", title: "Read", period: .evening)]))
        expectEqual(TrackerEngine(document: doc).score(on: monday).scheduled, 15)
        expectEqual(TrackerEngine(document: doc).score(on: "2026-10-21").scheduled, 16)
    }
    func testSeventyFivePercentRoundsUp() {
        expectEqual(Score(completed: 8, scheduled: 15).remaining(target: 0.75), 4)
        expectEqual(Score(completed: 0, scheduled: 14).remaining(target: 0.75), 11)
    }
    func testValidationRejectsCorruptReferencesAndDates() {
        var doc = TrackerDocument.seeded(today: monday)
        doc.habits[0].goalID = UUID()
        expectThrows(try doc.validate())
        doc = .seeded(today: monday); doc.cycle.end = "2026-02-31"
        expectThrows(try doc.validate())
        doc = .seeded(today: monday); doc.habits[0].revisions = []
        expectThrows(try doc.validate())
    }
    func testBackupRoundTripAndTimezoneMidnight() throws {
        let doc = TrackerDocument.seeded(today: monday)
        let decoded = try JSONDecoder().decode(TrackerDocument.self, from: JSONEncoder().encode(doc))
        try decoded.validate(); expectEqual(doc, decoded)
        let date = ISO8601DateFormatter().date(from: "2026-10-18T19:00:00Z")!
        expectEqual(TrackerEngine(document: doc).key(date), monday)
    }
    func testNoEvolutionFromTimePassingAlone() {
        let e = TrackerEngine(document: .seeded(today: monday))
        expectEqual(e.evolution(today: "2026-11-19"), 0)
    }
    func testLegacyBackupGetsSafeDefaults() throws {
        let original = TrackerDocument.seeded(today: monday)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        for key in ["restDays", "previousCycles", "reminders"] { object.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(TrackerDocument.self, from: JSONSerialization.data(withJSONObject: object))
        expectEqual(decoded, original); try decoded.validate()
    }
    func testRestDayPreservesValuesAndRestoresScore() throws {
        var doc = TrackerDocument.seeded(today: monday)
        let h = doc.habits[0]
        doc.setEntry(CheckIn(habitID: h.id, day: monday, value: 7.5))
        doc.restDays.insert(monday)
        try doc.validate()
        expectEqual(TrackerEngine(document: doc).score(on: monday), Score())
        expectEqual(doc.checkIns.first?.value, 7.5)
        doc.restDays.remove(monday)
        expectEqual(TrackerEngine(document: doc).score(on: monday), Score(completed: 1, scheduled: 15))
    }
    func testResetDayOnlyTouchesThatDate() {
        var doc = TrackerDocument.seeded(today: monday)
        let h = doc.habits[1], next = "2026-10-20"
        doc.setEntry(CheckIn(habitID: h.id, day: monday, completed: true))
        doc.setEntry(CheckIn(habitID: h.id, day: next, completed: true))
        doc.restDays = [monday, next]
        doc.resetDay(monday)
        expectEqual(doc.checkIns.count, 1); expectEqual(doc.checkIns[0].day, next)
        expectEqual(doc.restDays, [next])
        let plan = doc.habits
        doc.resetProgress()
        expectTrue(doc.checkIns.isEmpty); expectTrue(doc.restDays.isEmpty); expectEqual(doc.habits, plan)
    }
    func testRestartKeepsHistoricalRulesAndResetsCurrentCycle() throws {
        var doc = TrackerDocument.seeded(today: monday)
        let today = "2026-10-26", h = doc.habits[1]
        doc.setEntry(CheckIn(habitID: h.id, day: monday, completed: true))
        doc.setEntry(CheckIn(habitID: h.id, day: today, completed: true))
        doc.restDays = ["2026-10-20", today]
        doc.restart(on: today, length: 90)
        try doc.validate()
        let e = TrackerEngine(document: doc)
        expectEqual(e.days(from: doc.cycle.start, through: doc.cycle.end).count, 90)
        expectEqual(doc.checkIns.count, 1); expectEqual(doc.checkIns[0].day, monday)
        expectEqual(e.score(on: monday), Score(completed: 1, scheduled: 15))
        expectEqual(doc.restDays, ["2026-10-20"])
        expectEqual(doc.previousCycles[0].end, "2026-10-25")
        expectEqual(e.evolution(today: today), 0)
        expectEqual(doc.habits.first { $0.kind == .milestone }?.latest.schedule.once, "2026-11-09")
    }
    func testRepeatedSameDayRestartRemainsValid() throws {
        var doc = TrackerDocument.seeded(today: monday)
        doc.habits[0].archivedDay = monday
        doc.restart(on: monday, length: 84); doc.restart(on: monday, length: 90)
        try doc.validate()
        expectTrue(doc.previousCycles.isEmpty)
        expectEqual(doc.habits[0].archivedDay, monday)
        expectEqual(doc.goals[0].windows.count, 1)
    }
    func testRecordedMilestonesAppearOnActualLogDate() {
        var doc = TrackerDocument.seeded(today: monday)
        let h = doc.habits.first { $0.kind == .milestone }!
        doc.setEntry(CheckIn(habitID: h.id, day: monday, completed: true))
        expectTrue(TrackerEngine(document: doc).reviewTasks(on: monday).contains { $0.id == h.id })
        doc.restart(on: "2026-10-20", length: 84)
        expectFalse(TrackerEngine(document: doc).milestoneCompleted(h))
        expectTrue(TrackerEngine(document: doc).completed(h, on: monday))
    }
    func testLeapDayYearBoundaryAndDSTDates() {
        var doc = TrackerDocument.seeded(today: monday)
        doc.timeZoneID = "America/New_York"
        let e = TrackerEngine(document: doc)
        expectEqual(e.adding(1, to: "2028-02-28"), "2028-02-29")
        expectEqual(e.adding(1, to: "2026-12-31"), "2027-01-01")
        expectEqual(e.days(from: "2026-03-07", through: "2026-03-10").count, 4)
        expectEqual(e.days(from: "2026-10-31", through: "2026-11-03").count, 4)
        expectNil(e.date("2027-02-29"))
    }
    func testReminderPlannerSkipsRestCompletedAndPastTimes() throws {
        var doc = TrackerDocument.seeded(today: monday)
        doc.reminders.enabled = true
        let e = TrackerEngine(document: doc)
        let now = e.calendar.date(bySettingHour: 8, minute: 0, second: 0, of: e.date(monday)!)!
        let planned = e.plannedReminders(now: now)
        expectEqual(planned.count, 60)
        expectTrue(planned.allSatisfy { $0.date > now })
        expectEqual(Set(planned.map(\.id)).count, planned.count)
        doc.restDays.insert(monday)
        expectEqual(TrackerEngine(document: doc).plannedReminders(now: now).count, 58)
        doc.restDays.remove(monday)
        for h in e.due(on: monday) {
            let value = h.kind == .metric ? (h.latest.target?.minimum ?? h.latest.target?.maximum ?? 0) : nil
            doc.setEntry(CheckIn(habitID: h.id, day: monday, completed: true, value: value))
        }
        expectEqual(TrackerEngine(document: doc).plannedReminders(now: now).count, 58)
        doc.reminders.enabled = false
        expectTrue(TrackerEngine(document: doc).plannedReminders(now: now).isEmpty)
        try doc.validate()
    }
    func testInvalidReminderPreferencesAreRejected() {
        var doc = TrackerDocument.seeded(today: monday)
        doc.reminders.eveningMinute = 500
        expectThrows(try doc.validate())
        doc.reminders.eveningMinute = 1440
        expectThrows(try doc.validate())
        doc = .seeded(today: monday); doc.restDays.insert("2026-02-31")
        expectThrows(try doc.validate())
    }
}

@main enum CheckRunner {
    static func main() async {
        let checks = TrackerEngineChecks()
        let cases: [(String, () throws -> Void)] = [
            ("testSeedStartsEmptyAndHasAllUserPriorities", checks.testSeedStartsEmptyAndHasAllUserPriorities),
            ("testTwelveWeeksIs84DaysInclusive", checks.testTwelveWeeksIs84DaysInclusive),
            ("testGymRestDaysAreExcluded", checks.testGymRestDaysAreExcluded),
            ("testMilestonesNeverInflateHabitScore", checks.testMilestonesNeverInflateHabitScore),
            ("testNoClosedScoreOnFirstDay", checks.testNoClosedScoreOnFirstDay),
            ("testClosedScoreExcludesOpenDayAndCountsMisses", checks.testClosedScoreExcludesOpenDayAndCountsMisses),
            ("testMetricRequiresLoggedValueWithinTarget", checks.testMetricRequiresLoggedValueWithinTarget),
            ("testCaloriesStayStrictlyBelow1700", checks.testCaloriesStayStrictlyBelow1700),
            ("testEntryUpdatesDoNotDoubleCount", checks.testEntryUpdatesDoNotDoubleCount),
            ("testScheduleEditDoesNotRewritePastDay", checks.testScheduleEditDoesNotRewritePastDay),
            ("testTargetEditPreservesHistoricalCompletion", checks.testTargetEditPreservesHistoricalCompletion),
            ("testGoalWindowEditPreservesHistory", checks.testGoalWindowEditPreservesHistory),
            ("testArchivePreservesPastDenominator", checks.testArchivePreservesPastDenominator),
            ("testNewHabitNeverCreatesHistoricalMisses", checks.testNewHabitNeverCreatesHistoricalMisses),
            ("testSeventyFivePercentRoundsUp", checks.testSeventyFivePercentRoundsUp),
            ("testValidationRejectsCorruptReferencesAndDates", checks.testValidationRejectsCorruptReferencesAndDates),
            ("testBackupRoundTripAndTimezoneMidnight", checks.testBackupRoundTripAndTimezoneMidnight),
            ("testNoEvolutionFromTimePassingAlone", checks.testNoEvolutionFromTimePassingAlone),
            ("testLegacyBackupGetsSafeDefaults", checks.testLegacyBackupGetsSafeDefaults),
            ("testRestDayPreservesValuesAndRestoresScore", checks.testRestDayPreservesValuesAndRestoresScore),
            ("testResetDayOnlyTouchesThatDate", checks.testResetDayOnlyTouchesThatDate),
            ("testRestartKeepsHistoricalRulesAndResetsCurrentCycle", checks.testRestartKeepsHistoricalRulesAndResetsCurrentCycle),
            ("testRepeatedSameDayRestartRemainsValid", checks.testRepeatedSameDayRestartRemainsValid),
            ("testRecordedMilestonesAppearOnActualLogDate", checks.testRecordedMilestonesAppearOnActualLogDate),
            ("testLeapDayYearBoundaryAndDSTDates", checks.testLeapDayYearBoundaryAndDSTDates),
            ("testReminderPlannerSkipsRestCompletedAndPastTimes", checks.testReminderPlannerSkipsRestCompletedAndPastTimes),
            ("testInvalidReminderPreferencesAreRejected", checks.testInvalidReminderPreferencesAreRejected)
        ]
        for (name, test) in cases {
            let before = failures
            do { try test() } catch { failure("\(name): \(error)") }
            if failures == before { print("PASS: \(name)") }
        }
        let features = await runFeatureChecks()
        failures += features.failures
        let patterns = runPatternChecks(); failures += patterns.failures
        let link = await runLinkChecks(); failures += link.failures
        let meds = await runMedChecks(); failures += meds.failures
        let notes = await runNoteChecks(); failures += notes.failures
        print("\(cases.count + features.count + patterns.count + link.count + meds.count + notes.count) checks, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
