import SwiftUI
import AppKit
import AscendCore

@MainActor final class MacScreenTimeService:ObservableObject {
    @Published private(set) var automatic=true
    @Published private(set) var busy=false
    @Published private(set) var status:String?
    @Published private(set) var failed=false
    @Published private(set) var needsAccess=false
    let enabled:Bool
    private weak var store:ScreenTimeStore?
    private let settingsURL:URL
    private let deviceID:String
    private var timer:Timer?
    private var operation:Task<Void,Never>?
    private var worker:Task<[ScreenTimeDay],Error>?
    private var generation=0
    private var lastAttempt:Date?
    private var observers:[(NotificationCenter,NSObjectProtocol)]=[]
    private struct Settings:Codable { var id:String;var automatic:Bool }
    init(enabled:Bool,store:ScreenTimeStore) {
        self.enabled=enabled;self.store=store
        settingsURL=store.url.deletingLastPathComponent().appendingPathComponent("mac-screen-time-sync.json")
        if let data=try? Data(contentsOf:settingsURL),let saved=try? JSONDecoder().decode(Settings.self,from:data),UUID(uuidString:saved.id) != nil {
            deviceID=saved.id;automatic=saved.automatic
        } else { deviceID=UUID().uuidString }
    }
    private func saveSettings() throws {
        try FileManager.default.createDirectory(at:settingsURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(Settings(id:deviceID,automatic:automatic)).write(to:settingsURL,options:.atomic)
    }
    func start() {
        guard enabled,timer==nil else{return}
        do { try saveSettings() } catch { failed=true;status="Mac usage settings could not be saved.";return }
        timer=Timer.scheduledTimer(withTimeInterval:900,repeats:true) { [weak self] _ in Task{@MainActor in self?.refreshIfDue()} }
        for (center,name) in [(NSWorkspace.shared.notificationCenter,NSWorkspace.didWakeNotification),(NotificationCenter.default,NSApplication.didBecomeActiveNotification)] {
            let observer=center.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in Task{@MainActor in self?.refreshIfDue()} }
            observers.append((center,observer))
        }
        if automatic { refresh() }
    }
    private func refreshIfDue() {
        guard automatic,lastAttempt.map({Date().timeIntervalSince($0)>=120}) ?? true else{return}
        let last=store?.archive.devices.first{$0.id==deviceID}?.lastSync ?? 0
        if Date().timeIntervalSince1970-last>=900 { refresh() }
    }
    func setAutomatic(_ on:Bool) {
        guard enabled else{return}
        automatic=on
        if !on { generation+=1;worker?.cancel();operation?.cancel();busy=false;failed=false;needsAccess=false;status="Mac history sync paused. Earlier records are retained." }
        do { try saveSettings() } catch { failed=true;status="Mac usage settings could not be saved." }
        if on { refresh() }
    }
    func refresh() {
        guard enabled,!busy else{return}
        generation+=1;let current=generation
        busy=true;failed=false;needsAccess=false;status="Reading this Mac’s recorded app usage…";lastAttempt=Date()
        let now=Date(),zone=TimeZone.current,url=MacUsageReader.defaultURL
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=zone
        let start=calendar.date(byAdding:.day,value:-27,to:calendar.startOfDay(for:now))!
        operation=Task {
            defer { if generation==current { busy=false;worker=nil } }
            do {
                let task=Task.detached(priority:.utility) {
                    let rows=try MacUsageReader.read(url,from:start,to:now)
                    return try MacUsageSummary.days(rows,from:start,to:now,zone:zone)
                }
                worker=task
                var days=try await task.value
                try Task.checkCancellation()
                guard generation==current,let store else{return}
                var labels:[String:String]=[:]
                for i in days.indices {
                    for j in days[i].apps.indices {
                        let id=days[i].apps[j].packageName
                        if labels[id]==nil {
                            let bundle=NSWorkspace.shared.urlForApplication(withBundleIdentifier:id).flatMap{Bundle(url:$0)}
                            let name=(bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String) ?? (bundle?.infoDictionary?["CFBundleDisplayName"] as? String) ?? (bundle?.infoDictionary?["CFBundleName"] as? String) ?? id
                            labels[id]=String(name.prefix(200))
                        }
                        days[i].apps[j].label=labels[id] ?? id
                    }
                }
                try store.receiveMac(days,deviceID:deviceID,name:Host.current().localizedName ?? "This Mac",zone:zone,now:now)
                let recorded=days.filter{$0.screenSeconds != nil}.count
                status=recorded>0 ? "Updated \(recorded) days with recorded Mac app usage." : "The database is readable, but no app-use intervals were available in the last 28 days."
            } catch is CancellationError {} catch {
                if generation==current {
                    failed=true;status=error.localizedDescription
                    if let issue=error as? MacScreenTimeError { if case .access=issue { needsAccess=true } }
                }
            }
        }
    }
    func openPrivacy() {
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
    func revealApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
}
struct MacScreenTimePanel:View {
    @ObservedObject var service:MacScreenTimeService
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Label("This Mac’s history",systemImage:"desktopcomputer").font(.bt(size:15,weight:.medium))
                Spacer()
                if service.busy { ProgressView().controlSize(.small) }
                Button("Refresh Mac history") { service.refresh() }.disabled(!service.enabled || service.busy)
            }
            Toggle("Refresh Mac history every 15 minutes while Ascend is open",isOn:Binding(get:{service.automatic},set:{service.setAutomatic($0)}))
                .font(.bt(size:12)).disabled(!service.enabled)
            Text("Reads this Mac’s recorded app-use intervals locally. It doesn’t collect websites, window titles, notifications or screenshots. App-use time is shown separately from the phone’s screen-on time.")
                .font(.bt(size:11)).foregroundStyle(Ink.muted).fixedSize(horizontal:false,vertical:true)
            if let status=service.status { Text(status).font(.bt(size:12)).foregroundStyle(service.failed ? .orange:Ink.muted).fixedSize(horizontal:false,vertical:true) }
            if service.needsAccess {
                Text("For historical access, add Ascend in System Settings → Privacy & Security → Full Disk Access, then quit and reopen Ascend. Full Disk Access is a broad macOS permission; this connector reads only the local app-usage stream.")
                    .font(.bt(size:11)).foregroundStyle(Ink.muted).fixedSize(horizontal:false,vertical:true)
                HStack { Button("Open Full Disk Access settings") { service.openPrivacy() };Button("Show this Ascend app in Finder") { service.revealApp() } }
            }
        }.panel(padding:16)
    }
}
