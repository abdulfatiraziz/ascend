import Foundation
import AscendCore

private struct BodyCheckFailure: Error { let message: String }
func runBodyMeasurementChecks() -> (count: Int, failures: Int) {
    var count = 0, failures = 0
    func expect(_ value: Bool, _ message: String = "Assertion failed") throws {
        if !value { throw BodyCheckFailure(message: message) }
    }
    func rejects(_ body: () throws -> Void) throws {
        do { try body() } catch { return }
        throw BodyCheckFailure(message: "Expected rejection")
    }
    func check(_ name: String, _ body: () throws -> Void) {
        count += 1
        do { try body(); print("PASS: \(name)") } catch { failures += 1; print("FAIL: \(name): \(error)") }
    }
    func row(_ id: String = "r1", user: String = "test-user", weight: Double = 78) -> [String: Any] {
        ["id": id, "userId": user, "createdAt": 1785041707000.0, "measuredWeight": weight,
         "bodyFatPercentage": 0, "boneMass": NSNull(), "isManual": false,
         "futureField": ["original": [1, 2, 3]]]
    }
    func export(_ rows: [[String: Any]], total: Int? = nil, last: Bool = true) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["measurementTypes": ["FAT_SCALE_DATA": ["httpStatus": 200, "recordCount": rows.count,
            "pages": [["content": rows, "totalElements": total ?? rows.count, "totalPages": 1, "number": 0, "last": last]]]]])
    }
    check("Dr Trust import preserves raw fields, units and millisecond timestamps; unrelated categories are ignored") {
        let rows = try DrTrustImport.read(export([row()]))
        try expect(rows.count == 1 && rows[0].kilograms == 78 && rows[0].date.timeIntervalSince1970 == 1785041707)
        try expect(rows[0].value("bodyFatPercentage") == 0 && rows[0].fields["boneMass"] == .null)
        try expect(rows[0].fields["futureField"] == .object(["original": .array([.number(1), .number(2), .number(3)])]))
        let encoded = try JSONEncoder().encode(BodyArchive().merging(rows))
        try expect(try JSONDecoder().decode(BodyArchive.self, from: encoded).records == rows)
        try expect(try DrTrustImport.read(encoded) == rows)
    }
    check("reimports are idempotent; same-ID corrections replace once and other history remains") {
        let first = try BodyArchive().merging(DrTrustImport.read(export([row(), row("r2")])))
        try expect(try first.merging(DrTrustImport.read(export([row()]))) == first)
        let corrected = try first.merging(DrTrustImport.read(export([row(weight: 79)])))
        try expect(corrected.records.count == 2 && corrected.records.first { $0.id == "r1" }?.kilograms == 79)
        try expect(corrected.records.first { $0.id == "r2" }?.kilograms == 78)
    }
    check("incomplete pages, duplicate IDs, mixed profiles and invalid weights reject the whole import") {
        try rejects { _ = try DrTrustImport.read(export([row()], total: 2)) }
        try rejects { _ = try DrTrustImport.read(export([row()], last: false)) }
        try rejects { _ = try DrTrustImport.read(export([row(), row()])) }
        try rejects { _ = try DrTrustImport.read(export([row(), row("r2", user: "another-user")])) }
        try rejects { _ = try DrTrustImport.read(export([row(weight: -1)])) }
        try rejects { _ = try DrTrustImport.read(export([])) }
        let old = try BodyArchive().merging(DrTrustImport.read(export([row()])))
        try rejects { _ = try old.merging(DrTrustImport.read(export([row("r2", user: "another-user")]))) }
    }
    check("body storage leaves tracker and watch bytes intact, preserves exact backups and rejects corrupt archives") {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ascend-body-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let tracker = folder.appendingPathComponent("tracker.json"), health = folder.appendingPathComponent("health.json"), body = folder.appendingPathComponent("body-measurements.json")
        try Data("unchanged tracker".utf8).write(to: tracker); try Data("unchanged watch".utf8).write(to: health)
        let first = try BodyStorage.importFile(export([row()]), to: body)
        let bytes = try Data(contentsOf: body)
        try expect(try BodyStorage.importFile(export([row()]), to: body) == first)
        try expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 3)
        _ = try BodyStorage.importFile(export([row("r2")]), to: body)
        let backup = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("body-before-import-") }!
        try expect(try Data(contentsOf: backup) == bytes)
        try expect(try Data(contentsOf: tracker) == Data("unchanged tracker".utf8))
        try expect(try Data(contentsOf: health) == Data("unchanged watch".utf8))
        let good = try Data(contentsOf: body)
        try rejects { _ = try BodyStorage.importFile(export([row(weight: -1)]), to: body) }
        try expect(try Data(contentsOf: body) == good)
        try Data("corrupt".utf8).write(to: body)
        try rejects { _ = try BodyStorage.importFile(export([row()]), to: body) }
        try expect(try Data(contentsOf: body) == Data("corrupt".utf8))
    }
    check("existing tracker and HealthMetric formats stay unchanged and do not include body data in assistant context") {
        let doc = TrackerDocument.seeded(today: "2026-11-03")
        let bytes = try JSONEncoder().encode(doc)
        let roundTrip = try JSONDecoder().decode(TrackerDocument.self, from: bytes)
        try roundTrip.validate()
        try expect(!HealthMetric.allCases.map(\.rawValue).contains("weight"))
        try expect(!String(decoding: bytes, as: UTF8.self).contains("bodyMeasurements"))
    }
    return (count, failures)
}
