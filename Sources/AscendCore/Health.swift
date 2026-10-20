import Foundation

public enum HealthMetric: String, Codable, CaseIterable, Sendable {
    case heartRate, steps, sleep, oxygen, distance, activeEnergy, speed, elevation, workout
    public var title: String { switch self {
        case .heartRate: "Heart rate"; case .steps: "Steps"; case .sleep: "Sleep"; case .oxygen: "Blood oxygen"
        case .distance: "Distance"; case .activeEnergy: "Activity energy"; case .speed: "Speed"; case .elevation: "Elevation"; case .workout: "Workouts"
    } }
    public var unit: String { switch self {
        case .heartRate: "bpm"; case .steps: "steps"; case .sleep: "hours"; case .oxygen: "%"
        case .distance, .elevation: "m"; case .activeEnergy: "kcal"; case .speed: "m/s"; case .workout: "minutes"
    } }
    var bounds: ClosedRange<Double> { switch self {
        case .heartRate: 1...400; case .steps: 0...1_000_000; case .sleep: 0...72; case .oxygen: 0...100
        case .distance: 0...10_000_000; case .activeEnergy: 0...100_000; case .speed: 0...1000; case .elevation: 0...100_000; case .workout: 0...10080
    } }
}
/// Health Connect sleep stage types, as Mi Fitness reports them.
public enum SleepStageKind: String, Codable, CaseIterable, Sendable {
    case awake, light, deep, rem, asleep, outOfBed, awakeInBed, unknown
    public var title: String {
        switch self {
        case .awake: "Awake"; case .light: "Light"; case .deep: "Deep"; case .rem: "REM"; case .asleep: "Asleep"
        case .outOfBed: "Out of bed"; case .awakeInBed: "Awake in bed"; case .unknown: "Unknown"
        }
    }
    public var isAsleep: Bool { [.light, .deep, .rem, .asleep].contains(self) }
    /// Chart row from top (awake) to bottom (deep).
    public var depth: Int {
        switch self { case .awake, .awakeInBed, .outOfBed, .unknown: 0; case .rem: 1; case .light, .asleep: 2; case .deep: 3 }
    }
}
public struct SleepStage: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var kind: SleepStageKind
    public init(start: Double, end: Double, kind: SleepStageKind) { self.start = start; self.end = end; self.kind = kind }
    public var minutes: Double { (end - start) / 60 }
}
public struct HealthRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var metric: HealthMetric
    public var start: Double
    public var end: Double
    public var value: Double
    public var detail: String
    public var device: String
    /// Sleep only, from Ascend Bridge 0.2.1+. Older imports have none.
    public var stages: [SleepStage]?
    public init(id: String, metric: HealthMetric, start: Double, end: Double, value: Double, detail: String = "", device: String = "", stages: [SleepStage]? = nil) {
        self.id = id; self.metric = metric; self.start = start; self.end = end; self.value = value; self.detail = detail; self.device = device; self.stages = stages
    }
    public func validate() throws {
        guard !id.isEmpty, id.count <= 200, start.isFinite, end.isFinite, (946684800...7289654399).contains(start), end >= start,
              end - start <= 7 * 86400, value.isFinite, metric.bounds.contains(value), detail.count <= 200, device.count <= 120 else {
            throw ValidationError(message: "Invalid watch record. No data was imported.")
        }
        if let stages {
            guard metric == .sleep, stages.count <= 1000, stages.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start < $0.end && $0.start >= start - 60 && $0.end <= end + 60 }) else {
                throw ValidationError(message: "Invalid sleep stages. No data was imported.")
            }
        }
    }
    var identity: String { "\(metric.rawValue):\(id)" }
    /// Minutes per stage, ignoring stages that overlap one already counted.
    public var stageMinutes: [SleepStageKind: Double] {
        var totals: [SleepStageKind: Double] = [:], covered = start - 1
        for stage in (stages ?? []).sorted(by: { $0.start < $1.start }) {
            let from = max(stage.start, covered)
            guard stage.end > from else { continue }
            totals[stage.kind, default: 0] += (stage.end - from) / 60; covered = stage.end
        }
        return totals
    }
}
public struct HealthSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var requestID: String
    public var generatedAt: Double
    public var rangeStart: Double
    public var rangeEnd: Double
    public var sourcePackage: String
    public var permissions: [String: Bool]
    public var errors: [String: String]
    public var records: [HealthRecord]
    public init(requestID: String, generatedAt: Double, rangeStart: Double, rangeEnd: Double, permissions: [String: Bool], errors: [String: String] = [:], records: [HealthRecord]) {
        version = 1; self.requestID = requestID; self.generatedAt = generatedAt; self.rangeStart = rangeStart; self.rangeEnd = rangeEnd
        sourcePackage = "com.xiaomi.wearable"; self.permissions = permissions; self.errors = errors; self.records = records
    }
    public func validate(expectedRequestID: String? = nil, now: Date = Date()) throws {
        let known = Set(HealthMetric.allCases.map(\.rawValue))
        guard version == 1, sourcePackage == "com.xiaomi.wearable", UUID(uuidString: requestID) != nil,
              expectedRequestID.map({ $0.caseInsensitiveCompare(requestID) == .orderedSame }) ?? true,
              generatedAt.isFinite, rangeStart.isFinite, rangeEnd.isFinite,
              rangeStart >= 946684800, rangeStart < rangeEnd, rangeEnd - rangeStart <= 15 * 86400,
              rangeEnd <= generatedAt, generatedAt <= now.timeIntervalSince1970 + 300,
              now.timeIntervalSince1970 - generatedAt < 300,
              Set(permissions.keys) == known, Set(errors.keys).isSubset(of: known), errors.values.allSatisfy({ $0.count <= 300 }),
              records.count <= 100_000, Set(records.map(\.identity)).count == records.count else {
            throw ValidationError(message: "The phone returned an invalid or stale snapshot. Sync again.")
        }
        for record in records {
            try record.validate()
            guard permissions[record.metric.rawValue] == true, record.start >= rangeStart - 7 * 86400, record.end <= rangeEnd + 1,
                  record.end >= rangeStart else { throw ValidationError(message: "Watch record falls outside the permitted snapshot.") }
        }
    }
}
public struct HealthArchive: Codable, Equatable, Sendable {
    public var records: [HealthRecord] = []
    public var lastSync: Double?
    public var permissions: [String: Bool] = [:]
    public var errors: [String: String] = [:]
    /// Check-in values Ascend wrote from watch data, keyed "habitID|day", so typed values are never overwritten.
    public var filled: [String: Double]?
    public init() {}
    public func validate() throws {
        let known = Set(HealthMetric.allCases.map(\.rawValue))
        guard records.count <= 500_000, Set(records.map(\.identity)).count == records.count,
              (filled?.count ?? 0) <= 20_000, filled?.values.allSatisfy(\.isFinite) ?? true,
              lastSync.map({ $0.isFinite && (946684800...7289654399).contains($0) }) ?? true,
              Set(permissions.keys).isSubset(of: known), Set(errors.keys).isSubset(of: known), errors.values.allSatisfy({ $0.count <= 300 }) else {
            throw ValidationError(message: "Invalid local watch archive.")
        }
        try records.forEach { try $0.validate() }
    }
    public func merging(_ snapshot: HealthSnapshot, expectedRequestID: String, now: Date = Date()) throws -> Self {
        try snapshot.validate(expectedRequestID: expectedRequestID, now: now)
        var result = self
        let readable = Set(HealthMetric.allCases.filter { snapshot.permissions[$0.rawValue] == true && snapshot.errors[$0.rawValue] == nil })
        guard !readable.isEmpty else { throw ValidationError(message: "No watch data could be read. Choose permissions in Ascend Bridge on your phone, keep it open, then sync again.") }
        // Replace only successfully queried types in the refreshed window. Keep older history,
        // denied types and failed types intact. Stable IDs also handle edited source timestamps.
        let incoming = snapshot.records.filter { readable.contains($0.metric) }
        let incomingIDs = Set(incoming.map(\.identity))
        result.records.removeAll { incomingIDs.contains($0.identity) || (readable.contains($0.metric) && $0.end >= snapshot.rangeStart && $0.start <= snapshot.rangeEnd) }
        result.records.append(contentsOf: incoming)
        result.records.sort { $0.start < $1.start }
        result.lastSync = snapshot.generatedAt; result.permissions = snapshot.permissions; result.errors = snapshot.errors
        try result.validate()
        return result
    }
    public func records(_ metric: HealthMetric, on day: String, engine: TrackerEngine) -> [HealthRecord] {
        records.filter { $0.metric == metric && engine.key(Date(timeIntervalSince1970: metric == .sleep ? $0.end : $0.start)) == day }
    }
    /// Sleep sessions ending on `day`, longest first. Mi Fitness can write several growing copies of one night
    /// (same start, later ends) as the watch syncs; overlapping sessions collapse to the most complete copy.
    public func sleepSessions(on day: String, engine: TrackerEngine) -> [HealthRecord] {
        var clusters: [[HealthRecord]] = []
        for record in records(.sleep, on: day, engine: engine).sorted(by: { $0.start < $1.start }) {
            if let last = clusters.last, record.start < last.map(\.end).max()! { clusters[clusters.count - 1].append(record) }
            else { clusters.append([record]) }
        }
        return clusters.map { cluster in
            cluster.max { a, b in
                if a.end != b.end { return a.end < b.end }
                if (a.detail == "Asleep stages") != (b.detail == "Asleep stages") { return b.detail == "Asleep stages" }
                return a.value < b.value
            }!
        }.sorted { ($0.end - $0.start) > ($1.end - $1.start) }
    }
}
