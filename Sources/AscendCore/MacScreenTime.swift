import Foundation
import SQLite3

public enum MacScreenTimeError: LocalizedError {
    case access, missing, schema, busy, invalid, limit
    public var errorDescription:String? {
        switch self {
        case .access: "macOS blocked the activity database. Allow Full Disk Access for Ascend, quit and reopen the app, then refresh Mac history."
        case .missing: "The Mac activity database is not available. Enable App & Website Activity in macOS Screen Time, use a few apps, then try again."
        case .schema: "This macOS activity database has an unsupported layout. Earlier history is retained."
        case .busy: "The Mac activity database is busy. Try refreshing again shortly."
        case .invalid: "The Mac returned invalid app-usage records. Earlier history is retained."
        case .limit: "The Mac usage query exceeded its safety limit. Earlier history is retained."
        }
    }
}
public struct MacUsageInterval:Equatable,Sendable {
    public var bundleID:String
    public var start:Double
    public var end:Double
    public init(bundleID:String,start:Double,end:Double) { self.bundleID=bundleID;self.start=start;self.end=end }
}
/// Reads only this Mac's /app/usage rows. Never opens Apple's database writable, creates a copy, or reads web/notification streams.
/// Source-device convention documented by tobias-x/screentime-archive: no ZSOURCE.ZDEVICEID denotes local rows.
public enum MacUsageReader {
    public static var defaultURL:URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Knowledge/knowledgeC.db") }
    public static func read(_ url:URL, from start:Date, to end:Date) throws -> [MacUsageInterval] {
        var db:OpaquePointer?
        let rc=sqlite3_open_v2(url.path,&db,SQLITE_OPEN_READONLY|SQLITE_OPEN_FULLMUTEX,nil)
        guard rc==SQLITE_OK,let db else {
            if let db { sqlite3_close(db) }
            if !FileManager.default.fileExists(atPath:url.path) { throw MacScreenTimeError.missing }
            throw MacScreenTimeError.access
        }
        defer { sqlite3_close(db) }
        guard sqlite3_db_readonly(db,"main")==1 else { throw MacScreenTimeError.access }
        sqlite3_busy_timeout(db,1500)
        let sql="""
        SELECT o.ZVALUESTRING, o.ZSTARTDATE, o.ZENDDATE
        FROM ZOBJECT o LEFT JOIN ZSOURCE s ON s.Z_PK=o.ZSOURCE
        WHERE o.ZSTREAMNAME='/app/usage' AND COALESCE(s.ZDEVICEID,'')=''
          AND o.ZVALUESTRING IS NOT NULL AND length(o.ZVALUESTRING)>0
          AND o.ZENDDATE>o.ZSTARTDATE AND o.ZENDDATE>? AND o.ZSTARTDATE<?
        ORDER BY o.ZSTARTDATE LIMIT 200001
        """
        var statement:OpaquePointer?
        let prepared=sqlite3_prepare_v2(db,sql,-1,&statement,nil)
        guard prepared==SQLITE_OK,let statement else {
            if let statement { sqlite3_finalize(statement) }
            if [SQLITE_AUTH,SQLITE_PERM,SQLITE_CANTOPEN].contains(prepared) { throw MacScreenTimeError.access }
            if prepared==SQLITE_BUSY || prepared==SQLITE_LOCKED { throw MacScreenTimeError.busy }
            throw MacScreenTimeError.schema
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement,1,start.timeIntervalSinceReferenceDate)
        sqlite3_bind_double(statement,2,end.timeIntervalSinceReferenceDate)
        var intervals:[MacUsageInterval]=[]
        while true {
            try Task.checkCancellation()
            let step=sqlite3_step(statement)
            if step==SQLITE_DONE { break }
            guard step==SQLITE_ROW else {
                if step==SQLITE_BUSY || step==SQLITE_LOCKED { throw MacScreenTimeError.busy }
                if step==SQLITE_AUTH || step==SQLITE_PERM { throw MacScreenTimeError.access }
                throw MacScreenTimeError.invalid
            }
            guard let text=sqlite3_column_text(statement,0),sqlite3_column_type(statement,1) != SQLITE_NULL,sqlite3_column_type(statement,2) != SQLITE_NULL else { throw MacScreenTimeError.invalid }
            let id=String(cString:text),a=sqlite3_column_double(statement,1)+Date.timeIntervalBetween1970AndReferenceDate,b=sqlite3_column_double(statement,2)+Date.timeIntervalBetween1970AndReferenceDate
            guard !id.isEmpty,id.count<=250,id.allSatisfy({$0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0))}),a.isFinite,b.isFinite,a>=946684800,b>a,b-a<=7*86400 else { throw MacScreenTimeError.invalid }
            intervals.append(MacUsageInterval(bundleID:id,start:max(a,start.timeIntervalSince1970),end:min(b,end.timeIntervalSince1970)))
            guard intervals.count<=200000 else { throw MacScreenTimeError.limit }
        }
        return intervals
    }
}
public enum MacUsageSummary {
    private struct Span { var start:Double;var end:Double }
    private static func union(_ input:[Span])->[Span] {
        var result:[Span]=[]
        for x in input.sorted(by:{$0.start<$1.start}) where x.end>x.start {
            if let last=result.last,last.end>=x.start { result[result.count-1].end=max(last.end,x.end) }
            else { result.append(x) }
        }
        return result
    }
    /// Missing days stay unknown. A union of recorded app intervals is app-use time, not full display-on time.
    public static func days(_ intervals:[MacUsageInterval],from start:Date,to end:Date,zone:TimeZone) throws -> [ScreenTimeDay] {
        guard end>start,end.timeIntervalSince(start)<=32*86400,intervals.count<=200000 else { throw MacScreenTimeError.invalid }
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=zone
        guard calendar.startOfDay(for:start)==start else { throw MacScreenTimeError.invalid }
        for i in intervals { guard i.start.isFinite,i.end.isFinite,i.end>i.start,i.start>=start.timeIntervalSince1970,i.end<=end.timeIntervalSince1970 else { throw MacScreenTimeError.invalid } }
        let grouped=Dictionary(grouping:intervals,by:\.bundleID)
        guard grouped.count<=1000 else { throw MacScreenTimeError.limit }
        let apps=grouped.mapValues { union($0.map { Span(start:$0.start,end:$0.end) }) }
        let all=union(intervals.map { Span(start:$0.start,end:$0.end) })
        var result:[ScreenTimeDay]=[];var date=start
        while date<end {
            try Task.checkCancellation()
            let next=calendar.date(byAdding:.day,value:1,to:date)!,a=date.timeIntervalSince1970,b=min(next,end).timeIntervalSince1970
            var total=0.0,hours:[Double:Double]=[:],appRows:[ScreenTimeApp]=[]
            for x in all {
                var t=max(x.start,a);let stop=min(x.end,b)
                guard stop>t else { continue }
                total+=stop-t
                while t<stop {
                    guard let hour=calendar.dateInterval(of:.hour,for:Date(timeIntervalSince1970:t)),hour.end.timeIntervalSince1970>t else { throw MacScreenTimeError.invalid }
                    let boundary=min(stop,hour.end.timeIntervalSince1970)
                    hours[hour.start.timeIntervalSince1970,default:0]+=boundary-t;t=boundary
                }
            }
            for (id,spans) in apps {
                let seconds=spans.reduce(0.0) { $0+max(0,min($1.end,b)-max($1.start,a)) }
                if seconds>0 { appRows.append(ScreenTimeApp(packageName:id,label:id,seconds:seconds)) }
            }
            let day=ScreenTimeDay(start:a,end:b,timeZoneID:zone.identifier,screenSeconds:total>0 ? total:nil,complete:false,
                                  apps:appRows.sorted{$0.packageName<$1.packageName},hours:hours.map{ScreenTimeHour(start:$0.key,seconds:$0.value)}.sorted{$0.start<$1.start})
            try day.validate();result.append(day);date=next
        }
        return result
    }
}
