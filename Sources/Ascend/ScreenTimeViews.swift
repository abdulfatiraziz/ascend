import SwiftUI
import AppKit
import Charts
import AscendCore
import UniformTypeIdentifiers

@MainActor final class ScreenTimeStore: ObservableObject {
    @Published private(set) var archive=ScreenTimeArchive()
    @Published private(set) var error: String?
    let url: URL
    init(folder:URL) {
        url=folder.appendingPathComponent("screen-time.json")
        do { archive=try ScreenTimeStorage.read(url) }
        catch { self.error="Screen-time history could not be read. The existing file is preserved." }
    }
    func receive(_ snapshot:ScreenTimeSnapshot,phoneID:String,phoneName:String) throws {
        let current=try ScreenTimeStorage.read(url)
        let candidate=try current.merging(snapshot,phoneID:phoneID,phoneName:phoneName)
        if candidate != current { try ScreenTimeStorage.save(candidate,to:url) }
        archive=candidate;error=nil
    }
    func receiveMac(_ days:[ScreenTimeDay],deviceID:String,name:String,zone:TimeZone,now:Date) throws {
        let current=try ScreenTimeStorage.read(url)
        let candidate=try current.mergingMac(days,deviceID:deviceID,name:name,zone:zone,now:now)
        if candidate != current { try ScreenTimeStorage.save(candidate,to:url) }
        archive=candidate;error=nil
    }
    func export() {
        let panel=NSSavePanel();panel.nameFieldStringValue="Cipher-screen-time.json";panel.allowedContentTypes=[.json]
        guard panel.runModal() == .OK,let destination=panel.url else { return }
        do {
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(archive).write(to:destination,options:.atomic)
        } catch { self.error="The screen-time backup could not be exported." }
    }
}
struct ScreenTimeView: View {
    @ObservedObject var store:ScreenTimeStore
    @ObservedObject var mac:MacScreenTimeService
    @State private var deviceID:String?
    @State private var selected:Double?
    private var device:ScreenTimeDevice? { store.archive.devices.first { $0.id==deviceID } ?? store.archive.devices.max { $0.lastSync<$1.lastSync } }
    private var isMac:Bool { device?.source=="macKnowledge" }
    private var day:ScreenTimeDay? { device?.days.first { $0.start==selected } ?? device?.days.last }
    private var zone:TimeZone { TimeZone(identifier:day?.timeZoneID ?? device?.timeZoneID ?? "") ?? .current }
    private var phoneCalendar:Calendar { var c=Calendar(identifier:.gregorian);c.timeZone=zone;return c }
    private func formatted(_ t:Double,time:Bool=false) -> String {
        var f:Date.FormatStyle=time ? .dateTime.hour().minute() : .dateTime.day().month(.abbreviated).year()
        f.timeZone=zone;return Date(timeIntervalSince1970:t).formatted(f)
    }
    private func duration(_ seconds:Double?) -> String {
        guard let seconds else { return "—" }
        let minutes=Int(seconds/60),hours=minutes/60
        return hours>0 ? "\(hours)h \(minutes%60)m" : minutes>0 ? "\(minutes)m" : "\(Int(seconds))s"
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                HStack {
                    VStack(alignment:.leading,spacing:6) {
                        Kicker("DEVICE USAGE")
                        Text("Screen time").font(.bt(size:28,weight:.semibold))
                        Text("Phone screen-on time and this Mac’s recorded app usage, kept as separate sources.").font(.bt(size:12)).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    if !store.archive.devices.isEmpty { Button("Export screen-time backup…") { store.export() } }
                }
                MacScreenTimePanel(service:mac)
                if let device {
                    HStack {
                        Picker("Device",selection:Binding(get:{ device.id },set:{ deviceID=$0;selected=nil })) {
                            ForEach(store.archive.devices) { Text($0.name).tag($0.id) }
                        }.fixedSize()
                        Spacer()
                        Text("Last updated \(Date(timeIntervalSince1970:device.lastSync).formatted(date:.abbreviated,time:.shortened))").font(.bt(size:11)).foregroundStyle(Ink.muted)
                    }
                    if device.status != "allowed" { Text(status(device.status)).font(.bt(size:12)).foregroundStyle(.orange).panel(padding:14) }
                    if let day {
                        HStack(alignment:.top,spacing:18) {
                            VStack(alignment:.leading,spacing:10) {
                                Kicker(isMac ? "RECORDED APP-USE TIME · MAC" : day.complete ? "SCREEN-ON TIME" : "OBSERVED SCREEN-ON TIME · PARTIAL")
                                Text(duration(day.screenSeconds)).font(.bt(size:46,weight:.semibold,design:.rounded)).monospacedDigit()
                                Text(formatted(day.start)).font(.bt(size:14))
                                Text("\(isMac ? "Queried" : "Observed") through \(formatted(day.end,time:true)) · \(zone.identifier)").font(.bt(size:11)).foregroundStyle(Ink.muted)
                            }.frame(maxWidth:.infinity,alignment:.leading).panel()
                            VStack(alignment:.leading,spacing:10) {
                                Kicker("COVERAGE")
                                Text(isMac ? "Recorded intervals" : day.complete ? "Available" : "Incomplete history").font(.bt(size:20,weight:.medium))
                                Text(isMac ? "Imported from this Mac’s local activity database. Only retained app-use intervals are counted; missing time stays unknown." : day.complete ? "Usage events covered the observed interval. Today’s total grows as you use your phone." : "Android no longer has all the events for this day. The observed subtotal may be lower than your actual usage.")
                                    .font(.bt(size:12)).foregroundStyle(Ink.muted).fixedSize(horizontal:false,vertical:true)
                                Text("\(day.apps.count) apps observed").font(.bt(size:11)).foregroundStyle(Ink.accent)
                            }.frame(maxWidth:.infinity,alignment:.leading).panel()
                        }
                        history(device)
                        HStack {
                            Text("Selected day").font(.bt(size:12)).foregroundStyle(Ink.muted)
                            Picker("Screen-time day",selection:Binding(get:{ day.start },set:{ selected=$0 })) {
                                ForEach(device.days.reversed()) { Text(formatted($0.start)).tag($0.start) }
                            }.labelsHidden().fixedSize()
                        }
                        if !day.hours.isEmpty {
                            VStack(alignment:.leading,spacing:12) {
                                Text("Across the day").font(.bt(size:16,weight:.medium))
                                Chart(day.hours) { hour in
                                    BarMark(x:.value("Hour",Date(timeIntervalSince1970:hour.start),unit:.hour),y:.value("Minutes",hour.seconds/60)).foregroundStyle(Ink.accent)
                                }.chartXScale(domain:Date(timeIntervalSince1970:day.start)...Date(timeIntervalSince1970:day.end)).chartYScale(domain:0...60).chartYAxisLabel("min / hour").frame(height:130)
                            }.panel()
                        }
                        VStack(alignment:.leading,spacing:14) {
                            Text(isMac ? "Recorded app usage" : "App foreground time").font(.bt(size:17,weight:.medium))
                            Text(isMac ? "App intervals are deduplicated. Overlapping intervals count once in the Mac total; device totals are never added together." : "Observed while the screen was on. App times may overlap in split-screen; they are not added to calculate device screen time.")
                                .font(.bt(size:11)).foregroundStyle(Ink.muted)
                            if day.apps.isEmpty { Text("No app sessions are available for this day.").font(.bt(size:13)).foregroundStyle(Ink.muted) }
                            ForEach(day.apps.sorted { $0.seconds>$1.seconds }) { app in
                                HStack(spacing:14) {
                                    Image(systemName:"app.fill").foregroundStyle(Ink.accent).frame(width:30,height:30).background(Ink.accent.opacity(0.1),in:RoundedRectangle(cornerRadius:8))
                                    VStack(alignment:.leading,spacing:4) {
                                        Text(app.label).font(.bt(size:13,weight:.medium))
                                        GeometryReader { g in
                                            Capsule().fill(Ink.accent.opacity(0.12)).overlay(alignment:.leading) {
                                                Capsule().fill(Ink.accent.opacity(0.75)).frame(width:g.size.width*min(1,app.seconds/(day.apps.map(\.seconds).max() ?? 1)))
                                            }
                                        }.frame(height:3)
                                    }
                                    Spacer(minLength:12)
                                    Text(duration(app.seconds)).font(.bt(size:13,design:.monospaced)).monospacedDigit().frame(width:85,alignment:.trailing)
                                }.padding(.vertical,5)
                            }
                        }.panel()
                        Text(isMac ? "Mac totals are a union of recorded app-use intervals, not display-on time or a guaranteed match to Apple’s Screen Time report. Historical retention and delayed writes can leave gaps. Missing days remain unknown. History is local, left out of the main tracker backup, and read by Q only with full data access on." : "Screen-on time includes the lock screen. Event retention, restarts and multi-window activity can cause differences from Digital Wellbeing. No screenshots or app content are collected. A rolling 90-day history is kept on this Mac when syncing, left out of the main tracker backup, and read by Q only with full data access on.")
                            .font(.bt(size:11)).foregroundStyle(Ink.muted).fixedSize(horizontal:false,vertical:true)
                    } else { setup }
                } else { setup }
                if let error=store.error { Text(error).font(.bt(size:12)).foregroundStyle(.orange) }
            }.padding(.bottom,12)
        }.environment(\.timeZone,zone).environment(\.calendar,phoneCalendar)
    }
    private func status(_ status:String)->String {
        switch status { case "disabled":"Screen-time sharing is paused on the phone. Earlier history is retained.";case "denied":"Usage access is not allowed. Enable it for Cipher Bridge in Android Settings, then sync.";default:"The phone could not read usage events. Unlock it and sync again. Earlier history is retained." }
    }
    private var setup:some View {
        VStack(alignment:.leading,spacing:14) {
            Image(systemName:"hourglass").font(.bt(size:36)).foregroundStyle(Ink.accent)
            Text("Bring your phone usage into view.").font(.bt(size:22,weight:.medium))
            Text("1. Update Cipher Bridge on your phone.\n2. Open Bridge → Settings → Share screen time with Mac.\n3. Allow Usage access in Android Settings, return to Bridge and tap Sync now.\n4. Optionally enable Screen time in background for hourly Wi-Fi sync.")
                .font(.bt(size:13)).lineSpacing(6).foregroundStyle(Ink.muted)
            Text("Only usage summaries are shared with your paired Mac. This is separate from Health Connect permissions.").font(.bt(size:11)).foregroundStyle(Ink.muted)
        }.frame(maxWidth:.infinity,alignment:.leading).panel(padding:26)
    }
    private func history(_ device:ScreenTimeDevice)->some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text("Recent days").font(.bt(size:16,weight:.medium));Spacer();Text(isMac ? "Recorded intervals only" : "Orange = incomplete").font(.bt(size:10)).foregroundStyle(Ink.muted) }
            Chart(Array(device.days.suffix(7))) { d in
                if let seconds=d.screenSeconds {
                    BarMark(x:.value("Date",Date(timeIntervalSince1970:d.start),unit:.day),y:.value("Hours",seconds/3600))
                        .foregroundStyle(isMac || d.complete ? Ink.accent : .orange).cornerRadius(4)
                }
            }.frame(height:150).chartYAxisLabel("hours")
        }.panel()
    }
}
