import Foundation
import AscendCore

private struct ReportFailure: Error { let message: String }
private func expect(_ test: Bool, _ message: String = "Assertion failed") throws { if !test { throw ReportFailure(message: message) } }

func runHealthReportChecks() -> (count: Int, failures: Int) {
    var count = 0, failures = 0
    func check(_ name: String, _ body: () throws -> Void) {
        count += 1
        do { try body(); print("PASS: \(name)") } catch { failures += 1; print("FAIL: \(name): \(error)") }
    }

    var doc = TrackerDocument.seeded(today: "2026-11-03", timeZoneID: "Asia/Kolkata")
    doc.routine.configured = true; doc.routine.bedMinute = 60; doc.routine.wakeMinute = 540
    let engine = TrackerEngine(document: doc)
    let day = "2026-11-03", midnight = engine.calendar.startOfDay(for: engine.date(day)!).timeIntervalSince1970
    func at(_ day: String, _ hour: Double) -> Double { engine.calendar.startOfDay(for: engine.date(day)!).timeIntervalSince1970 + hour * 3600 }
    var records: [HealthRecord] = []
    // 14 earlier days of resting heart rate around 50, then today's 50.
    for back in 1...14 { let d = engine.adding(-back, to: day); records.append(HealthRecord(id: "rhr-\(d)", metric: .restingHeartRate, start: at(d, 0), end: at(d, 0) + 86_399, value: back % 2 == 0 ? 49 : 51)) }
    records.append(HealthRecord(id: "rhr-today", metric: .restingHeartRate, start: midnight, end: midnight + 86_399, value: 50))
    // Last night 1:54 am → 8:34 am with stages: 6 h 40 m asleep.
    let bed = at(day, 1.9), wake = bed + 400 * 60
    let stages = [SleepStage(start: bed, end: bed + 128 * 60, kind: .deep), SleepStage(start: bed + 128 * 60, end: bed + 207 * 60, kind: .rem),
                  SleepStage(start: bed + 207 * 60, end: wake, kind: .light)]
    records.append(HealthRecord(id: "night", metric: .sleep, start: bed, end: wake, value: 400.0 / 60, stages: stages))
    for i in 0..<144 {
        let t = midnight + Double(i) * 600
        let asleep = t >= bed && t <= wake
        records.append(HealthRecord(id: "hr-\(i)", metric: .heartRate, start: t, end: t, value: asleep ? 54 : 72))
        records.append(HealthRecord(id: "st-\(i)", metric: .stress, start: t, end: t, value: asleep ? 17 : 35))
    }
    records.append(HealthRecord(id: "steps", metric: .steps, start: midnight, end: midnight + 3600, value: 4384))
    var archive = HealthArchive(); archive.records = records.sorted { $0.start < $1.start }

    check("the daily report reads resting heart rate, baseline, sleep against plan and overnight stress") {
        let r = archive.report(on: day, document: doc)
        try expect(r.restingHeartRate == 50 && r.restingSource == "Mi Fitness" && r.restingBaseline == 50, "resting \(String(describing: r.restingHeartRate)) \(String(describing: r.restingBaseline))")
        try expect(r.restingSeries.count == 15 && r.asleepMinutes == 400 && r.planMinutes == 480, "sleep \(String(describing: r.asleepMinutes))")
        try expect(r.overnightStress == 17 && r.heart.count == 144 && r.stress.count == 144, "stress \(String(describing: r.overnightStress))")
        try expect(r.drift?.bedtime == 54, "bedtime drift \(String(describing: r.drift))")
        try expect(r.trend.count == 8 && r.trend.last?.steps == 4384)
    }
    check("recovery weighs resting heart rate, sleep and stress; a raised resting heart rate lowers it and raises a signal") {
        let r = archive.report(on: day, document: doc)
        // 100 (at baseline) × 0.4 + 83.3 (400 of 480 min) × 0.4 + 100 (stress 17) × 0.2 = 93.
        try expect(r.recovery?.score == 93 && r.recovery?.label == "Good", "score \(String(describing: r.recovery))")
        try expect(r.headline == "Recovered, but short on sleep.", r.headline)
        try expect(r.summary.contains("54 m later than planned"), r.summary)
        var raised = archive
        raised.records.removeAll { $0.id == "rhr-today" }
        raised.records.append(HealthRecord(id: "rhr-today", metric: .restingHeartRate, start: midnight, end: midnight + 86_399, value: 57))
        let worse = raised.report(on: day, document: doc)
        try expect((worse.recovery?.score ?? 100) < 70 && worse.signals.first?.title == "Resting heart rate is up", "raised \(String(describing: worse.recovery)) \(worse.signals.map(\.title))")
    }
    check("a day without watch data says so instead of inventing numbers") {
        let r = HealthArchive().report(on: day, document: doc)
        try expect(!r.hasData && r.recovery == nil && r.signals.isEmpty && r.headline.hasPrefix("No watch data"))
    }
    check("report times read as 12-hour clock times") {
        try expect(HealthReport.clock(114) == "1:54 am" && HealthReport.clock(0) == "12:00 am" && HealthReport.clock(14 * 60 + 38) == "2:38 pm" && HealthReport.clock(-60) == "11:00 pm")
        try expect(HealthReport.duration(400) == "6 h 40 m" && HealthReport.duration(45) == "45 m")
    }

    if let folder = ProcessInfo.processInfo.environment["ASCEND_REPORT_DIR"] {
        // Opt-in: prints the report for real data from a data folder, read-only.
        count += 1
        do {
            let base = URL(fileURLWithPath: folder)
            var real = try JSONDecoder().decode(TrackerDocument.self, from: Data(contentsOf: base.appendingPathComponent("tracker.json")))
            real.health = try JSONDecoder().decode(HealthArchive.self, from: Data(contentsOf: base.appendingPathComponent("health.json")))
            let today = TrackerEngine(document: real).key(Date())
            let started = Date()
            let r = real.health.report(on: today, document: real)
            print("  report \(today) in \(Int(Date().timeIntervalSince(started) * 1000)) ms: \(r.headline) \(r.summary)")
            print("  recovery \(String(describing: r.recovery)) · resting \(String(describing: r.restingHeartRate)) base \(String(describing: r.restingBaseline))")
            print("  stress avg \(String(describing: r.stressAverage)) · heart \(r.heartReadings) · steps \(String(describing: r.steps)) goal \(String(describing: r.stepGoal))")
            for s in r.signals { print("  signal [\(s.tone.rawValue)] \(s.title): \(s.detail)") }
            print("PASS: real-data health report")
        } catch { failures += 1; print("FAIL: real-data health report: \(error)") }
    }
    return (count, failures)
}
