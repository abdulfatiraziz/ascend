import Foundation
import AscendCore

private struct XiaomiFailure: Error { let message: String }
private func expect(_ test: Bool, _ message: String = "Assertion failed") throws { if !test { throw XiaomiFailure(message: message) } }

func runXiaomiChecks() async -> (count: Int, failures: Int) {
    var count = 0, failures = 0
    func check(_ name: String, _ body: () throws -> Void) {
        count += 1
        do { try body(); print("PASS: \(name)") } catch { failures += 1; print("FAIL: \(name): \(error)") }
    }
    let now = Date(timeIntervalSince1970: 1_793_700_000)

    check("Mi Fitness cloud requests are signed and RC4-encrypted exactly like the reference client") {
        // Vectors from the Python client that worked against the live service, with a fixed key and nonce.
        let ssecurity = "AAECAwQFBgcICQoLDA0ODw==", nonce = "CQgHBgUEAwIByCVw"
        try expect(try XiaomiCloud.signedNonce(ssecurity: ssecurity, nonce: nonce) == "XDhKPl2XL3l3D3M4w6/3zCC6eqR0vufRHlqZS4Vp56I=")
        let query = try XiaomiCloud.encryptedQuery(path: "/app/v1/data/get_fitness_data_by_time",
                                                   data: #"{"end_time":1793700000,"key":"heart_rate","reverse":true}"#, nonce: nonce, ssecurity: ssecurity)
        try expect(query["data"] == "uwLnc3/hianbK7UxcCDpJIamuxg+lGc4BoaL6rS1C52Wq65ZlJAvTZ8R6qxxmd/Q8fv+xLcKd6yK", "data \(query["data"] ?? "")")
        try expect(query["rc4_hash__"] == "7e9A1k7zypw1Jzp/q7qFZFCt3B43uK0SD2o3Dw==", "rc4_hash__")
        try expect(query["signature"] == "9LPP7G/D0DLcmi5QUJmoytu2sz8=" && query["_nonce"] == nonce, "signature")
        let reply = try XiaomiCloud.decrypt(Data("uwLhcn/b3/qGYrV5JGSle8W0sVMswCpuDLyeof3jQcKshKd7\n".utf8), nonce: nonce, ssecurity: ssecurity)
        try expect((reply["code"] as? Int) == 0 && (reply["result"] as? [String: Any]) != nil, "reply")
    }

    func row(_ value: [String: Any]) -> [String: Any] {
        ["value": String(decoding: try! JSONSerialization.data(withJSONObject: value), as: UTF8.self)]
    }
    let t = now.timeIntervalSince1970
    let range = (t - 2 * 86_400)...t

    check("cloud rows become heart-rate, SpO2 and stress records; out-of-range, zero and impossible readings are skipped") {
        let heart = [row(["time": t - 600, "bpm": 61, "type": 0]), row(["time": t - 600, "bpm": 61, "type": 0]), row(["time": t - 3 * 86_400, "bpm": 70]),
                     row(["time": t - 300, "bpm": 0]), row(["time": t - 200, "bpm": 900]), ["value": "not json"]]
        let records = XiaomiCloud.records(heart: heart, oxygen: [row(["time": t - 120, "spo2": 97])], stress: [row(["time": t - 60, "stress": 37])], range: range)
        try expect(records.map(\.metric) == [.heartRate, .oxygen, .stress], "\(records.map(\.id))")
        try expect(records[0].id == "xm-hr-\(Int(t - 600))" && records[0].value == 61 && records[2].value == 37)
        try records.forEach { try $0.validate() }
    }

    check("daily resting heart rate lands on the right local day") {
        // A daily report's time is the local date's midnight written as UTC.
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let stamp = utc.date(from: DateComponents(year: 2026, month: 11, day: 2))!.timeIntervalSince1970
        let ist = TimeZone(identifier: "Asia/Kolkata")!
        let rest = XiaomiCloud.restingRecords([["time": stamp, "value": #"{"avg_rhr":52,"min_hr":42}"#], ["time": stamp - 86_400, "value": #"{"avg_hr":70}"#]],
                                              timeZone: ist, range: (stamp - 5 * 86_400)...(stamp + 2 * 86_400))
        var local = Calendar(identifier: .gregorian); local.timeZone = ist
        try expect(rest.count == 1 && rest[0].id == "xm-rhr-2026-11-02" && rest[0].value == 52, "\(rest.map(\.id))")
        try expect(rest[0].start == local.date(from: DateComponents(year: 2026, month: 11, day: 2))!.timeIntervalSince1970)
    }

    func phoneSnapshot(_ records: [HealthRecord]) -> HealthSnapshot {
        HealthSnapshot(requestID: UUID().uuidString, generatedAt: t, rangeStart: t - 86_400, rangeEnd: t,
                       permissions: Dictionary(uniqueKeysWithValues: HealthMetric.phone.map { ($0.rawValue, true) }), records: records)
    }

    func merged(_ archive: HealthArchive, _ records: [HealthRecord]) throws -> HealthArchive {
        let snapshot = phoneSnapshot(records)
        return try archive.merging(snapshot, expectedRequestID: snapshot.requestID, now: now)
    }

    check("once the cloud has synced, phone syncs keep steps and sleep but leave heart rate and SpO2 to the cloud") {
        let workoutHR = HealthRecord(id: "hc-hr", metric: .heartRate, start: t - 3600, end: t - 3600, value: 140)
        let steps = HealthRecord(id: "hc-steps", metric: .steps, start: t - 7200, end: t - 3600, value: 900)
        var archive = try merged(HealthArchive(), [workoutHR, steps])
            .mergingCloud([], range: range, now: now)
        try expect(!archive.records.contains { $0.id == "hc-hr" } && archive.records.contains { $0.id == "hc-steps" },
                   "Cloud sync replaces phone heart rate in its window")
        let cloud = XiaomiCloud.records(heart: [row(["time": t - 1800, "bpm": 58])], oxygen: [], stress: [row(["time": t - 1700, "stress": 20])], range: range)
        archive = try archive.mergingCloud(cloud, range: range, now: now)
        archive = try merged(archive, [workoutHR, HealthRecord(id: "hc-steps2", metric: .steps, start: t - 600, end: t - 60, value: 50)])
        try expect(archive.records.contains { $0.id == "xm-hr-\(Int(t - 1800))" } && archive.records.contains { $0.metric == .stress }, "Cloud records survive a phone sync")
        try expect(!archive.records.contains { $0.id == "hc-hr" } && archive.records.contains { $0.id == "hc-steps2" }, "Phone still supplies steps")
        var signedOut = archive; signedOut.cloudSync = nil
        signedOut = try merged(signedOut, [workoutHR])
        try expect(signedOut.records.contains { $0.id == "hc-hr" }, "Without the cloud, the phone supplies heart rate again")
    }

    check("phone snapshots name only the phone's types; the cloud can't write steps or out-of-range records") {
        var withStress = phoneSnapshot([])
        withStress.permissions[HealthMetric.stress.rawValue] = true
        try expect((try? withStress.validate(now: now)) == nil, "A snapshot naming cloud-only types is rejected")
        let steps = HealthRecord(id: "xm-steps", metric: .steps, start: t - 60, end: t, value: 10)
        try expect((try? HealthArchive().mergingCloud([steps], range: range, now: now)) == nil)
        let ancient = HealthRecord(id: "xm-hr-1", metric: .heartRate, start: t - 30 * 86_400, end: t - 30 * 86_400, value: 60)
        try expect((try? HealthArchive().mergingCloud([ancient], range: range, now: now)) == nil)
    }

    if ProcessInfo.processInfo.environment["ASCEND_LIVE_XIAOMI"] != nil {
        // Opt-in: reads the last day from a real account. ASCEND_LIVE_XIAOMI is a JSON session file; nothing is saved.
        count += 1
        do {
            let file = ProcessInfo.processInfo.environment["ASCEND_LIVE_XIAOMI"]!
            let session = try JSONDecoder().decode(XiaomiSession.self, from: Data(contentsOf: URL(fileURLWithPath: file)))
            let (records, _) = try await XiaomiCloud.fetch(session, days: 1, timeZone: .current)
            let by = Dictionary(grouping: records, by: \.metric).mapValues(\.count)
            print("  live cloud: \(by.map { "\($0.key.rawValue) \($0.value)" }.sorted().joined(separator: ", "))")
            try expect((by[.heartRate] ?? 0) > 100, "Expected all-day heart rate")
            print("PASS: live Mi Fitness cloud read")
        } catch { failures += 1; print("FAIL: live Mi Fitness cloud read: \(error)") }
    }
    return (count, failures)
}
