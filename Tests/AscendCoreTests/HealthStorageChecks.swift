import Foundation
import AscendCore

private struct StorageFailure: Error { let message: String }
private func expect(_ test: Bool, _ message: String = "Assertion failed") throws { if !test { throw StorageFailure(message: message) } }

func runHealthStorageChecks() async -> (count: Int, failures: Int) {
    var count = 0, failures = 0
    func check(_ name: String, _ body: () throws -> Void) {
        count += 1
        do { try body(); print("PASS: \(name)") } catch { failures += 1; print("FAIL: \(name): \(error)") }
    }
    let now = Date(timeIntervalSince1970: 1_793_000_000)
    let old = now.timeIntervalSince1970 - 20 * 86_400, recent = now.timeIntervalSince1970 - 3 * 86_400
    /// A night of readings: heart rate every 40 s for 6 hours with a dip, SpO2 every 2 minutes.
    func night(from start: Double, prefix: String) -> [HealthRecord] {
        var list: [HealthRecord] = []
        for i in 0..<540 {
            let t = start + Double(i) * 40
            list.append(HealthRecord(id: "\(prefix)-hr-\(i)", metric: .heartRate, start: t, end: t, value: i == 300 ? 47 : 52 + Double(i % 9)))
        }
        for i in 0..<180 { let t = start + Double(i) * 120; list.append(HealthRecord(id: "\(prefix)-o2-\(i)", metric: .oxygen, start: t, end: t, value: i == 90 ? 89 : 95 + Double(i % 4))) }
        list.append(HealthRecord(id: "\(prefix)-sleep", metric: .sleep, start: start, end: start + 6 * 3600, value: 6))
        return list
    }

    check("old heart rate and SpO2 become 5-minute summaries with the same resting HR, averages and counts; recent days stay raw") {
        var archive = HealthArchive()
        archive.records = night(from: old, prefix: "old") + night(from: recent, prefix: "new")
        let oldNight = archive.records.first { $0.id == "old-sleep" }!, newNight = archive.records.first { $0.id == "new-sleep" }!
        let before = archive.nightVitals(oldNight), beforeRecent = archive.nightVitals(newNight)
        let compacted = archive.compacted(now: now)
        try compacted.validate()
        let after = compacted.nightVitals(oldNight)
        try expect(after.restingHeartRate == 47 && after.restingHeartRate == before.restingHeartRate && after.lowestOxygen == 89, "lows \(String(describing: after)) vs \(String(describing: before))")
        try expect(after.heartSamples == before.heartSamples && after.oxygenSamples == before.oxygenSamples, "counts \(after.heartSamples)/\(before.heartSamples) \(after.oxygenSamples)/\(before.oxygenSamples)")
        try expect(abs(after.averageHeartRate! - before.averageHeartRate!) < 0.1 && abs(after.averageOxygen! - before.averageOxygen!) < 0.1, "averages")
        try expect(compacted.nightVitals(newNight) == beforeRecent, "Recent nights are untouched")
        let oldHeart = compacted.records.filter { $0.metric == .heartRate && $0.start < now.timeIntervalSince1970 - 16 * 86_400 }
        try expect((72...73).contains(oldHeart.count) && oldHeart.allSatisfy { $0.samples != nil && $0.detail == "5-minute summary" }, "6 hours → about 72 buckets")
        try expect(compacted.records.count <= archive.records.count - 560 && compacted.records.filter { $0.metric == .sleep }.count == 2, "The old night shrinks from 720 readings to about 150 summaries")
        try expect(compacted.compacted(now: now) == compacted, "Compacting again changes nothing")
        let later = compacted.compacted(now: now.addingTimeInterval(14 * 86_400))
        try expect(later.nightVitals(newNight).restingHeartRate == 47 && later.nightVitals(newNight).heartSamples == beforeRecent.heartSamples, "later \(String(describing: later.nightVitals(newNight)))")
    }
    check("workout heart rate is thinned to one reading per 5 seconds; summaries and other types pass through") {
        let workout = (0..<600).map { HealthRecord(id: "w\($0)", metric: .heartRate, start: old + Double($0), end: old + Double($0), value: 120 + Double($0 % 30)) }
        let summary = HealthRecord(id: "5m-1", metric: .heartRate, start: old - 600, end: old - 301, value: 60, low: 55, high: 66, samples: 7)
        let steps = HealthRecord(id: "s", metric: .steps, start: old, end: old + 60, value: 100)
        let thinned = HealthArchive.thinned(workout + [summary, steps])
        try expect(thinned.filter { $0.metric == .heartRate && $0.samples == nil }.count == 120 && thinned.contains(summary) && thinned.contains(steps))
    }
    check("a sync never replaces summaries, and invalid summaries are rejected") {
        var archive = HealthArchive()
        archive.records = night(from: old, prefix: "old")
        archive = archive.compacted(now: now)
        let summaries = archive.records.filter { $0.samples != nil }
        let start = now.timeIntervalSince1970 - 14 * 86_400
        let snapshot = HealthSnapshot(requestID: UUID().uuidString, generatedAt: now.timeIntervalSince1970, rangeStart: start, rangeEnd: now.timeIntervalSince1970,
                                      permissions: Dictionary(uniqueKeysWithValues: HealthMetric.allCases.map { ($0.rawValue, true) }), records: night(from: recent, prefix: "new"))
        let merged = try archive.merging(snapshot, expectedRequestID: snapshot.requestID, now: now)
        try expect(summaries.allSatisfy(merged.records.contains) && merged.records.contains { $0.id == "new-hr-0" })
        for bad in [HealthRecord(id: "x", metric: .steps, start: old, end: old, value: 1, low: 1, high: 1, samples: 1),
                    HealthRecord(id: "y", metric: .heartRate, start: old, end: old, value: 80, low: 90, high: 95, samples: 3),
                    HealthRecord(id: "z", metric: .heartRate, start: old, end: old, value: 60, low: 50, high: 70, samples: 0)] {
            do { try bad.validate(); throw StorageFailure(message: "Expected rejection of \(bad.id)") } catch is ValidationError {}
        }
    }
    check("tracker.json can leave watch data out while exported backups keep it; older files with watch data still load") {
        var doc = TrackerDocument.seeded(today: "2026-10-20")
        doc.health.records = night(from: recent, prefix: "n")
        doc.health.lastSync = recent
        let full = try JSONEncoder().encode(doc)
        let encoder = JSONEncoder(); encoder.userInfo[TrackerDocument.omitHealth] = true
        let slim = try encoder.encode(doc)
        let json = try JSONSerialization.jsonObject(with: slim) as! [String: Any]
        try expect(json["health"] == nil && slim.count < full.count / 10)
        let reloaded = try JSONDecoder().decode(TrackerDocument.self, from: slim)
        try expect(reloaded.health == HealthArchive() && reloaded.habits == doc.habits)
        try expect(try JSONDecoder().decode(TrackerDocument.self, from: full).health == doc.health)
    }
    return (count, failures)
}
