import Foundation

/// Preserves Dr Trust's original fields, including unknown fields, zeroes and nulls.
public enum BodyValue: Codable, Equatable, Sendable {
    case number(Double), text(String), bool(Bool), null, array([BodyValue]), object([String: BodyValue])
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self), n.isFinite { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .text(s) }
        else if let a = try? c.decode([BodyValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: BodyValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let x): try c.encode(x)
        case .text(let x): try c.encode(x)
        case .bool(let x): try c.encode(x)
        case .null: try c.encodeNil()
        case .array(let x): try c.encode(x)
        case .object(let x): try c.encode(x)
        }
    }
    public var number: Double? { if case .number(let x) = self { return x }; return nil }
    public var text: String? { if case .text(let x) = self { return x }; return nil }
}

public struct BodyMeasurement: Codable, Equatable, Identifiable, Sendable {
    public let fields: [String: BodyValue]
    public var id: String { fields["id"]?.text ?? "" }
    public var userID: String { fields["userId"]?.text ?? "" }
    public var date: Date { Date(timeIntervalSince1970: (fields["createdAt"]?.number ?? 0) / 1000) }
    /// Dr Trust's FAT_SCALE_DATA measuredWeight field is kilograms; retain the raw field too.
    public var kilograms: Double { fields["measuredWeight"]?.number ?? 0 }
    public func value(_ key: String) -> Double? { fields[key]?.number }
    public init(fields: [String: BodyValue]) { self.fields = fields }
    public func validate() throws {
        guard !id.isEmpty, id.count <= 200, !userID.isEmpty, userID.count <= 200,
              kilograms.isFinite, kilograms > 0, kilograms <= 1000,
              let time = fields["createdAt"]?.number, time.isFinite,
              (946684800000...7289654399000).contains(time),
              time <= Date().timeIntervalSince1970 * 1000 + 300_000, fields.count <= 250 else {
            throw ValidationError(message: "Invalid Dr Trust measurement. No body data was imported.")
        }
    }
}

/// Kept outside tracker.json and health.json so older Mac apps and existing phone sync remain compatible.
public struct BodyArchive: Codable, Equatable, Sendable {
    public var version = 1
    public var source = "drtrust360"
    public var records: [BodyMeasurement] = []
    public init() {}
    public func validate() throws {
        guard version == 1, source == "drtrust360", records.count <= 100_000,
              Set(records.map(\.id)).count == records.count, Set(records.map(\.userID)).count <= 1 else {
            throw ValidationError(message: "Invalid body measurement archive. The existing file was preserved.")
        }
        try records.forEach { try $0.validate() }
    }
    public func merging(_ incoming: [BodyMeasurement]) throws -> Self {
        try validate()
        guard !incoming.isEmpty, Set(incoming.map(\.id)).count == incoming.count else {
            throw ValidationError(message: "The import is empty or contains duplicate measurement IDs.")
        }
        try incoming.forEach { try $0.validate() }
        guard Set((records + incoming).map(\.userID)).count == 1 else {
            throw ValidationError(message: "These readings belong to another Dr Trust profile. No data was changed.")
        }
        var merged = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for row in incoming { merged[row.id] = row }
        var result = self
        result.records = merged.values.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        try result.validate()
        return result
    }
}

public enum DrTrustImport {
    public static func read(_ data: Data) throws -> [BodyMeasurement] {
        guard data.count <= 25_000_000 else { throw ValidationError(message: "The Dr Trust file is too large.") }
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["source"] as? String == "drtrust360" {
            let archive = try JSONDecoder().decode(BodyArchive.self, from: data)
            try archive.validate()
            _ = try BodyArchive().merging(archive.records)
            return archive.records
        }
        struct Category: Decodable { let httpStatus: Int; let recordCount: Int?; let pages: [Page]? }
        struct Page: Decodable {
            let content: [[String: BodyValue]]
            let totalElements: Int; let totalPages: Int; let number: Int; let last: Bool
        }
        // Decode only the scale category: other categories may have provider-specific response shapes.
        struct Root: Decodable {
            let scale: Category
            enum Keys: String, CodingKey { case measurementTypes, FAT_SCALE_DATA }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: Keys.self)
                scale = try c.nestedContainer(keyedBy: Keys.self, forKey: .measurementTypes).decode(Category.self, forKey: .FAT_SCALE_DATA)
            }
        }
        let category = try JSONDecoder().decode(Root.self, from: data).scale
        guard category.httpStatus == 200, let pages = category.pages, !pages.isEmpty,
              pages.count == pages[0].totalPages, pages.last?.last == true,
              pages.enumerated().allSatisfy({ $0.offset == $0.element.number && $0.element.totalElements == pages[0].totalElements && $0.element.totalPages == pages.count && $0.element.last == ($0.offset == pages.count - 1) }) else {
            throw ValidationError(message: "The Dr Trust export is incomplete. All history pages are required.")
        }
        let records = pages.flatMap(\.content).map { BodyMeasurement(fields: $0) }
        guard records.count == pages[0].totalElements, records.count == category.recordCount else {
            throw ValidationError(message: "The Dr Trust export's record count does not match its pages.")
        }
        _ = try BodyArchive().merging(records)
        return records
    }
}

public enum BodyStorage {
    public static func read(_ url: URL) throws -> BodyArchive {
        guard FileManager.default.fileExists(atPath: url.path) else { return BodyArchive() }
        let data = try Data(contentsOf: url)
        guard data.count <= 50_000_000 else { throw ValidationError(message: "The body archive is too large.") }
        let archive = try JSONDecoder().decode(BodyArchive.self, from: data)
        try archive.validate()
        return archive
    }
    /// Validate first; preserve the exact previous file before an atomic replacement. Duplicate imports do not write.
    @discardableResult public static func importFile(_ data: Data, to url: URL) throws -> BodyArchive {
        try mergeRecords(DrTrustImport.read(data), to: url)
    }
    /// Successful cloud reads upsert stable IDs. Empty responses never erase saved history.
    @discardableResult public static func mergeRecords(_ records: [BodyMeasurement], to url: URL) throws -> BodyArchive {
        let previous = try read(url)
        guard !records.isEmpty else { return previous }
        let candidate = try previous.merging(records)
        guard candidate != previous else { return previous }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(candidate)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            let backup = url.deletingLastPathComponent().appendingPathComponent("body-before-import-\(UUID().uuidString).json")
            try fm.copyItem(at: url, to: backup)
        }
        try encoded.write(to: url, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return candidate
    }
}
