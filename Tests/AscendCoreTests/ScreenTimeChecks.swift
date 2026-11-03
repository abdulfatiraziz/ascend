import Foundation
import AscendCore

private struct ScreenCheckFailure:Error {}
func screenTimeFixture(now:Date=Date(),status:String="allowed",partial:Bool=false) throws -> ScreenTimeSnapshot {
    var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:"Asia/Kolkata")!
    let today=c.startOfDay(for:now)
    let days:[[String:Any]]=status=="allowed" ? (0..<7).map { index in
        let start=c.date(byAdding:.day,value:index-6,to:today)!.timeIntervalSince1970
        let end=min(c.date(byAdding:.day,value:1,to:Date(timeIntervalSince1970:start))!.timeIntervalSince1970,now.timeIntervalSince1970)
        let seconds=min(60,max(0,end-start))
        return ["start":start,"end":end,"screenSeconds":seconds,"complete":!partial,
                "hours":seconds>0 ? [["start":start,"seconds":seconds]]:[],
                "apps":seconds>0 ? [["packageName":"com.example.app","label":"Example","seconds":seconds]]:[]]
    }:[]
    let data=try JSONSerialization.data(withJSONObject:["version":1,"generatedAt":now.timeIntervalSince1970,"timeZoneID":"Asia/Kolkata","status":status,"days":days])
    return try JSONDecoder().decode(ScreenTimeSnapshot.self,from:data)
}
func runScreenTimeChecks() -> (count:Int,failures:Int) {
    var count=0,failures=0
    func expect(_ value:Bool)throws { if !value { throw ScreenCheckFailure() } }
    func rejects(_ body:()throws->Void)throws { do { try body() }catch{return};throw ScreenCheckFailure() }
    func check(_ name:String,_ body:()throws->Void) {
        count+=1;do{try body();print("PASS: \(name)")}catch{failures+=1;print("FAIL: \(name): \(error)")}
    }
    let now=Date(),phone=UUID().uuidString
    check("screen-time days are scoped to phone-local dates with validated hourly and app totals") {
        let s=try screenTimeFixture(now:now);try s.validate(now:now)
        let a=try ScreenTimeArchive().merging(s,phoneID:phone,phoneName:"Test phone",now:now)
        try expect(a.devices.count==1 && a.devices[0].days.count==7)
        try expect(a.devices[0].days.allSatisfy{$0.timeZoneID=="Asia/Kolkata"})
    }
    check("screen-time refresh deduplicates days and retains complete history when new event coverage is partial") {
        let s=try screenTimeFixture(now:now)
        let a=try ScreenTimeArchive().merging(s,phoneID:phone,phoneName:"Phone",now:now)
        try expect(try a.merging(s,phoneID:phone,phoneName:"Phone",now:now)==a)
        let partial=try screenTimeFixture(now:now.addingTimeInterval(1),partial:true)
        let b=try a.merging(partial,phoneID:phone,phoneName:"Phone",now:now.addingTimeInterval(1))
        try expect(b.devices[0].days==a.devices[0].days)
    }
    check("disabled, denied and unavailable screen-time reads keep earlier records; devices stay separate") {
        var a=try ScreenTimeArchive().merging(screenTimeFixture(now:now),phoneID:phone,phoneName:"Phone",now:now)
        let old=a.devices[0].days
        for status in ["disabled","denied","unavailable"] {
            a=try a.merging(screenTimeFixture(now:now,status:status),phoneID:phone,phoneName:"Phone",now:now)
            try expect(a.devices[0].days==old && a.devices[0].status==status)
        }
        a=try a.merging(screenTimeFixture(now:now),phoneID:UUID().uuidString,phoneName:"Second",now:now)
        try expect(a.devices.count==2)
    }
    check("screen-time rejects stale, future, malformed dates, duplicate apps, impossible hours and unpermitted payloads") {
        var s=try screenTimeFixture(now:now);s.generatedAt-=3600
        try rejects{try s.validate(now:now)}
        s=try screenTimeFixture(now:now);s.generatedAt+=3600
        try rejects{try s.validate(now:now)}
        s=try screenTimeFixture(now:now);s.days[0].start+=60
        try rejects{try s.validate(now:now)}
        s=try screenTimeFixture(now:now);s.days[0].apps+=s.days[0].apps
        try rejects{try s.validate(now:now)}
        s=try screenTimeFixture(now:now);s.days[0].hours[0].seconds=4000
        try rejects{try s.validate(now:now)}
        s=try screenTimeFixture(now:now);s.status="denied"
        try rejects{try s.validate(now:now)}
    }
    check("screen-time saves atomically with a readable backup and leaves tracker/watch bytes unchanged") {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("ascend-screen-check-\(UUID())")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("screen-time.json"), tracker=folder.appendingPathComponent("tracker.json"),watch=folder.appendingPathComponent("health.json")
        try Data("tracker".utf8).write(to:tracker);try Data("watch".utf8).write(to:watch)
        let a=try ScreenTimeArchive().merging(screenTimeFixture(now:now),phoneID:phone,phoneName:"Phone",now:now)
        try ScreenTimeStorage.save(a,to:url)
        let b=try a.merging(screenTimeFixture(now:now,status:"disabled"),phoneID:phone,phoneName:"Phone",now:now)
        try ScreenTimeStorage.save(b,to:url)
        try expect(try ScreenTimeStorage.read(url)==b && ScreenTimeStorage.read(url.appendingPathExtension("backup"))==a)
        try expect(try Data(contentsOf:tracker)==Data("tracker".utf8) && Data(contentsOf:watch)==Data("watch".utf8))
        try Data("broken".utf8).write(to:url)
        try rejects{try ScreenTimeStorage.save(a,to:url)}
        try expect(try Data(contentsOf:url)==Data("broken".utf8))
    }
    check("screen-time is absent from tracker backups and old phone envelopes remain decodable") {
        let doc=TrackerDocument.seeded(today:"2026-11-03")
        let data=try JSONEncoder().encode(doc)
        try expect(!String(decoding:data,as:UTF8.self).contains("screenTime"))
        let envelope=LinkEnvelope(kind:"hello")
        let e=try JSONDecoder().decode(LinkEnvelope.self,from:JSONEncoder().encode(envelope))
        try expect(e.screenTime==nil)
    }
    return(count,failures)
}
