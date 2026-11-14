import SwiftUI
import Charts
import AscendCore
import LocalAuthentication

// MARK: - Shared pieces

/// The serif line under the sub-tabs that tells you the day, with something on the right.
struct ConditionLede<Trailing: View>: View {
    var text: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(text).font(.bt(size: 22, design: .serif)).foregroundStyle(Ink.ivory).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 16)
            trailing
        }
    }
}

/// A Black Tie card: panel, hairline border, 14 pt corners.
extension View {
    func conditionCard(padding: CGFloat = 22) -> some View {
        self.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.panel, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.line))
    }
}

/// A small sub-dial: twelve ticks, an arc for the fraction and a hand.
struct DialGauge: View {
    var fraction: Double
    var color: Color
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2), r = min(size.width, size.height) / 2 - 3
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r - 3, y: c.y - r - 3, width: 2 * r + 6, height: 2 * r + 6)), with: .color(Color(hex: 0x0A231B)))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r - 3, y: c.y - r - 3, width: 2 * r + 6, height: 2 * r + 6)), with: .color(Ink.accent.opacity(0.45)), lineWidth: 1)
            for i in 0..<12 {
                let a = Double(i) / 12 * 2 * .pi
                var p = Path(); p.move(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)); p.addLine(to: CGPoint(x: c.x + cos(a) * (r - 3), y: c.y + sin(a) * (r - 3)))
                ctx.stroke(p, with: .color(Ink.ivory.opacity(0.22)), lineWidth: 1)
            }
            let f = min(0.999, max(0.001, fraction)), a0 = -Double.pi / 2, a1 = a0 + f * 2 * .pi
            var arc = Path(); arc.addArc(center: c, radius: r - 7, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
            ctx.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            var hand = Path(); hand.move(to: c); hand.addLine(to: CGPoint(x: c.x + cos(a1) * (r - 4), y: c.y + sin(a1) * (r - 4)))
            ctx.stroke(hand, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.4, y: c.y - 2.4, width: 4.8, height: 4.8)), with: .color(color))
        }.frame(width: 56, height: 56).accessibilityHidden(true)
    }
}

/// One instrument: dial, label, value with unit, and a coloured note.
struct GaugeCard: View {
    var label: String, value: String, unit: String, note: String
    var fraction: Double, color: Color
    var body: some View {
        HStack(spacing: 14) {
            DialGauge(fraction: fraction, color: color)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.bt(size: 9.5, weight: .medium, design: .monospaced)).tracking(2.2).foregroundStyle(Ink.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.bt(size: 22, design: .serif)).foregroundStyle(Ink.ivory).monospacedDigit()
                    if !unit.isEmpty { Text(unit).font(.bt(size: 11)).foregroundStyle(Ink.muted) }
                }
                Text(note).font(.bt(size: 11)).foregroundStyle(color == Ink.onTrack ? Ink.muted : color).lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 16).padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.panel, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.line))
            .accessibilityElement(children: .combine)
    }
}

/// Dots joined by faint lines; green when the day was fine, red when not. Missing days are skipped.
struct DotSpark: View {
    var values: [Double?]
    var good: (Double) -> Bool
    var inverted = false
    var body: some View {
        Canvas { ctx, size in
            let known = values.compactMap { $0 }
            guard let lo = known.min(), let hi = known.max(), values.count > 1 else { return }
            let span = hi - lo == 0 ? 1 : hi - lo
            func pt(_ i: Int, _ v: Double) -> CGPoint {
                let t = (v - lo) / span
                return CGPoint(x: 8 + (size.width - 16) * Double(i) / Double(values.count - 1), y: inverted ? 5 + t * (size.height - 10) : size.height - 5 - t * (size.height - 10))
            }
            var last: CGPoint?
            for (i, v) in values.enumerated() {
                guard let v else { last = nil; continue }
                let p = pt(i, v)
                if let last { var l = Path(); l.move(to: last); l.addLine(to: p); ctx.stroke(l, with: .color(Ink.ivory.opacity(0.18)), lineWidth: 1) }
                last = p
            }
            for (i, v) in values.enumerated() {
                guard let v else { continue }
                let p = pt(i, v)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.2, y: p.y - 3.2, width: 6.4, height: 6.4)), with: .color(good(v) ? Ink.onTrack : Ink.offTrack))
            }
        }.frame(height: 34).accessibilityHidden(true)
    }
}

/// "Pattern · …" in a lamp-tinted box.
struct PatternBox: View {
    var text: String
    var body: some View {
        (Text("Pattern").foregroundStyle(Ink.lamp) + Text(" · " + text).foregroundStyle(Ink.ivory))
            .font(.bt(size: 12)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.lamp.opacity(0.07), in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Ink.lamp.opacity(0.25)))
    }
}

/// "7 h 47" for minutes; "45 m" under an hour.
func shortDuration(_ minutes: Double) -> String {
    let m = Int(minutes.rounded())
    return m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60))" : "\(m) m"
}
func hourName(_ h: Int) -> String { h == 0 ? "midnight" : h == 12 ? "noon" : h < 12 ? "\(h) am" : "\(h - 12) pm" }

// MARK: - Health

/// Condition → Health: the day in one line, five instruments, the day on the wire and the last 7 days.
/// Sources and setup live in Settings.
struct HealthView: View {
    @ObservedObject var store: TrackerStore
    @ObservedObject var screen: ScreenTimeStore
    @State private var day = ""
    @State private var fallback = ""
    init(store: TrackerStore) { self.store = store; screen = store.screenTime }
    private var archive: HealthArchive { store.document.health }
    private var engine: TrackerEngine { store.engine }
    private func settle() {
        let d = Condition.reportDay(today: store.today, engine: engine) { archive.report(on: $0, document: store.document).hasData }
        fallback = d; day = d
    }

    var body: some View {
        let key = day.isEmpty ? store.today : day
        let r = archive.report(on: key, document: store.document)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ConditionLede(text: lede(r)) { dateBar(key) }
                HStack(spacing: 12) { gauges(r, key) }
                HStack(alignment: .top, spacing: 16) {
                    wire(r, key)
                    week(key).frame(width: 450)
                }
            }.padding(.bottom, 12)
        }
        .onAppear { if day.isEmpty { settle() } }
        .onChange(of: store.today) { _, _ in settle() }
    }

    private func lede(_ r: HealthReport) -> String {
        Condition.healthLede(asleep: r.asleepMinutes, asleepAt: r.night.map { Condition.signedMinute($0.start, calendar: engine.calendar) },
                             planMinutes: r.planMinutes > 0 ? r.planMinutes : 480, stress: r.stressAverage, steps: r.steps)
            .replacingOccurrences(of: #"(\d+) h (\d+) m"#, with: "$1 h $2", options: .regularExpression)
    }

    private func dateBar(_ key: String) -> some View {
        let tail = key == store.today ? " · SO FAR" : key == fallback ? " · LAST FULL DAY" : ""
        return HStack(spacing: 6) {
            Button { day = engine.adding(-1, to: key) } label: { Image(systemName: "chevron.left").font(.system(size: 10)).frame(width: 26, height: 26) }
                .buttonStyle(.plain).overlay(RoundedRectangle(cornerRadius: 6).stroke(Ink.line)).accessibilityLabel("Previous day")
            Text(dateText(key, engine: engine, pattern: "EEE d MMM").uppercased() + tail).font(.bt(size: 10.5, design: .monospaced)).tracking(1.4).foregroundStyle(Ink.ivory)
                .padding(.horizontal, 12).frame(height: 26).overlay(RoundedRectangle(cornerRadius: 6).stroke(Ink.line))
            Button { day = engine.adding(1, to: key) } label: { Image(systemName: "chevron.right").font(.system(size: 10)).frame(width: 26, height: 26) }
                .buttonStyle(.plain).overlay(RoundedRectangle(cornerRadius: 6).stroke(Ink.line)).disabled(key >= store.today).accessibilityLabel("Next day")
        }.foregroundStyle(Ink.muted)
    }

    // MARK: Instruments
    @ViewBuilder private func gauges(_ r: HealthReport, _ key: String) -> some View {
        let missing = Ink.watch
        // Sleep
        if let asleep = r.asleepMinutes, let night = r.night {
            let at = Condition.signedMinute(night.start, calendar: engine.calendar), late = Condition.lateMinutes(asleepAt: at)
            let off = late > 15 || asleep < (r.planMinutes > 0 ? r.planMinutes : 480) * 0.9
            GaugeCard(label: "SLEEP", value: shortDuration(asleep), unit: "", note: "Asleep \(HealthReport.clock((at + 1440) % 1440))" + (late > 15 ? " · \(shortDuration(Double(late))) late" : " · on time"),
                      fraction: asleep / 480, color: off ? Ink.offTrack : Ink.onTrack)
        } else { GaugeCard(label: "SLEEP", value: "—", unit: "", note: "No night recorded", fraction: 0, color: missing) }
        // Resting heart rate: Mi Fitness's figure; amber when it hasn't arrived for 2+ days.
        let last = Condition.lastResting(archive, onOrBefore: key, engine: engine)
        let stale = last.map { $0.day < engine.adding(-1, to: key) } ?? true
        if let value = stale ? (last?.value ?? r.restingHeartRate) : (r.restingHeartRate ?? last?.value) {
            GaugeCard(label: "RESTING HR", value: "\(Int(value.rounded()))", unit: "bpm",
                      note: stale ? (last.map { "Last read \(dateText($0.day, engine: engine, pattern: "d MMM"))" } ?? "Lowest while asleep") : value < 60 ? "Under 60 · strong" : "Mi Fitness daily figure",
                      fraction: value / 100, color: stale ? missing : Ink.onTrack)
        } else { GaugeCard(label: "RESTING HR", value: "—", unit: "", note: "Not sent yet", fraction: 0, color: missing) }
        // Stress
        if let s = r.stressAverage {
            let evening = Condition.stress(archive, on: key, engine: engine, eveningOnly: true)
            GaugeCard(label: "STRESS", value: "\(Int(s.rounded()))", unit: "avg", note: (s < 30 ? "Low" : s < 50 ? "Medium" : "High") + (evening.map { " · evening \(Int($0.rounded()))" } ?? ""),
                      fraction: s / 100, color: s < 30 ? Ink.onTrack : s < 50 ? Ink.accent : Ink.offTrack)
        } else { GaugeCard(label: "STRESS", value: "—", unit: "", note: "No readings", fraction: 0, color: missing) }
        // Blood oxygen
        if let o = r.oxygenAverage {
            GaugeCard(label: "BLOOD OXYGEN", value: "\(Int(o.rounded()))", unit: "%", note: (o >= 95 ? "Normal" : "Below normal") + (r.oxygenLow.map { " · low \(Int($0))" } ?? ""),
                      fraction: o / 100, color: o >= 95 ? Ink.onTrack : Ink.offTrack)
        } else { GaugeCard(label: "BLOOD OXYGEN", value: "—", unit: "", note: "No readings", fraction: 0, color: missing) }
        // Steps against the floor
        if let steps = r.steps {
            let floor = Condition.stepsFloor
            GaugeCard(label: "STEPS", value: Int(steps).formatted(), unit: "", note: steps < floor ? "Floor is \(Int(floor).formatted())" : "Over the \(Int(floor).formatted()) floor",
                      fraction: min(1, steps / floor), color: steps < floor ? Ink.offTrack : Ink.onTrack)
        } else { GaugeCard(label: "STEPS", value: "—", unit: "", note: "No steps received", fraction: 0, color: missing) }
    }

    // MARK: The day on the wire
    private struct Hourly: Identifiable { var hour: Int; var value: Double; var id: Int { hour } }
    private func hourly(_ points: [HealthReport.Point], dayStart: Double) -> [Hourly] {
        var sums: [Int: (Double, Int)] = [:]
        for p in points { let h = Int((p.time - dayStart) / 3600); guard (0..<24).contains(h) else { continue }; let s = sums[h] ?? (0, 0); sums[h] = (s.0 + p.value, s.1 + 1) }
        return sums.keys.sorted().map { Hourly(hour: $0, value: sums[$0]!.0 / Double(sums[$0]!.1)) }
    }
    private func at(_ dayStart: Double, _ hour: Double) -> Date { Date(timeIntervalSince1970: dayStart + hour * 3600) }

    private func wire(_ r: HealthReport, _ key: String) -> some View {
        let heart = hourly(r.heart, dayStart: r.dayStart), stress = hourly(r.stress, dayStart: r.dayStart)
        let sessions = archive.sleepSessions(on: key, engine: engine)
        let peak = heart.max { $0.value < $1.value }
        let top = max(100, (peak?.value ?? 0) + 8)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                CardTitle("The day on the wire")
                Spacer()
                HStack(spacing: 12) { legend("heart rate", Ink.accent, line: true); legend("stress", Color(hex: 0x5E8A78)); legend("asleep", Color(hex: 0x3A5A4E)) }
            }
            if heart.isEmpty && stress.isEmpty {
                Text("No heart-rate or stress readings for this day.").font(.bt(size: 12)).foregroundStyle(Ink.muted).frame(maxWidth: .infinity, minHeight: 240)
            } else {
                Chart {
                    ForEach(Array(sessions.enumerated()), id: \.offset) { i, s in
                        RectangleMark(xStart: .value("From", Date(timeIntervalSince1970: max(s.start, r.dayStart))), xEnd: .value("To", Date(timeIntervalSince1970: s.end)), yStart: .value("Low", 40), yEnd: .value("High", top))
                            .foregroundStyle(Color(hex: 0x3A5A4E).opacity(i == 0 ? 0.40 : 0.28))
                            .annotation(position: .overlay, alignment: .top) {
                                Text(i == 0 ? "ASLEEP \(HealthReport.clock(minute(s.start)).uppercased()) – \(HealthReport.clock(minute(s.end)).uppercased())".replacingOccurrences(of: " AM –", with: " –").replacingOccurrences(of: " PM –", with: " –") : "NAP")
                                    .font(.bt(size: 9.5, design: .monospaced)).tracking(1.4).foregroundStyle(Color(hex: 0xB9D2C6)).padding(.top, 8).lineLimit(1).fixedSize()
                            }
                    }
                    ForEach(stress) { s in
                        BarMark(x: .value("Hour", at(r.dayStart, Double(s.hour)), unit: .hour), yStart: .value("Base", 40), yEnd: .value("Stress", 40 + s.value * 0.6), width: .ratio(0.72))
                            .foregroundStyle(Color(hex: 0x5E8A78).opacity(0.55)).cornerRadius(2)
                    }
                    ForEach(heart) { h in
                        LineMark(x: .value("Hour", at(r.dayStart, Double(h.hour) + 0.5)), y: .value("BPM", h.value), series: .value("Series", "heart"))
                            .foregroundStyle(Ink.accent).lineStyle(StrokeStyle(lineWidth: 2.2, lineJoin: .round))
                    }
                    if let peak {
                        PointMark(x: .value("Hour", at(r.dayStart, Double(peak.hour) + 0.5)), y: .value("BPM", peak.value)).foregroundStyle(Ink.lamp).symbolSize(40)
                            .annotation(position: .topTrailing, spacing: 2) { Text("\(Int(peak.value.rounded())) bpm · \(hourName(peak.hour))").font(.bt(size: 10, design: .monospaced)).foregroundStyle(Ink.lamp) }
                    }
                }
                .chartXScale(domain: at(r.dayStart, 0)...at(r.dayStart, 24))
                .chartYScale(domain: 40...top)
                .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 24].map { at(r.dayStart, Double($0)) }) { v in
                    AxisValueLabel(anchor: .top) { if let d = v.as(Date.self) { Text(axisHour(d, r.dayStart)).font(.bt(size: 9.5, design: .monospaced)).foregroundStyle(Ink.muted) } }
                } }
                .chartYAxis { AxisMarks(position: .leading, values: [50, 70, 90]) { _ in AxisGridLine().foregroundStyle(Ink.ivory.opacity(0.06)); AxisValueLabel().font(.bt(size: 9.5, design: .monospaced)).foregroundStyle(Ink.muted) } }
                .frame(height: 250)
            }
            Spacer(minLength: 0)
            sourcesLine(key)
        }.conditionCard()
    }
    private func minute(_ t: Double) -> Int { let c = engine.calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: t)); return (c.hour ?? 0) * 60 + (c.minute ?? 0) }
    private func axisHour(_ d: Date, _ dayStart: Double) -> String {
        let h = Int(((d.timeIntervalSince1970 - dayStart) / 3600).rounded())
        return h % 24 == 0 ? "12 AM" : h == 12 ? "12 PM" : h < 12 ? "\(h) AM" : "\(h - 12) PM"
    }
    private func legend(_ text: String, _ color: Color, line: Bool = false) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: line ? 13 : 10, height: line ? 2 : 9)
            Text(text).font(.bt(size: 11)).foregroundStyle(Ink.muted)
        }
    }

    private func sourcesLine(_ key: String) -> some View {
        let last = Condition.lastResting(archive, onOrBefore: store.today, engine: engine)
        let restingStale = last.map { $0.day < engine.adding(-2, to: store.today) } ?? false
        func chip(_ name: String, _ time: Double?) -> some View {
            let fresh = time.map { Date().timeIntervalSince1970 - $0 < 6 * 3600 } ?? false
            return HStack(spacing: 6) {
                Circle().fill(fresh ? Ink.onTrack : Ink.watch).frame(width: 5, height: 5)
                Text(time.map { "\(name) · \(HealthReport.clock(minute($0)).uppercased())" } ?? "\(name) · NOT CONNECTED")
            }
        }
        return HStack(spacing: 16) {
            chip("MI FITNESS CLOUD", archive.cloudSync)
            chip("PHONE", archive.lastSync)
            if restingStale, let last {
                HStack(spacing: 6) { Circle().fill(Ink.watch).frame(width: 5, height: 5); Text("RESTING HR NOT SENT SINCE \(dateText(last.day, engine: engine, pattern: "d MMM").uppercased())") }.foregroundStyle(Ink.watch)
            }
            Spacer(minLength: 8)
            Button("SETUP LIVES IN SETTINGS") { store.pendingScreen = "Settings" }.buttonStyle(.plain).help("Pair phone, Mi Fitness sign-in and sources")
        }.font(.bt(size: 9.5, design: .monospaced)).tracking(1.2).foregroundStyle(Ink.muted).lineLimit(1)
    }

    // MARK: Last 7 days
    private func week(_ key: String) -> some View {
        let keys = (0..<7).reversed().map { engine.adding(-$0, to: key) }
        let asleep: [Double?] = keys.map { k in archive.sleepSessions(on: k, engine: engine).first.map { Double(Condition.signedMinute($0.start, calendar: engine.calendar)) } }
        let steps: [Double?] = keys.map { Condition.steps(archive, on: $0, engine: engine) }
        let stress: [Double?] = keys.map { Condition.stress(archive, on: $0, engine: engine) }
        let phone = phoneDevice
        let hours: [Double?] = keys.map { k in phone.flatMap { Condition.day($0, key: k, engine: engine)?.screenSeconds }.map { $0 / 3600 } }
        let workouts = keys.map { !archive.records(.workout, on: $0, engine: engine).isEmpty }
        func avg(_ v: [Double?]) -> Double? { let x = v.compactMap { $0 }; return x.isEmpty ? nil : x.reduce(0, +) / Double(x.count) }
        let first = dateText(keys[0], engine: engine, pattern: "d"), last = dateText(keys[6], engine: engine, pattern: "d MMM")
        let pattern = Condition.stepsPattern(days: keys.indices.map { (dateText(keys[$0], engine: engine, pattern: "d MMM"), steps[$0], workouts[$0]) })
        return VStack(alignment: .leading, spacing: 0) {
            HStack { CardTitle("Last 7 days"); Spacer(); Text("\(first) – \(last) · automatic").font(.bt(size: 11)).foregroundStyle(Ink.muted) }.padding(.bottom, 8)
            row("Asleep at", DotSpark(values: asleep, good: { $0 <= Double(Condition.asleepBy) }, inverted: true),
                avg(asleep).map { "avg \(HealthReport.clock((Int($0.rounded()) + 1440) % 1440))" }, bad: avg(asleep).map { $0 > Double(Condition.asleepBy) } ?? false)
            row("Steps", DotSpark(values: steps, good: { $0 >= Condition.stepsFloor }), avg(steps).map { "avg \(Int($0.rounded()).formatted())" }, bad: avg(steps).map { $0 < Condition.stepsFloor } ?? false)
            row("Stress", DotSpark(values: stress, good: { $0 < 30 }, inverted: true), avg(stress).map { "avg \(Int($0.rounded()))" }, bad: avg(stress).map { $0 >= 50 } ?? false)
            row("Phone", DotSpark(values: hours, good: { $0 < 6 }, inverted: true), avg(hours).map { "avg \(shortDuration($0 * 60))" }, bad: false)
            row("Workouts", HStack(spacing: 0) {
                ForEach(workouts.indices, id: \.self) { i in
                    Circle().fill(workouts[i] ? Ink.accent : Color.clear).overlay(Circle().stroke(workouts[i] ? Color.clear : Ink.ivory.opacity(0.25))).frame(width: 10, height: 10).frame(maxWidth: .infinity)
                }
            }.frame(height: 34), "\(workouts.filter { $0 }.count) this week", bad: false, divider: false)
            if let pattern { PatternBox(text: pattern).padding(.top, 14) }
        }.conditionCard()
    }
    private func row<V: View>(_ title: String, _ spark: V, _ average: String?, bad: Bool, divider: Bool = true) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.bt(size: 13)).foregroundStyle(Ink.ivory).frame(width: 110, alignment: .leading)
            spark.frame(maxWidth: .infinity)
            Text(average ?? "—").font(.bt(size: 11, design: .monospaced)).foregroundStyle(bad ? Ink.offTrack : Ink.ivory.opacity(0.85)).frame(width: 96, alignment: .trailing)
        }.padding(.vertical, 9).overlay(alignment: .bottom) { if divider { Line() } }
    }
    private var phoneDevice: ScreenTimeDevice? { screen.archive.devices.filter { $0.source != "macKnowledge" }.max { $0.lastSync < $1.lastSync } }
}

// MARK: - Screen time

/// Condition → Screen time: yesterday's phone total, the week, phone after 11 pm against when you fell asleep,
/// the top apps, and whether this Mac is still recording. Device setup and export live in Settings.
struct ConditionScreenTimeView: View {
    @ObservedObject var store: TrackerStore
    @ObservedObject var screen: ScreenTimeStore
    @ObservedObject var mac: MacScreenTimeService
    init(store: TrackerStore) { self.store = store; screen = store.screenTime; mac = store.macScreenTime }
    private var engine: TrackerEngine { store.engine }
    private var phone: ScreenTimeDevice? { screen.archive.devices.filter { $0.source != "macKnowledge" }.max { $0.lastSync < $1.lastSync } }
    private var macDevice: ScreenTimeDevice? { screen.archive.devices.first { $0.source == "macKnowledge" } }
    private func duration(_ seconds: Double) -> String { HealthReport.duration(seconds / 60) }

    /// Yesterday, or the latest finished phone day before today.
    private var shownDay: (key: String, day: ScreenTimeDay)? {
        guard let phone else { return nil }
        let yesterday = engine.adding(-1, to: store.today)
        if let d = Condition.day(phone, key: yesterday, engine: engine), d.screenSeconds != nil { return (yesterday, d) }
        return phone.days.last { $0.screenSeconds != nil && engine.key(Date(timeIntervalSince1970: $0.start + 60)) < store.today }
            .map { (engine.key(Date(timeIntervalSince1970: $0.start + 60)), $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let phone, let shown = shownDay {
                    let keys = (0..<7).reversed().map { engine.adding(-$0, to: shown.key) }
                    let week = keys.map { k in Condition.day(phone, key: k, engine: engine)?.screenSeconds }
                    let known = week.compactMap { $0 }, average = known.isEmpty ? nil : known.reduce(0, +) / Double(known.count)
                    ConditionLede(text: "\(duration(shown.day.screenSeconds ?? 0)) on the phone \(shown.key == engine.adding(-1, to: store.today) ? "yesterday" : "on " + dateText(shown.key, engine: engine, pattern: "d MMM")).") {
                        topLine(shown.day, average: average)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 16) { bars(phone, keys: keys, values: week, average: average); nights(phone) }
                        VStack(spacing: 16) { topApps(shown.day, yesterday: shown.key == engine.adding(-1, to: store.today)); thisMac }.frame(width: 420)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No phone screen time yet.").font(.bt(size: 20, weight: .semibold))
                        Text("Open Ascend Bridge on your phone → Settings → Share screen time with Mac, allow Usage access, then tap Sync now. Pairing lives in Settings.").font(.bt(size: 12)).foregroundStyle(Ink.muted)
                        Button("Open Settings") { store.pendingScreen = "Settings" }
                    }.conditionCard()
                    thisMac
                }
                if let error = screen.error { Text(error).font(.bt(size: 12)).foregroundStyle(Ink.watch) }
            }.padding(.bottom, 12)
        }
    }

    private func topLine(_ day: ScreenTimeDay, average: Double?) -> some View {
        let top = day.apps.max { $0.seconds < $1.seconds }
        return HStack(spacing: 0) {
            if let top {
                Text(top.label + " ").foregroundStyle(Ink.muted)
                Text(duration(top.seconds)).foregroundStyle(Ink.ivory).fontWeight(.semibold)
                Text(" of it").foregroundStyle(Ink.muted)
            }
            if let average { Text((top == nil ? "" : " · ") + "week average \(duration(average))").foregroundStyle(Ink.muted) }
        }.font(.bt(size: 12.5)).lineLimit(1)
    }

    private struct Bar: Identifiable { var i: Int; var label: String; var hours: Double; var id: Int { i } }
    private func bars(_ phone: ScreenTimeDevice, keys: [String], values: [Double?], average: Double?) -> some View {
        let data = keys.indices.compactMap { i in values[i].map { Bar(i: i, label: i == 0 || i == keys.count - 1 ? dateText(keys[i], engine: engine, pattern: "d MMM").uppercased() : dateText(keys[i], engine: engine, pattern: "d"), hours: $0 / 3600) } }
        let top = max(10, (data.map(\.hours).max() ?? 0) + 1.5)
        return VStack(alignment: .leading, spacing: 14) {
            HStack { CardTitle("Phone · last 7 days"); Spacer(); Text("\(phone.name) · Mac shown separately").font(.bt(size: 11)).foregroundStyle(Ink.muted) }
            Chart {
                ForEach(data) { b in
                    BarMark(x: .value("Day", b.label), y: .value("Hours", b.hours), width: .ratio(0.64))
                        .foregroundStyle(b.i == keys.count - 1 ? Ink.lamp : Ink.accent.opacity(0.55)).cornerRadius(4)
                        .annotation(position: .top, spacing: 5) { Text(shortDuration(b.hours * 60)).font(.bt(size: 9.5, design: .monospaced)).foregroundStyle(Ink.ivory) }
                }
                if let average { RuleMark(y: .value("Average", average / 3600)).foregroundStyle(Ink.ivory.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 5])) }
            }
            .chartYScale(domain: 0...top).chartYAxis(.hidden)
            .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.bt(size: 9.5, design: .monospaced)).foregroundStyle(Ink.muted) } }
            .frame(height: 190)
        }.conditionCard()
    }

    private func nights(_ phone: ScreenTimeDevice) -> some View {
        let hour = engine.calendar.component(.hour, from: Date())
        let lastEvening = engine.adding(hour >= 4 ? -1 : -2, to: store.today)
        let evenings = (0..<7).reversed().map { engine.adding(-$0, to: lastEvening) }
        let health = store.document.health
        let rows: [(key: String, minutes: Double?, asleep: Int?)] = evenings.map { e in
            (e, Condition.afterHoursMinutes(phone, evening: e, engine: engine),
             health.sleepSessions(on: engine.adding(1, to: e), engine: engine).first.map { Condition.signedMinute($0.start, calendar: engine.calendar) })
        }
        let most = max(60, rows.compactMap(\.minutes).max() ?? 60)
        let pattern = Condition.nightsPattern(rows.compactMap { r in r.minutes.map { ($0, r.asleep) } })
        return VStack(alignment: .leading, spacing: 10) {
            HStack { CardTitle("After Black Tie hours begin"); Spacer(); Text("Phone use 11 pm – 4 am · and when you fell asleep").font(.bt(size: 11)).foregroundStyle(Ink.muted) }.padding(.bottom, 4)
            ForEach(rows, id: \.key) { r in
                HStack(spacing: 14) {
                    Text(dateText(r.key, engine: engine, pattern: "d MMM").uppercased()).font(.bt(size: 10, design: .monospaced)).foregroundStyle(Ink.muted).frame(width: 52, alignment: .leading)
                    GeometryReader { g in
                        Capsule().fill(Ink.ivory.opacity(0.06)).overlay(alignment: .leading) {
                            Capsule().fill(Ink.accent.opacity((r.minutes ?? 0) >= 60 ? 0.85 : 0.45)).frame(width: max(3, g.size.width * min(1, (r.minutes ?? 0) / most)))
                        }
                    }.frame(height: 6)
                    Text(r.minutes.map { $0 >= 60 ? shortDuration($0) : "\(Int($0)) m" } ?? "—").font(.bt(size: 11, design: .monospaced)).foregroundStyle(Ink.ivory).frame(width: 56, alignment: .trailing)
                    Text(r.asleep.map { "asleep \(HealthReport.clock(($0 + 1440) % 1440))" } ?? "no sleep data").font(.bt(size: 11, design: .monospaced))
                        .foregroundStyle(r.asleep.map { Condition.lateMinutes(asleepAt: $0) > 0 ? Ink.offTrack : Ink.onTrack } ?? Ink.muted).frame(width: 130, alignment: .trailing)
                }.frame(height: 22)
            }
            if let pattern { PatternBox(text: pattern).padding(.top, 8) }
        }.conditionCard()
    }

    private func topApps(_ day: ScreenTimeDay, yesterday: Bool) -> some View {
        let apps = Array(day.apps.sorted { $0.seconds > $1.seconds }.prefix(3)), most = apps.first?.seconds ?? 1
        return VStack(alignment: .leading, spacing: 0) {
            HStack { CardTitle(yesterday ? "Yesterday's top apps" : "Top apps · " + dateText(engine.key(Date(timeIntervalSince1970: day.start + 60)), engine: engine, pattern: "d MMM")); Spacer(); Text("Phone").font(.bt(size: 11)).foregroundStyle(Ink.muted) }.padding(.bottom, 8)
            if apps.isEmpty { Text("No app sessions for this day.").font(.bt(size: 12)).foregroundStyle(Ink.muted).padding(.vertical, 10) }
            ForEach(Array(apps.enumerated()), id: \.offset) { i, app in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(app.label).font(.bt(size: 13)).foregroundStyle(Ink.ivory)
                        GeometryReader { g in Capsule().fill(Ink.accent.opacity(0.8)).frame(width: max(4, g.size.width * app.seconds / most)) }.frame(height: 3)
                    }
                    Text(shortDuration(app.seconds / 60)).font(.bt(size: 11, design: .monospaced)).foregroundStyle(Ink.muted).frame(width: 60, alignment: .trailing)
                }.padding(.vertical, 10).overlay(alignment: .top) { if i > 0 { Line() } }
            }
        }.conditionCard()
    }

    @ViewBuilder private var thisMac: some View {
        let recorded = macDevice?.days.filter { ($0.screenSeconds ?? 0) > 0 } ?? []
        let lastKey = recorded.last.map { engine.key(Date(timeIntervalSince1970: $0.start + 60)) }
        let stopped = lastKey.map { $0 < engine.adding(-2, to: store.today) } ?? true
        let recent = Array(recorded.suffix(7))
        let average = recent.isEmpty ? nil : recent.compactMap(\.screenSeconds).reduce(0, +) / Double(recent.count)
        let topNames = Dictionary(grouping: recent.flatMap(\.apps), by: \.label).mapValues { $0.map(\.seconds).reduce(0, +) }.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardTitle("This Mac"); Spacer()
                Text(macDevice == nil ? "Not set up" : stopped ? "Stopped recording" : "Recording").font(.bt(size: 11)).foregroundStyle(macDevice == nil || stopped ? Ink.watch : Ink.onTrack)
            }
            if let lastKey, let average {
                Group {
                    if stopped {
                        Text("Last day recorded: ").foregroundStyle(Ink.ivory.opacity(0.85)) + Text(dateText(lastKey, engine: engine, pattern: "d MMM")).foregroundStyle(Ink.ivory).fontWeight(.semibold)
                            + Text(". Before that, about \(shortDuration(average / 60)) a day" + (topNames.isEmpty ? "." : " (\(topNames.joined(separator: ", "))).")).foregroundStyle(Ink.ivory.opacity(0.85))
                    } else {
                        Text("About \(shortDuration(average / 60)) a day this week" + (topNames.isEmpty ? "." : " · \(topNames.joined(separator: ", ")).")).foregroundStyle(Ink.ivory.opacity(0.85))
                    }
                }.font(.bt(size: 12.5)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            if stopped {
                Text(mac.needsAccess ? "Ascend has lost Full Disk Access. macOS drops it each time the app is rebuilt; add Ascend again in Privacy & Security → Full Disk Access." : "Likely cause: macOS dropped Full Disk Access when Ascend was rebuilt.")
                    .font(.bt(size: 11.5)).foregroundStyle(Ink.watch).fixedSize(horizontal: false, vertical: true)
                if mac.failed, let status = mac.status { Text(status).font(.bt(size: 11)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true) }
            }
            HStack {
                Text("Fix and the 15-minute refresh live in Settings.").font(.bt(size: 11)).foregroundStyle(Ink.muted)
                Spacer()
                Button("Open Settings") { store.pendingScreen = "Settings" }.font(.bt(size: 11))
            }
        }.conditionCard()
    }
}

// MARK: - Photo vault

/// Progress photos behind Touch ID inside Body. Opens on the first body photo next to the latest, same angle.
struct PhotoVaultCard: View {
    @ObservedObject var store: TrackerStore
    var open: () -> Void
    @State private var checking = false
    @State private var refused = false
    var body: some View {
        let photos = store.document.photos.photos
        let lastFront = store.document.photos.photos(.body, angle: .front).last
        let overdue = lastFront.map { Date().timeIntervalSince1970 - $0.takenAt > 14 * 86_400 } ?? true
        Button(action: unlock) {
            HStack(spacing: 18) {
                Image(systemName: "touchid").font(.system(size: 26, weight: .light)).foregroundStyle(Ink.lamp)
                    .frame(width: 58, height: 58).overlay(Circle().stroke(Ink.accent.opacity(0.5)))
                VStack(alignment: .leading, spacing: 7) {
                    CardTitle("Progress photos · eyes only")
                    (Text("Opens on ").foregroundStyle(Ink.ivory.opacity(0.85)) + Text("your first photo next to your latest").foregroundStyle(Ink.ivory).fontWeight(.semibold) + Text(", same angle.").foregroundStyle(Ink.ivory.opacity(0.85)))
                        .font(.bt(size: 12.5))
                    HStack(spacing: 6) {
                        ForEach(PhotoArea.allCases, id: \.self) { area in chip("\(area.label) \(photos.filter { $0.area == area }.count)", Ink.muted) }
                        if overdue { chip(lastFront.map { "Body front: last one \(dateText($0.day, engine: store.engine, pattern: "d MMM"))" } ?? "No body front photo yet", Ink.watch) }
                    }
                }
                Spacer(minLength: 8)
                VStack { Text(checking ? "Checking…" : refused ? "Not opened" : "Touch ID to open").font(.bt(size: 11)).foregroundStyle(refused ? Ink.watch : Ink.muted); Spacer() }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).conditionCard(padding: 20).accessibilityLabel("Progress photos, eyes only. Touch ID to open.")
    }
    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(.bt(size: 10.5)).foregroundStyle(color).padding(.horizontal, 9).padding(.vertical, 3)
            .overlay(Capsule().stroke(color == Ink.watch ? Ink.watch.opacity(0.6) : Ink.line))
    }
    private func unlock() {
        let context = LAContext()
        context.localizedCancelTitle = "Keep closed"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { open(); return }
        checking = true; refused = false
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "open your progress photos") { ok, _ in
            DispatchQueue.main.async { checking = false; if ok { open() } else { refused = true } }
        }
    }
}
