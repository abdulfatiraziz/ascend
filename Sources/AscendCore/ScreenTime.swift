import Foundation

public struct ScreenTimeApp: Codable, Equatable, Identifiable, Sendable {
    public var packageName: String
    public var label: String
    public var seconds: Double
    public var id: String { packageName }
}
public struct ScreenTimeHour: Codable, Equatable, Identifiable, Sendable {
    public var start: Double
    public var seconds: Double
    public var id: Double { start }
}
public struct ScreenTimeDay: Codable, Equatable, Identifiable, Sendable {
    public var start: Double
    public var end: Double
    public var timeZoneID: String?

    public var screenSeconds: Double?
    public var complete: Bool
    public var apps: [ScreenTimeApp]
    public var hours: [ScreenTimeHour]
    public var id: Double { start }
    public func validate() throws {
        let duration=end-start
        guard start.isFinite, end.isFinite, start >= 946684800, (0...93601).contains(duration),
              screenSeconds.map({ $0.isFinite && (0...(duration+1)).contains($0) }) ?? !complete,
              timeZoneID.map({ TimeZone(identifier:$0) != nil }) ?? true,
              apps.count <= 1000, Set(apps.map(\.packageName)).count == apps.count,
              hours.count <= 26, Set(hours.map(\.start)).count == hours.count else { throw ValidationError(message: "Invalid screen-time day.") }
        for app in apps {
            guard !app.packageName.isEmpty, app.packageName.count <= 250, app.packageName.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }),
                  !app.label.isEmpty, app.label.count <= 200, app.seconds.isFinite, app.seconds > 0,
                  app.seconds <= (screenSeconds ?? 0)+1 else { throw ValidationError(message: "Invalid app-usage summary.") }
        }
        for hour in hours {
            guard hour.start.isFinite, hour.start >= start, hour.start < end, hour.seconds.isFinite,
                  hour.seconds > 0, hour.seconds <= min(3600,end-hour.start)+1 else { throw ValidationError(message: "Invalid hourly usage summary.") }
        }
        guard abs(hours.reduce(0) { $0+$1.seconds }-(screenSeconds ?? 0)) <= 1 else { throw ValidationError(message: "Screen-time hour totals do not match.") }
    }
}
public struct ScreenTimeSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var generatedAt: Double
    public var timeZoneID: String
    public var status: String
    public var days: [ScreenTimeDay]
    public func validate(now: Date = Date()) throws {
        guard version == 1, generatedAt.isFinite, abs(now.timeIntervalSince1970-generatedAt) <= 600,
              let zone=TimeZone(identifier: timeZoneID), ["allowed","disabled","denied","unavailable"].contains(status) else { throw ValidationError(message: "Invalid or stale screen-time snapshot.") }
        if status != "allowed" {
            guard days.isEmpty else { throw ValidationError(message: "Screen-time data was sent without usage access.") };return
        }
        guard days.count == 7, Set(days.map(\.start)).count == 7 else { throw ValidationError(message: "Incomplete screen-time snapshot.") }
        var calendar=Calendar(identifier: .gregorian);calendar.timeZone=zone
        let today=calendar.startOfDay(for: Date(timeIntervalSince1970: generatedAt))
        for (index, day) in days.enumerated() {
            try day.validate()
            let date=calendar.date(byAdding: .day, value: index-6, to: today)!
            let end=min(calendar.date(byAdding: .day,value: 1,to: date)!.timeIntervalSince1970,generatedAt)
            guard abs(day.start-date.timeIntervalSince1970)<1, abs(day.end-end)<1 else { throw ValidationError(message: "Screen-time dates do not match the phone's time zone.") }
        }
    }
}
public struct ScreenTimeDevice: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var status: String
    public var timeZoneID: String
    public var lastSync: Double
    public var days: [ScreenTimeDay]
    public var source: String? = nil
}
/// Separate local archive; excluded from the tracker/watch files and automatic assistant context.
public struct ScreenTimeArchive: Codable, Equatable, Sendable {
    public var version = 1
    public var devices: [ScreenTimeDevice] = []
    public init() {}
    public func validate() throws {
        guard version == 1, devices.count <= 16, Set(devices.map(\.id)).count == devices.count else { throw ValidationError(message: "Invalid screen-time archive.") }
        for d in devices {
            guard UUID(uuidString: d.id) != nil, d.name.count <= 200, TimeZone(identifier:d.timeZoneID) != nil,
                  d.lastSync.isFinite, d.lastSync >= 946684800, ["allowed","disabled","denied","unavailable"].contains(d.status),
                  d.source.map({ ["macKnowledge","androidUsageEvents"].contains($0) }) ?? true,
                  d.days.count <= 100, Set(d.days.map(\.start)).count == d.days.count else { throw ValidationError(message: "Invalid screen-time device.") }
            try d.days.forEach { try $0.validate(); guard $0.end <= d.lastSync+1 else { throw ValidationError(message:"Screen-time day is newer than its source.") } }
        }
    }
    public func merging(_ snapshot: ScreenTimeSnapshot, phoneID: String, phoneName: String, now: Date = Date()) throws -> Self {
        try validate();try snapshot.validate(now:now)
        guard UUID(uuidString: phoneID) != nil, phoneName.count <= 200 else { throw ValidationError(message: "Invalid screen-time source.") }
        var result=self
        let old=devices.first { $0.id==phoneID }
        guard old?.source != "macKnowledge" else { throw ValidationError(message:"A phone snapshot cannot replace the Mac source.") }
        guard old.map({ snapshot.generatedAt >= $0.lastSync }) ?? true else { throw ValidationError(message: "An older screen-time snapshot was ignored.") }
        var saved=Dictionary(uniqueKeysWithValues:(old?.days ?? []).map { ($0.start,$0) })
        if snapshot.status=="allowed" {
            for incoming in snapshot.days {
                var day=incoming;day.timeZoneID=snapshot.timeZoneID
                // Never replace a previously complete observation with a less complete event-history result.
                if let previous=saved[day.start], previous.complete && !day.complete { continue }
                saved[day.start]=day
            }
        }
        let cutoff=now.addingTimeInterval(-90*86400).timeIntervalSince1970
        let days=saved.values.filter { $0.end>=cutoff }.sorted { $0.start<$1.start }
        result.devices.removeAll { $0.id==phoneID }
        result.devices.append(ScreenTimeDevice(id:phoneID,name:phoneName,status:snapshot.status,timeZoneID:snapshot.timeZoneID,lastSync:snapshot.generatedAt,days:Array(days.suffix(100))))
        try result.validate();return result
    }
    public func mergingMac(_ days:[ScreenTimeDay],deviceID:String,name:String,zone:TimeZone,now:Date=Date()) throws -> Self {
        try validate()
        guard UUID(uuidString:deviceID) != nil,!name.isEmpty,name.count<=200,days.count<=32,
              Set(days.map(\.start)).count==days.count else { throw MacScreenTimeError.invalid }
        if let existing=devices.first(where:{$0.id==deviceID}),existing.source != "macKnowledge" { throw MacScreenTimeError.invalid }
        var saved=Dictionary(uniqueKeysWithValues:(devices.first{$0.id==deviceID}?.days ?? []).map{($0.start,$0)})
        for d in days {
            try d.validate()
            guard d.end<=now.timeIntervalSince1970+1,d.timeZoneID==zone.identifier else { throw MacScreenTimeError.invalid }
            // Empty or shortened retained history must not wipe an earlier useful observation.
            if let old=saved[d.start],let before=old.screenSeconds,(d.screenSeconds ?? 0)<before { continue }
            saved[d.start]=d
        }
        var result=self;result.devices.removeAll{$0.id==deviceID}
        let retained=saved.values.filter{$0.end>=now.timeIntervalSince1970-90*86400}.sorted{$0.start<$1.start}
        var device=ScreenTimeDevice(id:deviceID,name:name,status:"allowed",timeZoneID:zone.identifier,lastSync:now.timeIntervalSince1970,days:Array(retained.suffix(100)))
        device.source="macKnowledge";result.devices.append(device)
        try result.validate();return result
    }

}
public enum ScreenTimeStorage {
    public static func read(_ url: URL) throws -> ScreenTimeArchive {
        guard FileManager.default.fileExists(atPath:url.path) else { return ScreenTimeArchive() }
        let data=try Data(contentsOf:url)
        guard data.count<=50_000_000 else { throw ValidationError(message:"Screen-time archive is too large.") }
        let archive=try JSONDecoder().decode(ScreenTimeArchive.self,from:data);try archive.validate();return archive
    }
    public static func save(_ archive: ScreenTimeArchive, to url: URL) throws {
        try archive.validate()
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        let data=try encoder.encode(archive)
        if FileManager.default.fileExists(atPath:url.path) {
            _=try read(url)
            try Data(contentsOf:url).write(to:url.appendingPathExtension("backup"),options:.atomic)
        }
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
}
