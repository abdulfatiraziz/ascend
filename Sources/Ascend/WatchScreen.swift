import SwiftUI
import AppKit
import IOKit.pwr_mgt
import AscendCore

/// The Routine dial as an always-on screen. It fills one whole display (the MacBook's own screen when a monitor is
/// attached), keeps that display from sleeping, dims in the sleep hours and drifts a few points every ten minutes.
/// Esc or the right-click menu closes it. It reopens after a restart if it was showing when Cipher quit.
@MainActor final class WatchScreen {
    static let shared = WatchScreen()
    static let openKey = "watchScreen.open", displayKey = "watchScreen.display"
    private var window: NSWindow?
    private var assertion: IOPMAssertionID = 0
    private var keyMonitor: Any?
    private var screensObserver: Any?
    private weak var store: TrackerStore?
    private var restored = false
    var isOpen: Bool { window != nil }

    func toggle(store: TrackerStore) { isOpen ? close() : open(store: store, activate: true) }

    /// Reopens the watch screen on launch when it was left showing. Once per launch; never for sample data.
    func restore(store: TrackerStore) {
        guard !restored else { return }
        restored = true
        guard ProcessInfo.processInfo.environment["ASCEND_DATA_DIR"] == nil, UserDefaults.standard.bool(forKey: Self.openKey) else { return }
        DispatchQueue.main.async { self.open(store: store, activate: false) }
    }

    func open(store: TrackerStore, on chosen: NSScreen? = nil, activate: Bool) {
        teardown()
        self.store = store
        let screen = chosen ?? Self.preferredScreen()
        let dedicated = NSScreen.screens.count > 1
        let w = WatchWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.backgroundColor = NSColor(Ink.night)
        w.hasShadow = false
        w.isMovable = false
        // On a screen of its own it covers that screen's menu bar too; as the only screen it stays a normal window you can switch away from.
        w.level = dedicated ? .statusBar : .normal
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let others = NSScreen.screens.filter { $0 != screen }
        w.contentView = NSHostingView(rootView:
            WatchScreenView(store: store, otherScreens: others.map { ($0.localizedName, Self.number($0)) },
                            close: { [weak self] in self?.close() },
                            move: { [weak self] id in
                                guard let self, let s = NSScreen.screens.first(where: { Self.number($0) == id }) else { return }
                                UserDefaults.standard.set(Int(id), forKey: Self.displayKey)
                                self.open(store: store, on: s, activate: true)
                            })
            .preferredColorScheme(.dark)
            .environment(\.calendar, store.engine.calendar)
            .environment(\.timeZone, store.engine.calendar.timeZone))
        w.setFrame(screen.frame, display: true)
        if activate { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) } else { w.orderFrontRegardless() }
        window = w
        UserDefaults.standard.set(true, forKey: Self.openKey)

        // Keep the displays awake while it shows (the Mac then doesn't start its screen saver or lock on idle).
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "Cipher watch screen is showing" as CFString, &assertion)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, event.keyCode == 53 else { return event }   // Esc
            self.close(); return nil
        }
        // A monitor unplugged or plugged in: follow the preferred screen.
        screensObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let store = self.store, self.isOpen else { return }
                self.open(store: store, activate: false)
            }
        }
    }

    /// Closed by you: stays closed after a restart.
    func close() {
        teardown()
        UserDefaults.standard.set(false, forKey: Self.openKey)
    }
    private func teardown() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let screensObserver { NotificationCenter.default.removeObserver(screensObserver) }
        keyMonitor = nil; screensObserver = nil
        if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
        window?.orderOut(nil); window = nil
    }

    static func number(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
    /// The display you last moved it to; else, with a monitor attached, the MacBook's own screen; else the main screen.
    static func preferredScreen() -> NSScreen {
        let screens = NSScreen.screens
        let saved = UserDefaults.standard.integer(forKey: displayKey)
        if saved != 0, let s = screens.first(where: { number($0) == CGDirectDisplayID(saved) }) { return s }
        if screens.count > 1, let builtIn = screens.first(where: { CGDisplayIsBuiltin(number($0)) != 0 }) { return builtIn }
        return NSScreen.main ?? screens[0]
    }
}

/// A borderless window that can still take Esc.
private final class WatchWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

struct WatchScreenView: View {
    @ObservedObject var store: TrackerStore
    let otherScreens: [(name: String, id: CGDirectDisplayID)]
    let close: () -> Void
    let move: (CGDirectDisplayID) -> Void
    @State private var drift = CGSize.zero
    private let shift = Timer.publish(every: 600, on: .main, in: .common).autoconnect()

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let facts = RoutineFacts(store: store, now: timeline.date)
            let asleep = store.document.routine.configured && store.document.routine.phase(at: facts.clockMinute) == .sleep
            GeometryReader { geo in
                let wide = geo.size.width > geo.size.height * 1.2
                let dial = wide ? min(geo.size.height * 0.84, geo.size.width * 0.5) : min(geo.size.width * 0.86, geo.size.height * 0.56)
                let layout = wide ? AnyLayout(HStackLayout(alignment: .center, spacing: geo.size.width * 0.04)) : AnyLayout(VStackLayout(spacing: 28))
                layout {
                    WatchDial(facts: facts).frame(width: dial, height: dial)
                    side(facts, scale: min(1.25, max(0.85, geo.size.height / 900))).frame(maxWidth: wide ? min(600, geo.size.width * 0.4) : dial)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .offset(drift)
                .opacity(asleep ? 0.3 : 1)
                .animation(.easeInOut(duration: 2), value: asleep)
            }
        }
        .background(RadialGradient(colors: [Color(hex: 0x12392C), Ink.background, Ink.night], center: UnitPoint(x: 0.35, y: 0.45), startRadius: 0, endRadius: 1100))
        .ignoresSafeArea()
        .onReceive(shift) { _ in withAnimation(.easeInOut(duration: 3)) { drift = CGSize(width: .random(in: -8...8), height: .random(in: -8...8)) } }
        .contextMenu {
            ForEach(otherScreens, id: \.id) { s in Button("Move to \(s.name)") { move(s.id) } }
            Button("Close watch screen (Esc)", action: close)
        }
        .onHover { inside in if inside { NSCursor.setHiddenUntilMouseMoves(true) } }
    }

    /// Today's score, the next few things on the plan and M's orders. Urges are never shown here: this screen sits in the open.
    @ViewBuilder private func side(_ facts: RoutineFacts, scale k: CGFloat) -> some View {
        let engine = store.engine, day = store.today
        let score = engine.score(on: day), rest = store.document.restDays.contains(day)
        let memo = DailyMemo.compose(DailyMemoFacts(store: store))
        VStack(alignment: .leading, spacing: 26 * k) {
            Text(dateText(day, engine: engine, pattern: "EEEE d MMMM").uppercased() + " · " + facts.momentName.uppercased())
                .font(.bt(size: 12 * k, weight: .semibold, design: .monospaced)).tracking(2.4).foregroundStyle(Ink.accent).lineLimit(1).minimumScaleFactor(0.7)

            VStack(alignment: .leading, spacing: 8 * k) {
                HStack(alignment: .firstTextBaseline, spacing: 12 * k) {
                    Text(rest ? "Rest" : "\(score.completed)/\(score.scheduled)").font(.bt(size: 64 * k, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(Ink.ivory)
                    Text(rest ? "day · check-ins kept, not scored" : "check-ins today").font(.bt(size: 15 * k)).foregroundStyle(Ink.muted)
                }
                if let r = score.ratio {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Ink.line)
                            Capsule().fill(r >= 1 ? Ink.onTrack : Ink.accent).frame(width: max(6, g.size.width * r))
                        }
                    }.frame(height: 6 * k)
                }
            }

            VStack(alignment: .leading, spacing: 6 * k) {
                Text("Tonight: lights out by \(HealthReport.clock(store.document.routine.bedMinute)).").font(.bt(size: 22 * k)).foregroundStyle(Ink.ivory)
                facts.ledeDetail.font(.bt(size: 13 * k)).foregroundStyle(Ink.muted)
            }

            let ahead = Array(facts.ahead.filter { !$0.done }.prefix(4))
            VStack(alignment: .leading, spacing: 10 * k) {
                Text("NEXT").font(.bt(size: 11 * k, weight: .semibold, design: .monospaced)).tracking(2.4).foregroundStyle(Ink.muted)
                if ahead.isEmpty { Text("Nothing left on the plan tonight.").font(.bt(size: 15 * k)).foregroundStyle(Ink.muted) }
                ForEach(ahead, id: \.id) { e in
                    let open = e.kind == .meal && facts.nowMinute >= e.minute && facts.nowMinute < (e.endMinute ?? e.minute)
                    HStack(alignment: .firstTextBaseline, spacing: 14 * k) {
                        Text(HealthReport.clock(e.minute)).font(.bt(size: 13 * k, design: .monospaced)).foregroundStyle(Ink.muted).frame(width: 82 * k, alignment: .leading)
                        Text(e.title).font(.bt(size: 18 * k, weight: e.kind == .windDown ? .semibold : .medium)).foregroundStyle(e.kind == .windDown ? Ink.lamp : Ink.ivory).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(open ? "OPEN" : RoutineFacts.span(e.minute - facts.nowMinute)).font(.bt(size: 12 * k, design: .monospaced)).foregroundStyle(open ? Ink.accent : Ink.muted)
                    }
                }
            }

            if !memo.orders.isEmpty {
                VStack(alignment: .leading, spacing: 8 * k) {
                    Text("TODAY · FROM M").font(.bt(size: 11 * k, weight: .semibold, design: .monospaced)).tracking(2.4).foregroundStyle(Ink.offTrack.opacity(0.85))
                    ForEach(Array(memo.orders.enumerated()), id: \.offset) { i, order in
                        HStack(alignment: .firstTextBaseline, spacing: 10 * k) {
                            Text("\(i + 1).").font(.bt(size: 13 * k, weight: .semibold, design: .monospaced)).foregroundStyle(Ink.accent)
                            Text(order).font(.custom(Typeface.serif, fixedSize: 21 * k).weight(.semibold)).foregroundStyle(Ink.ivory).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
