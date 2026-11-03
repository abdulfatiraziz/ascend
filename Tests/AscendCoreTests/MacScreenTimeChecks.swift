import Foundation
import SQLite3
import AscendCore

private struct MacUsageCheckFailure:Error {}
func runMacScreenTimeChecks() throws -> (count:Int,failures:Int) {
    var count=0,failures=0
    func expect(_ b:Bool)throws { if !b { throw MacUsageCheckFailure() } }
    func rejects(_ body:()throws->Void)throws { do{try body()}catch{return};throw MacUsageCheckFailure() }
    func check(_ name:String,_ body:()throws->Void) {
        count+=1;do{try body();print("PASS: \(name)")}catch{failures+=1;print("FAIL: \(name): \(error)")}
    }
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent("ascend-mac-usage-\(UUID())")
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:folder)}
    let url=folder.appendingPathComponent("fixture.db")
    let zone=TimeZone(identifier:"Asia/Kolkata")!
    var c=Calendar(identifier:.gregorian);c.timeZone=zone
    let now=Date(),start=c.startOfDay(for:now.addingTimeInterval(-2*86400)),end=c.date(byAdding:.day,value:1,to:start)!
    let t=start.timeIntervalSince1970,reference=start.timeIntervalSinceReferenceDate
    var db:OpaquePointer?
    guard sqlite3_open(url.path,&db)==SQLITE_OK,let handle=db else{throw MacUsageCheckFailure()}
    let sql="""
    CREATE TABLE ZSOURCE(Z_PK INTEGER PRIMARY KEY,ZDEVICEID TEXT);
    INSERT INTO ZSOURCE VALUES(1,NULL),(2,'remote-device');
    CREATE TABLE ZOBJECT(ZSTREAMNAME TEXT,ZVALUESTRING TEXT,ZSTARTDATE REAL,ZENDDATE REAL,ZSOURCE INTEGER);
    INSERT INTO ZOBJECT VALUES('/app/usage','com.example-a',\(reference),\(reference+3600),1);
    INSERT INTO ZOBJECT VALUES('/app/usage','com.example-a',\(reference+1800),\(reference+5400),1);
    INSERT INTO ZOBJECT VALUES('/app/usage','com.example.b',\(reference+3600),\(reference+7200),1);
    INSERT INTO ZOBJECT VALUES('/app/usage','com.remote.app',\(reference),\(reference+20000),2);
    INSERT INTO ZOBJECT VALUES('/app/webUsage','not-collected',\(reference),\(reference+20000),1);
    INSERT INTO ZOBJECT VALUES('/notification/usage','not-collected',\(reference),\(reference+20000),1);
    """
    guard sqlite3_exec(handle,sql,nil,nil,nil)==SQLITE_OK else{sqlite3_close(handle);throw MacUsageCheckFailure()}
    sqlite3_close(handle)
    check("Mac usage reader is read-only, filters remote devices and ignores web/notification streams") {
        let before=try Data(contentsOf:url)
        let rows=try MacUsageReader.read(url,from:start,to:end)
        try expect(rows.count==3 && Set(rows.map(\.bundleID))==["com.example-a","com.example.b"])
        try expect(rows[0].start==t && rows[0].end==t+3600)
        try expect(try Data(contentsOf:url)==before)
        try expect(try FileManager.default.contentsOfDirectory(atPath:folder.path)==["fixture.db"])
    }
    check("Mac interval unions remove duplicate overlap without summing parallel apps into device time") {
        let rows=try MacUsageReader.read(url,from:start,to:end)
        let days=try MacUsageSummary.days(rows,from:start,to:end,zone:zone)
        try expect(days.count==1 && days[0].screenSeconds==7200 && !days[0].complete)
        try expect(days[0].apps.first{$0.packageName=="com.example-a"}?.seconds==5400)
        try expect(days[0].apps.first{$0.packageName=="com.example.b"}?.seconds==3600)
        try expect(days[0].hours.reduce(0){$0+$1.seconds}==7200)
    }
    check("Mac usage query clips sessions to the requested time bounds; missing days stay unknown") {
        let rows=try MacUsageReader.read(url,from:start.addingTimeInterval(1800),to:start.addingTimeInterval(4000))
        try expect(rows.allSatisfy{$0.start>=t+1800 && $0.end<=t+4000})
        let days=try MacUsageSummary.days([],from:start,to:end,zone:zone)
        try expect(days[0].screenSeconds==nil && days[0].apps.isEmpty && days[0].hours.isEmpty && !days[0].complete)
    }
    check("Mac day/hour splitting handles midnight and both 23/25-hour DST days") {
        let z=TimeZone(identifier:"Europe/Berlin")!
        var cal=Calendar(identifier:.gregorian);cal.timeZone=z
        for date in [(2026,3,29),(2026,10,25)] {
            let a=cal.date(from:DateComponents(year:date.0,month:date.1,day:date.2))!,b=cal.date(byAdding:.day,value:1,to:a)!
            let rows=[MacUsageInterval(bundleID:"com.example",start:a.timeIntervalSince1970,end:b.timeIntervalSince1970)]
            let d=try MacUsageSummary.days(rows,from:a,to:b,zone:z)[0]
            try expect(d.screenSeconds==b.timeIntervalSince(a) && d.hours.count==Int(b.timeIntervalSince(a)/3600))
        }
        let rows=[MacUsageInterval(bundleID:"com.example",start:end.timeIntervalSince1970-600,end:end.timeIntervalSince1970+600)]
        let days=try MacUsageSummary.days(rows,from:start,to:end.addingTimeInterval(1200),zone:zone)
        try expect(days.count==2 && days[0].screenSeconds==600 && days[1].screenSeconds==600)
    }
    check("Mac reader never creates a missing database and rejects unsupported schemas without modifying them") {
        let missing=folder.appendingPathComponent("missing.db")
        try rejects{_=try MacUsageReader.read(missing,from:start,to:end)}
        try expect(!FileManager.default.fileExists(atPath:missing.path))
        let broken=folder.appendingPathComponent("broken.db")
        try Data("not a database".utf8).write(to:broken)
        let old=try Data(contentsOf:broken)
        try rejects{_=try MacUsageReader.read(broken,from:start,to:end)}
        try expect(try Data(contentsOf:broken)==old)
    }
    check("Mac and phone histories stay separate; old phone archives still decode and sources cannot overwrite one another") {
        let phone=UUID().uuidString,mac=UUID().uuidString
        var archive=try ScreenTimeArchive().merging(screenTimeFixture(now:now),phoneID:phone,phoneName:"Phone",now:now)
        let oldPhone=archive.devices[0]
        let rows=try MacUsageReader.read(url,from:start,to:end)
        let days=try MacUsageSummary.days(rows,from:start,to:end,zone:zone)
        archive=try archive.mergingMac(days,deviceID:mac,name:"Mac",zone:zone,now:now)
        try expect(archive.devices.count==2 && archive.devices.first{$0.id==phone}==oldPhone && archive.devices.first{$0.id==mac}?.source=="macKnowledge")
        try rejects{_=try archive.mergingMac(days,deviceID:phone,name:"Mac",zone:zone,now:now)}
        try rejects{_=try archive.merging(screenTimeFixture(now:now),phoneID:mac,phoneName:"Phone",now:now)}
        let roundTrip=try JSONDecoder().decode(ScreenTimeArchive.self,from:JSONEncoder().encode(archive))
        try expect(roundTrip==archive && roundTrip.devices.first{$0.id==phone}?.source==nil)
    }
    check("Mac refreshes are idempotent and retained-history gaps do not erase an earlier useful day") {
        let id=UUID().uuidString,rows=try MacUsageReader.read(url,from:start,to:end)
        let days=try MacUsageSummary.days(rows,from:start,to:end,zone:zone)
        let a=try ScreenTimeArchive().mergingMac(days,deviceID:id,name:"Mac",zone:zone,now:now)
        try expect(try a.mergingMac(days,deviceID:id,name:"Mac",zone:zone,now:now)==a)
        let empty=try MacUsageSummary.days([],from:start,to:end,zone:zone)
        let b=try a.mergingMac(empty,deviceID:id,name:"Mac",zone:zone,now:now)
        try expect(b==a)
    }
    return(count,failures)
}
