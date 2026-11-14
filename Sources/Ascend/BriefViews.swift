import SwiftUI
import AscendCore

/// The Brief: the home screen's left side. A lit header with the countdown to the cycle's end,
/// four missions as watch dials, and today's ledger. Every number comes from the same stores the other tabs use.
struct BriefPanel: View {
    @ObservedObject var store: TrackerStore
    @ObservedObject var lifestyle: LifestyleStore
    let day: String
    let score: Score
    private var engine: TrackerEngine { store.engine }
    private var facts: BriefFacts { BriefFacts(store: store, day: day) }
    /// The memo shows on the Brief on Sunday (from 10 am) and Monday; it lives in the Dossier all week.
    private var memoDay: Bool { let w = engine.calendar.component(.weekday, from: Date()); return w == 1 || w == 2 }

    var body: some View {
        let f = facts
        let weeks = WeekFacts(store: store)
        let status = weeks.status
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if status.level.rawValue > lifestyle.lifestyle.seenLevel {
                    LevelUpCard(level: status.level, reward: lifestyle.lifestyle.rewards[status.level.mark] ?? "Set one in the Dossier.") {
                        lifestyle.update { $0.seenLevel = status.level.rawValue }
                    }
                }
                hero(f, status: status)
                if memoDay, day == store.today, let m = weeks.debriefMonday { DebriefCard(store: store, monday: m, memo: Debrief.compose(weeks.debriefWeek(m))) }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(f.missions) { MissionDial(mission: $0) }
                }
                ledger(f)
            }
        }.scrollIndicators(.never)
        .onAppear { if status.level.rawValue < lifestyle.lifestyle.seenLevel { lifestyle.update { $0.seenLevel = status.level.rawValue } } }
    }

    // MARK: Hero

    private func hero(_ f: BriefFacts, status: ClearanceStatus) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(f.greeting.uppercased()), ABDUL · BRIEF · \(status.level.title.uppercased())").font(.bt(size: 10, design: .monospaced)).tracking(1.6).foregroundStyle(Ink.accent)
                Text(f.headline).font(.bt(size: 26)).foregroundStyle(Ink.ivory).fixedSize(horizontal: false, vertical: true)
                Text(f.coaching).font(.bt(size: 12)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(score.percentLabel).font(.bt(size: 26)).foregroundStyle(Ink.ivory)
                    Text("\(score.completed) of \(score.scheduled) check-ins · \(Int(store.document.cycle.target * 100))% is the mission").font(.bt(size: 11)).foregroundStyle(Ink.muted)
                }
                ProgressTrack(ratio: score.ratio ?? 0, target: store.document.cycle.target)
            }
            CountdownDial(daysLeft: f.daysLeft, totalDays: f.totalDays).frame(width: 150, height: 150)
        }
        .padding(22)
        .background(LitFelt().clipShape(RoundedRectangle(cornerRadius: 14)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.accent.opacity(0.28)))
    }

    // MARK: Ledger

    private func ledger(_ f: BriefFacts) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Kicker("Today’s ledger"); Spacer(); Kicker(dateText(day, engine: engine, pattern: "EEEE, d MMM")) }
            ForEach(f.ledger, id: \.label) { row in
                HStack(spacing: 10) {
                    Text(row.label).font(.bt(size: 12)).foregroundStyle(Ink.muted).frame(width: 92, alignment: .leading)
                    if let ratio = row.ratio {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Ink.ivory.opacity(0.08))
                                Capsule().fill(row.over ? Ink.offTrack : Ink.accent).frame(width: g.size.width * min(1, ratio))
                            }
                        }.frame(height: 4)
                    } else { Spacer() }
                    Text(row.value).font(.bt(size: 11, design: .monospaced)).foregroundStyle(Ink.ivory).frame(minWidth: 110, alignment: .trailing)
                }
            }
        }.panel()
    }
}

// MARK: - Pieces

/// Felt with one lamp above it: the screen's single lit moment.
struct LitFelt: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x13493A), Ink.background, Color(hex: 0x061A14)], center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Ink.lamp.opacity(0.16), .clear], center: UnitPoint(x: 0.3, y: 0), startRadius: 0, endRadius: 360)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
        }
    }
}

/// A watch bezel: 60 minute ticks, a gold arc for progress.
struct Bezel: View {
    let progress: Double
    var lineWidth: CGFloat = 5
    var color: Color = Ink.accent
    var body: some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) / 2
            ZStack {
                ForEach(0..<60, id: \.self) { i in
                    Rectangle().fill(Ink.ivory.opacity(i % 5 == 0 ? 0.45 : 0.16))
                        .frame(width: i % 5 == 0 ? 1.5 : 1, height: i % 5 == 0 ? 7 : 4)
                        .offset(y: -(r - lineWidth - 7))
                        .rotationEffect(.degrees(Double(i) * 6))
                }
                Circle().stroke(Ink.ivory.opacity(0.08), lineWidth: lineWidth).padding(lineWidth / 2)
                Circle().trim(from: 0, to: max(0.001, min(1, progress)))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(lineWidth / 2)
            }.frame(width: g.size.width, height: g.size.height)
        }
    }
}

struct CountdownDial: View {
    let daysLeft: Int
    let totalDays: Int
    var body: some View {
        ZStack {
            Bezel(progress: totalDays > 0 ? 1 - Double(daysLeft) / Double(totalDays) : 0, lineWidth: 4, color: Ink.lamp)
            VStack(spacing: 2) {
                Text("\(max(0, daysLeft))").font(.bt(size: 40)).foregroundStyle(Ink.ivory)
                Text("DAYS TO THE\nREVEAL").font(.bt(size: 8.5, design: .monospaced)).tracking(1.4).multilineTextAlignment(.center).foregroundStyle(Ink.muted)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(daysLeft) days to the end of the cycle")
    }
}

struct MissionDial: View {
    let mission: Mission
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Bezel(progress: mission.progress, lineWidth: 4, color: mission.status.color)
                VStack(spacing: 1) {
                    Text(mission.value).font(.bt(size: 19)).foregroundStyle(Ink.ivory).minimumScaleFactor(0.6).lineLimit(1)
                    Text(mission.unit).font(.bt(size: 7.5, design: .monospaced)).tracking(1).foregroundStyle(Ink.muted).lineLimit(1)
                }.padding(.horizontal, 14)
            }.frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 5) {
                Text("MISSION \(mission.number) · \(mission.area.uppercased())").font(.bt(size: 9, design: .monospaced)).tracking(1.3).foregroundStyle(Ink.goldDim)
                Text(mission.codename).font(.bt(size: 19)).foregroundStyle(Ink.ivory)
                Text(mission.detail).font(.bt(size: 11)).foregroundStyle(Ink.muted).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                Text(mission.statusText.uppercased()).font(.bt(size: 9, design: .monospaced)).tracking(1.1)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(mission.status.color.opacity(0.14), in: Capsule())
                    .foregroundStyle(mission.status.color)
            }
            Spacer(minLength: 0)
        }.panel()
    }
}

// MARK: - Facts (pure reads)

enum MissionStatus { case onTrack, watch, offTrack, none
    var color: Color { switch self { case .onTrack: Ink.onTrack; case .watch: Ink.watch; case .offTrack: Ink.offTrack; case .none: Ink.muted } }
}
struct Mission: Identifiable {
    var id: String { number }
    let number: String, area: String, codename: String
    let value: String, unit: String, progress: Double
    let detail: String, statusText: String, status: MissionStatus
}
struct LedgerRow { let label: String; let value: String; let ratio: Double?; var over = false }

@MainActor
struct BriefFacts {
    let store: TrackerStore
    let day: String
    private var engine: TrackerEngine { store.engine }
    private var cal: Calendar { engine.calendar }
    private var date: Date { engine.date(day) ?? Date() }

    var daysLeft: Int { max(0, engine.days(from: day, through: store.document.cycle.end).count - 1) }
    var totalDays: Int { engine.days(from: store.document.cycle.start, through: store.document.cycle.end).count }
    var greeting: String {
        let h = cal.component(.hour, from: Date())
        return h < 5 ? "Good evening" : h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
    }
    var headline: String { daysLeft > 0 ? "Sharp by the \(ordinal(cal.component(.day, from: engine.date(store.document.cycle.end) ?? Date()))). \(weakest.map { "Today is about \(Self.focus[$0.area] ?? $0.area.lowercased())." } ?? "Hold the line.")" : "Reveal day." }
    var coaching: String {
        let m = missions
        let good = m.filter { $0.status == .onTrack }.map { $0.codename }
        var parts: [String] = []
        if !good.isEmpty { parts.append("\(good.joined(separator: " and ")) on pace.") }
        if let w = weakest { parts.append("Weak point: \(w.codename), \(w.detail.prefix(1).lowercased() + w.detail.dropFirst())") }
        return parts.isEmpty ? "Log today’s check-ins and the dials fill in." : parts.joined(separator: " ")
    }
    private var weakest: Mission? { missions.first { $0.status == .offTrack } ?? missions.first { $0.status == .watch } }

    static let focus = ["Body": "the scale", "Sleep": "the night", "Training": "the gym", "Composure": "the evening"]
    var missions: [Mission] { [body, sleep, training, composure] }

    // 01 · Body: weight toward 72 kg.
    private var body: Mission {
        let records = store.bodyMeasurements.archive.records.sorted { $0.date < $1.date }
        let goalKg = 72.0
        guard let last = records.last else {
            return Mission(number: "01", area: "Body", codename: "Op. Reveal", value: "—", unit: "KG → 72", progress: 0, detail: "No weigh-in yet. Step on the scale.", statusText: "No data", status: .none)
        }
        let startDate = engine.date(store.document.cycle.start) ?? last.date
        let start = records.last { $0.date <= startDate } ?? records.first { $0.date >= startDate } ?? last
        let lost = start.kilograms - last.kilograms
        let progress = start.kilograms > goalKg ? lost / (start.kilograms - goalKg) : 1
        let fortnight = records.last { $0.date <= last.date.addingTimeInterval(-14 * 86400) }
        let perWeek = fortnight.map { ($0.kilograms - last.kilograms) / max(1, last.date.timeIntervalSince($0.date) / (7 * 86400)) }
        let weeksLeft = Double(max(1, daysLeft)) / 7
        let needed = max(0, last.kilograms - goalKg) / weeksLeft
        let status: MissionStatus = perWeek.map { $0 >= needed * 0.9 ? .onTrack : $0 >= needed * 0.5 ? .watch : .offTrack } ?? .none
        let detail = "72 kg by \(dateText(store.document.cycle.end, engine: engine, pattern: "d MMM")). " + (lost >= 0.05 ? "Down \(String(format: "%.1f", lost)) kg this cycle." : "Needs \(String(format: "%.2f", needed)) kg a week.")
        let statusText = perWeek.map { (status == .onTrack ? "On pace" : "Behind") + " · −" + String(format: "%.2f", max(0, $0)) + "/wk" } ?? "Need 2 weeks of weigh-ins"
        return Mission(number: "01", area: "Body", codename: "Op. Reveal", value: String(format: "%.1f", last.kilograms), unit: "KG → 72", progress: progress, detail: detail, statusText: statusText, status: status)
    }

    // 02 · Sleep: nights asleep by 1 am, last 7.
    private var sleep: Mission {
        var onTime = 0, known = 0, onsets: [Int] = []
        for offset in 0..<7 {
            let d = engine.adding(-offset, to: day)
            guard let s = store.document.health.sleepSessions(on: d, engine: engine).first else { continue }
            known += 1
            let start = Date(timeIntervalSince1970: s.start)
            var minute = cal.component(.hour, from: start) * 60 + cal.component(.minute, from: start)
            if minute < 12 * 60 { minute += 1440 }   // after midnight counts as late evening
            onsets.append(minute)
            if minute <= 25 * 60 { onTime += 1 }
        }
        guard known > 0 else {
            return Mission(number: "02", area: "Sleep", codename: "Midnight", value: "—", unit: "NIGHTS", progress: 0, detail: "No sleep synced this week. Open Ascend Bridge.", statusText: "No data", status: .none)
        }
        let avg = onsets.reduce(0, +) / onsets.count
        let status: MissionStatus = onTime >= 5 ? .onTrack : onTime >= 3 ? .watch : .offTrack
        return Mission(number: "02", area: "Sleep", codename: "Midnight", value: "\(onTime)/\(known)", unit: "BY 1 AM", progress: Double(onTime) / 7,
                       detail: "Asleep by 1:00 am on \(onTime) of the last \(known) nights.", statusText: "\(status == .onTrack ? "On pace" : "Behind") · avg \(HealthReport.clock(avg))", status: status)
    }

    // 03 · Training: gym sessions this week + steps today.
    private var training: Mission {
        let gym = store.document.habits.first { $0.latest.title.localizedCaseInsensitiveContains("gym") }
        let weekday = (cal.component(.weekday, from: date) + 5) % 7      // Monday = 0
        let monday = engine.adding(-weekday, to: day)
        let week = engine.days(from: monday, through: day)
        let done = gym.map { g in week.filter { engine.completed(g, on: $0) }.count } ?? 0
        let steps = store.document.health.steps(on: day, engine: engine)
        let stepsText = steps.map { "Steps today \(Int($0).formatted())." } ?? "No steps synced today."
        let left = max(0, 3 - done)
        let status: MissionStatus = done >= 3 ? .onTrack : (weekday >= 5 && left > 0) ? .offTrack : .watch
        return Mission(number: "03", area: "Training", codename: "Iron", value: "\(done)/3", unit: "SESSIONS", progress: Double(done) / 3,
                       detail: "Gym Mon · Wed · Sat. \(stepsText)", statusText: left == 0 ? "Week done" : "\(left) session\(left == 1 ? "" : "s") left", status: status)
    }

    // 04 · Composure: evening stress (6 pm–midnight), target under 28.
    private var composure: Mission {
        func evening(_ d: String) -> Double? {
            let readings = store.document.health.records(.stress, on: d, engine: engine).filter { cal.component(.hour, from: Date(timeIntervalSince1970: $0.start)) >= 18 }
            return readings.isEmpty ? nil : readings.map(\.value).reduce(0, +) / Double(readings.count)
        }
        let (value, which) = evening(day).map { ($0, "this evening") } ?? evening(engine.adding(-1, to: day)).map { ($0, "last evening") } ?? (nil, "")
        guard let value else {
            return Mission(number: "04", area: "Composure", codename: "Still Water", value: "—", unit: "EVE STRESS", progress: 0, detail: "Evening stress under 28. No watch stress yet.", statusText: "No data", status: .none)
        }
        let status: MissionStatus = value < 28 ? .onTrack : value < 34 ? .watch : .offTrack
        return Mission(number: "04", area: "Composure", codename: "Still Water", value: "\(Int(value.rounded()))", unit: "EVE STRESS", progress: min(1, 28 / max(1, value)),
                       detail: "Evening stress under 28; \(Int(value.rounded())) \(which). Two sighs at 11 pm help most.", statusText: status == .onTrack ? "On pace · target 28" : "Close · target 28", status: status)
    }

    var ledger: [LedgerRow] {
        var rows: [LedgerRow] = []
        let totals = store.document.meals.totals(day)
        let habits = store.document.mealHabits
        let kcalMax = habits.calories.flatMap { engine.target(for: $0, on: day)?.maximum }
        let proteinMin = habits.protein.flatMap { engine.target(for: $0, on: day)?.minimum }
        rows.append(LedgerRow(label: "Calories", value: "\(Int(totals.kcal).formatted())" + (kcalMax.map { " / \(Int($0).formatted())" } ?? "") + " kcal",
                              ratio: kcalMax.map { totals.kcal / $0 }, over: kcalMax.map { totals.kcal > $0 } ?? false))
        rows.append(LedgerRow(label: "Protein", value: "\(Int(totals.protein))" + (proteinMin.map { " / \(Int($0))" } ?? "") + " g", ratio: proteinMin.map { totals.protein / $0 }))
        let steps = store.document.health.steps(on: day, engine: engine)
        rows.append(LedgerRow(label: "Steps", value: steps.map { "\(Int($0).formatted()) / 10,000" } ?? "—", ratio: steps.map { $0 / 10_000 }))
        let meds = store.document.meds.slots(on: day, engine: engine)
        if !meds.isEmpty {
            let taken = meds.filter { $0.taken != nil }.count
            rows.append(LedgerRow(label: "Meds", value: "\(taken) / \(meds.count) taken", ratio: Double(taken) / Double(meds.count)))
        }
        if let screen = screenSeconds { rows.append(LedgerRow(label: "Screen time", value: hm(screen), ratio: nil)) }
        return rows
    }
    private var screenSeconds: Double? {
        let start = cal.startOfDay(for: date).timeIntervalSince1970
        let values = store.screenTime.archive.devices.compactMap { device in device.days.first { abs($0.start - start) < 3600 }?.screenSeconds }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    private func hm(_ s: Double) -> String { let m = Int(s / 60); return m >= 60 ? "\(m / 60) h \(m % 60) m" : "\(m) m" }
    private func ordinal(_ n: Int) -> String { let s = (11...13).contains(n % 100) ? "th" : [1: "st", 2: "nd", 3: "rd"][n % 10] ?? "th"; return "\(n)\(s)" }
}
