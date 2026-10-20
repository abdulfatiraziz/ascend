import Foundation

/// How often urges were let pass or acted on, for the Mac's Urges screen and the phone.
public struct UrgeTally: Equatable, Sendable {
    public struct Counts: Equatable, Sendable {
        public var passed = 0
        public var acted = 0
        public var unrecorded = 0
        public init() {}
        public var total: Int { passed + acted + unrecorded }
        mutating func add(_ outcome: UrgeOutcome) {
            switch outcome { case .passed: passed += 1; case .acted: acted += 1; case .unrecorded: unrecorded += 1 }
        }
    }
    public var today = Counts()
    /// The last seven days, including today.
    public var week = Counts()
    /// The current cycle up to today.
    public var cycle = Counts()
    /// Whole days since the last urge acted on, or since the cycle began when none were.
    public var cleanDays = 0
    public var lastActed: Date?
    /// Flat counts sent to the phone with every reply.
    public var phoneSummary: [String: Int] {
        ["todayPassed": today.passed, "todayActed": today.acted, "weekPassed": week.passed, "weekActed": week.acted,
         "cyclePassed": cycle.passed, "cycleActed": cycle.acted, "cleanDays": cleanDays]
    }
}
public extension TrackerEngine {
    func urgeTally(today: String) -> UrgeTally {
        var tally = UrgeTally()
        let weekStart = adding(-6, to: today), cycleStart = document.cycle.start
        for urge in document.urgeLogs {
            let day = key(urge.timestamp)
            guard day <= today else { continue }
            if day == today { tally.today.add(urge.outcome) }
            if day >= weekStart { tally.week.add(urge.outcome) }
            if day >= cycleStart { tally.cycle.add(urge.outcome) }
        }
        tally.lastActed = document.urgeLogs.filter { $0.outcome == .acted && key($0.timestamp) <= today }.map(\.timestamp).max()
        let from = tally.lastActed.map { key($0) } ?? cycleStart
        tally.cleanDays = max(0, days(from: from, through: today).count - 1)
        return tally
    }
}
