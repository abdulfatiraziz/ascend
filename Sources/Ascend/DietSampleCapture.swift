import AppKit
import SwiftUI

/// Explicit generated-fixture rendering only; never captures the user's desktop.
@MainActor enum DietSampleCapture {
    static func export(store: TrackerStore) {
        let env=ProcessInfo.processInfo.environment
        guard env["ASCEND_BODY_SAMPLE"]=="1",env["ASCEND_DATA_DIR"] != nil,let destination=env["ASCEND_DIET_SAMPLE_CAPTURE_DIR"] else{return}
        DispatchQueue.main.asyncAfter(deadline:.now()+1) {
            let view=VStack(alignment:.leading,spacing:16) {
                Text("ASCEND · MEALS").font(.bt(size:28,weight:.bold))
                Text("GENERATED SAMPLE DATA · NOT YOUR PERSONAL RECORDS").font(.bt(size:11,design:.monospaced)).foregroundStyle(.orange)
                DietDashboard(store:store,day:store.today)
            }.padding(28).frame(width:1120,height:1150,alignment:.topLeading).background(Ink.background).foregroundStyle(.white).preferredColorScheme(.dark).environment(\.calendar,store.engine.calendar).environment(\.timeZone,store.engine.calendar.timeZone)
            let root=NSHostingView(rootView:view);root.frame=NSRect(x:0,y:0,width:1120,height:1150);root.layoutSubtreeIfNeeded()
            guard let bitmap=root.bitmapImageRepForCachingDisplay(in:root.bounds) else{return}
            root.cacheDisplay(in:root.bounds,to:bitmap)
            guard let data=bitmap.representation(using:.png,properties:[:]) else{return}
            do {let folder=URL(fileURLWithPath:destination,isDirectory:true);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try data.write(to:folder.appendingPathComponent("diet-sample.png"),options:.atomic)} catch {}
        }
    }
}
