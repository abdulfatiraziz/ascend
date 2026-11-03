import SwiftUI
import Charts
import AscendCore

/// The Health tab as a daily report: recovery, vitals, the day hour by hour, last night against the plan,
/// eight-day trends and plain-language signals, then the phone and Mi Fitness cloud connections.
struct HealthView: View {
    @ObservedObject var store: TrackerStore
    @State private var day: String
    init(store: TrackerStore) { self.store = store; _day = State(initialValue: store.today) }
    private var archive: HealthArchive { store.document.health }

    var body: some View {
        let report = archive.report(on: day, document: store.document)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(report)
                if report.hasData {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) { RecoveryCard(report: report).frame(width: 340); vitals(report) }
                        VStack(spacing: 14) { RecoveryCard(report: report); vitals(report) }
                    }
                    DayTrace(report: report, isToday: day == store.today)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) { SleepCard(report: report); PlanCard(report: report).frame(width: 320) }
                        VStack(spacing: 14) { SleepCard(report: report); PlanCard(report: report) }
                    }
                    trends(report)
                    if !report.signals.isEmpty { signals(report) }
                } else {
                    emptyState
                }
                sources
            }.padding(.bottom, 10)
        }
        .onChange(of: store.today) { old, new in if day == old { day = new } }
    }

    // MARK: Header
    private func header(_ report: HealthReport) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Mono(dateText(day, engine: store.engine, pattern: "EEEE d MMMM").uppercased().replacingOccurrences(of: ",", with: ""), prefix: "HEALTH REPORT · ", color: Ink.accent)
                Text(report.headline).font(.system(size: 30, weight: .semibold)).tracking(-0.4)
                if !report.summary.isEmpty { Text(report.summary).font(.system(size: 13)).foregroundStyle(Ink.muted).lineSpacing(3).frame(maxWidth: 760, alignment: .leading).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 6) {
                    Button { day = store.engine.adding(-1, to: day) } label: { Image(systemName: "chevron.left").frame(width: 30, height: 30) }.buttonStyle(.plain).background(Ink.panel, in: RoundedRectangle(cornerRadius: 9)).accessibilityLabel("Previous day")
                    DatePicker("Health date", selection: Binding(get: { store.engine.date(day) ?? Date() }, set: { day = store.engine.key($0) }), in: ...Date(), displayedComponents: .date).labelsHidden().fixedSize()
                    Button("Today") { day = store.today }.buttonStyle(.plain).font(.system(size: 12)).padding(.horizontal, 12).frame(height: 30).background(Ink.accent.opacity(day == store.today ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 9))
                    Button { day = store.engine.adding(1, to: day) } label: { Image(systemName: "chevron.right").frame(width: 30, height: 30) }.buttonStyle(.plain).background(Ink.panel, in: RoundedRectangle(cornerRadius: 9)).disabled(day >= store.today).accessibilityLabel("Next day")
                }
                HStack(spacing: 8) {
                    chip("MI FITNESS CLOUD", archive.cloudSync, on: store.xiaomi.connected)
                    chip("PHONE", archive.lastSync, on: !store.phoneLink.phones.isEmpty)
                }
            }
        }
    }
    private func chip(_ name: String, _ time: Double?, on: Bool) -> some View {
        let label = time.map { "\(name) · \(HealthReport.clock(minute(of: $0)).uppercased())" } ?? "\(name) · NOT CONNECTED"
        return HStack(spacing: 6) {
            Circle().fill(on && time != nil ? Health.green : Color.orange).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10, design: .monospaced)).foregroundStyle(Ink.muted)
        }.padding(.horizontal, 10).padding(.vertical, 5).background(Ink.panel, in: Capsule()).overlay(Capsule().stroke(Ink.line))
    }
    private func minute(of t: Double) -> Int {
        let c = store.engine.calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: t)); return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    // MARK: Vitals
    private func vitals(_ r: HealthReport) -> some View {
        let restingNote: String = {
            guard r.restingHeartRate != nil else { return "No resting figure for this date" }
            let range = r.restingSeries.isEmpty ? "" : " · range \(Int(r.restingSeries.min()!))–\(Int(r.restingSeries.max()!))"
            return r.restingBaseline.map { "14-day baseline \(Int($0.rounded()))" + range } ?? (r.restingSource == "asleep" ? "Lowest while asleep" : "Mi Fitness daily figure")
        }()
        let goal = r.stepGoal
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
            VitalTile(label: "RESTING HR", value: r.restingHeartRate.map { "\(Int($0))" }, unit: "BPM", color: Ink.accent, series: r.restingSeries, note: restingNote)
            VitalTile(label: "STRESS", value: r.stressAverage.map { "\(Int($0.rounded()))" }, unit: "/ 100 AVG", color: Health.amber, series: r.stress.map(\.value),
                      note: r.stressHigh.map { "High \(Int($0)) · \(Int(((r.relaxedShare ?? 0) * 100).rounded()))% of the day relaxed" } ?? "No stress readings · sign in to the Mi Fitness cloud")
            VitalTile(label: "HEART RATE", value: r.heartAverage.map { "\(Int($0.rounded()))" }, unit: "BPM AVG", color: Ink.accent, series: r.heart.map(\.value),
                      note: r.heartLow.map { "Range \(Int($0))–\(Int(r.heartHigh ?? $0)) · \(r.heartReadings.formatted()) readings" } ?? "No heart-rate readings")
            VitalTile(label: "BLOOD OXYGEN", value: r.oxygenAverage.map { $0.formatted(.number.precision(.fractionLength(1))) }, unit: "%", color: Health.teal, series: r.oxygen.map(\.value),
                      note: r.oxygenLow.map { "Low \(Int($0))%" } ?? "No SpO2 readings")
            VitalTile(label: "STEPS", value: r.steps.map { Int($0).formatted() }, unit: goal.map { "/ \(Int($0).formatted())" } ?? "", color: Health.green,
                      series: r.trend.compactMap(\.steps),
                      note: r.steps.map { s in (goal.map { "\(Int(s / $0 * 100))% of goal" } ?? "Mi Fitness daily total") + (r.distance.map { " · \(($0 / 1000).formatted(.number.precision(.fractionLength(1)))) km" } ?? "") } ?? "No steps received for this date")
            VitalTile(label: "ACTIVE ENERGY", value: r.activeEnergy.map { "\(Int($0))" }, unit: "KCAL", color: Health.green, series: [],
                      note: r.workouts.isEmpty ? "No workout recorded" : r.workouts.map { "\(Int(($0.end - $0.start) / 60)) min workout at \(HealthReport.clock(minute(of: $0.start)))" }.joined(separator: " · "))
        }
    }

    // MARK: Trends
    private func trends(_ r: HealthReport) -> some View {
        let sleep = r.trend.map { $0.sleepHours }, steps = r.trend.map { $0.steps }, resting = r.trend.map { $0.restingHeartRate }, bed = r.trend.map { $0.bedtime }
        let goal = r.stepGoal ?? 10_000, planBed = r.planBed.map { Double($0 > 720 ? $0 - 1440 : $0) / 60 }
        func avg(_ v: [Double?]) -> Double? { let x = v.compactMap { $0 }; return x.isEmpty ? nil : x.reduce(0, +) / Double(x.count) }
        let labels = r.trend.map { dateText($0.day, engine: store.engine, pattern: "EEEEE") }
        let first = r.trend.first.map { dateText($0.day, engine: store.engine, pattern: "d MMM") } ?? "", last = dateText(r.day, engine: store.engine, pattern: "d MMM")
        return VStack(alignment: .leading, spacing: 10) {
            HStack { Mono("LAST 8 DAYS"); Spacer(); Mono("\(first) – \(last)".uppercased()) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                TrendCard(title: "Sleep", summary: avg(sleep).map { "AVG \(HealthReport.duration($0 * 60).uppercased())" } ?? "", values: sleep, labels: labels,
                          range: 0...10, target: r.planMinutes / 60, color: Health.teal, flag: { _ in false },
                          note: "Hit \(HealthReport.duration(r.planMinutes)) on \(sleep.compactMap { $0 }.filter { $0 >= r.planMinutes / 60 - 0.05 }.count) of \(sleep.compactMap { $0 }.count) nights.")
                TrendCard(title: "Steps", summary: avg(steps).map { "AVG \(Int($0).formatted())" } ?? "", values: steps, labels: labels,
                          range: 0...max(goal * 1.2, (steps.compactMap { $0 }.max() ?? 0)), target: goal, color: Health.green, flag: { $0 < 3000 },
                          note: "\(Int(goal).formatted()) reached on \(steps.compactMap { $0 }.filter { $0 >= goal }.count) of \(steps.compactMap { $0 }.count) days.")
                TrendCard(title: "Resting heart rate", summary: avg(resting).map { "AVG \(Int($0.rounded())) BPM" } ?? "", values: resting, labels: labels,
                          range: 40...65, target: r.restingBaseline, color: Ink.accent, flag: { v in r.restingBaseline.map { v - $0 >= 5 } ?? false },
                          note: "A rise of 5 or more over your baseline usually means poor recovery.")
                TrendCard(title: "Bedtime", summary: r.planBed.map { "PLAN \(HealthReport.clock($0).uppercased())" } ?? "", values: bed.map { $0.map { $0 + 3 } }, labels: labels,
                          range: 0...7, target: planBed.map { $0 + 3 }, color: Ink.accent, flag: { v in planBed.map { v - 3 - $0 > 0.25 } ?? false },
                          note: "Bars show bedtime from 9 pm. " + (planBed.map { p in "On plan \(bed.compactMap { $0 }.filter { $0 - p <= 0.25 }.count) of \(bed.compactMap { $0 }.count) nights." } ?? "Set a routine to compare."))
            }
        }
    }

    // MARK: Signals and sources
    private func signals(_ r: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("SIGNALS").padding(.bottom, 8)
            ForEach(Array(r.signals.enumerated()), id: \.offset) { _, s in
                HStack(alignment: .top, spacing: 14) {
                    Circle().fill(s.tone == .warn ? Health.amber : s.tone == .good ? Ink.accent : Health.teal).frame(width: 8, height: 8).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.title).font(.system(size: 14))
                        Text(s.detail).font(.system(size: 12)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }.padding(.vertical, 11).overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
            }
        }.healthCard()
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No watch data for this day.").font(.system(size: 20, weight: .semibold))
            Text("1. Sign in to the Mi Fitness cloud below for heart rate, stress, SpO2 and resting heart rate.\n2. Pair Ascend Bridge on your phone for sleep, steps and workouts, then tap Sync to Mac.\n3. Pick another day with the arrows above to see earlier reports.").font(.system(size: 13)).lineSpacing(6)
        }.frame(maxWidth: .infinity, alignment: .leading).healthCard()
    }
    private var sources: some View {
        VStack(alignment: .leading, spacing: 10) {
            Mono("SOURCES")
            PhoneLinkPanel(link: store.phoneLink)
            XiaomiCloudPanel(cloud: store.xiaomi)
            if !archive.errors.isEmpty {
                VStack(alignment: .leading, spacing: 7) { Mono("SOME TYPES COULD NOT REFRESH"); ForEach(archive.errors.keys.sorted(), id: \.self) { key in Text("\(HealthMetric(rawValue: key)?.title ?? key): \(archive.errors[key] ?? "")").font(.system(size: 12)).foregroundStyle(.orange) } }.panel()
            }
            Text((archive.cloudSync == nil ? "Sleep, steps, heart rate and SpO2 from Health Connect via Ascend Bridge." : "Heart rate, SpO2, stress and resting heart rate from the Mi Fitness cloud · sleep, steps, calories and workouts from Health Connect via Ascend Bridge.") + " Stored on this Mac and left out of Ask Ascend. Sleep and step habits fill from these readings; a value you type yourself is kept.")
                .font(.system(size: 11)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Pieces

enum Health {
    static let amber = Color(red: 0.95, green: 0.70, blue: 0.36)
    static let teal = Color(red: 0.37, green: 0.83, blue: 0.88)
    static let green = Color(red: 0.49, green: 0.88, blue: 0.63)
    static let light = Color(red: 0.63, green: 0.54, blue: 1).opacity(0.55)
}
private extension View {
    func healthCard(padding: CGFloat = 22) -> some View {
        self.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.panel, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Ink.line))
    }
}
/// Small monospaced caps label.
private struct Mono: View {
    var text: String, prefix: String = "", color: Color = Ink.muted
    init(_ text: String, prefix: String = "", color: Color = Ink.muted) { self.text = text; self.prefix = prefix; self.color = color }
    var body: some View { Text(prefix + text).font(.system(size: 10.5, design: .monospaced)).tracking(1.4).foregroundStyle(color) }
}
/// A line through `values`, scaled to fit.
private struct Sparkline: View {
    var values: [Double], color: Color
    var body: some View {
        GeometryReader { geo in
            if values.count > 1, let lo = values.min(), let hi = values.max() {
                Path { p in
                    for (i, v) in values.enumerated() {
                        let point = CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(values.count - 1),
                                            y: geo.size.height - 2 - (geo.size.height - 4) * CGFloat(hi == lo ? 0.5 : (v - lo) / (hi - lo)))
                        i == 0 ? p.move(to: point) : p.addLine(to: point)
                    }
                }.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
    }
}
private struct VitalTile: View {
    var label: String, value: String?, unit: String, color: Color, series: [Double], note: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Mono(label); Spacer(); Circle().fill(color).frame(width: 7, height: 7) }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value ?? "—").font(.system(size: 30, weight: .semibold)).tracking(-0.5).lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(.system(size: 10, design: .monospaced)).foregroundStyle(Ink.muted)
            }
            Sparkline(values: series, color: color).frame(height: 26)
            Text(note).font(.system(size: 11)).foregroundStyle(Ink.muted).lineLimit(2).frame(minHeight: 28, alignment: .top)
        }.healthCard(padding: 16)
    }
}
private struct RecoveryCard: View {
    var report: HealthReport
    var body: some View {
        let rec = report.recovery
        VStack(alignment: .leading, spacing: 16) {
            HStack { Mono("RECOVERY"); Spacer(); Mono(rec?.label.uppercased() ?? "NOT ENOUGH DATA", color: rec == nil ? Ink.muted : Ink.accent) }
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 9)
                    Circle().trim(from: 0, to: CGFloat(rec?.score ?? 0) / 100).stroke(Ink.accent, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                    Circle().inset(by: 14).stroke(Ink.accent.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                    VStack(spacing: 0) {
                        Text(rec.map { "\($0.score)" } ?? "—").font(.system(size: 38, weight: .semibold))
                        Text("/ 100").font(.system(size: 9, design: .monospaced)).foregroundStyle(Ink.muted)
                    }
                }.frame(width: 128, height: 128).accessibilityElement(children: .ignore).accessibilityLabel(rec.map { "Recovery \($0.score) out of 100" } ?? "Recovery not available")
                VStack(alignment: .leading, spacing: 11) {
                    factor("Resting HR", report.restingHeartRate.map { r in "\(Int(r))" + (report.restingBaseline.map { " · \(Int($0.rounded()))" } ?? "") } ?? "—", rec?.resting, Ink.accent)
                    factor("Sleep", report.asleepMinutes.map { HealthReport.duration($0) } ?? "—", rec?.sleep, Health.teal)
                    factor("Night stress", report.overnightStress.map { "\(Int($0.rounded()))" + ($0 < 30 ? " · relaxed" : "") } ?? "—", rec?.stress, Health.amber)
                }
            }
            Text("Resting heart rate against your 14-day baseline (40%), time asleep against your plan (40%) and overnight stress (20%).").font(.system(size: 11)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
        }.healthCard()
    }
    private func factor(_ label: String, _ value: String, _ part: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(label).foregroundStyle(Ink.muted); Spacer(); Text(value) }.font(.system(size: 11))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat((part ?? 0) / 100))
                }
            }.frame(height: 4)
        }
    }
}
/// Heart rate and stress through the day in 10-minute averages, with sleep and workouts shaded.
private struct DayTrace: View {
    var report: HealthReport
    var isToday: Bool
    var body: some View {
        let r = report, start = Date(timeIntervalSince1970: r.dayStart), end = Date(timeIntervalSince1970: r.dayStart + 86_400)
        let sleep = r.night.map { (max($0.start, r.dayStart - 86_400), $0.end) }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Mono("YOUR DAY · HOUR BY HOUR")
                    Text(caption).font(.system(size: 16, weight: .medium))
                }
                Spacer()
                HStack(spacing: 14) { legend("Heart rate", Ink.accent, line: true); legend("Stress", Health.amber, line: true); legend("Asleep", Ink.accent.opacity(0.25)); legend("Workout", Health.amber.opacity(0.3)) }
            }
            if r.heart.isEmpty && r.stress.isEmpty {
                Text("No heart-rate or stress readings for this date. Sign in to the Mi Fitness cloud under Sources for all-day readings.").font(.system(size: 12)).foregroundStyle(Ink.muted).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart {
                    if let sleep { RectangleMark(xStart: .value("From", Date(timeIntervalSince1970: max(sleep.0, r.dayStart))), xEnd: .value("To", Date(timeIntervalSince1970: sleep.1))).foregroundStyle(Ink.accent.opacity(0.10)) }
                    ForEach(Array(r.workouts.enumerated()), id: \.offset) { _, w in
                        RectangleMark(xStart: .value("From", Date(timeIntervalSince1970: w.start)), xEnd: .value("To", Date(timeIntervalSince1970: w.end))).foregroundStyle(Health.amber.opacity(0.16))
                    }
                    ForEach(r.heart, id: \.time) { p in
                        AreaMark(x: .value("Time", Date(timeIntervalSince1970: p.time)), yStart: .value("Floor", 40), yEnd: .value("BPM", p.value)).foregroundStyle(Ink.accent.opacity(0.08)).interpolationMethod(.monotone)
                        LineMark(x: .value("Time", Date(timeIntervalSince1970: p.time)), y: .value("BPM", p.value)).foregroundStyle(Ink.accent).interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 1.8))
                    }
                    if isToday { RuleMark(x: .value("Now", Date())).foregroundStyle(Color.white.opacity(0.45)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4])) }
                }
                .chartXScale(domain: start...end).chartYScale(domain: 40...max(130, (r.heart.map(\.value).max() ?? 0) + 5))
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in AxisGridLine().foregroundStyle(Color.white.opacity(0.06)); AxisValueLabel().font(.system(size: 9, design: .monospaced)) } }
                .frame(height: 190)
                Chart {
                    if let sleep { RectangleMark(xStart: .value("From", Date(timeIntervalSince1970: max(sleep.0, r.dayStart))), xEnd: .value("To", Date(timeIntervalSince1970: sleep.1))).foregroundStyle(Ink.accent.opacity(0.10)) }
                    ForEach(r.stress, id: \.time) { p in
                        LineMark(x: .value("Time", Date(timeIntervalSince1970: p.time)), y: .value("Stress", p.value)).foregroundStyle(Health.amber).interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 1.6))
                    }
                    if isToday { RuleMark(x: .value("Now", Date())).foregroundStyle(Color.white.opacity(0.45)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4])) }
                }
                .chartXScale(domain: start...end).chartYScale(domain: 0...100)
                .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { value in AxisGridLine().foregroundStyle(Color.white.opacity(0.05)); AxisValueLabel { if let d = value.as(Date.self) { Text(hourLabel(d)).font(.system(size: 9, design: .monospaced)) } } } }
                .chartYAxis { AxisMarks(position: .leading, values: [0, 50, 100]) { _ in AxisGridLine().foregroundStyle(Color.white.opacity(0.05)); AxisValueLabel().font(.system(size: 9, design: .monospaced)) } }
                .frame(height: 80)
                Text("Top: heart rate in bpm. Bottom: stress 0–100. 10-minute averages; gaps are not filled in.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            }
        }.healthCard()
    }
    private var caption: String {
        let r = report
        var parts: [String] = []
        if let n = r.night, let low = r.heart.filter({ $0.time >= n.start && $0.time <= n.end }).min(by: { $0.value < $1.value }) {
            parts.append("Heart rate fell to \(Int(low.value.rounded())) by \(HealthReport.clock(Int((low.time - r.dayStart) / 60)))")
        }
        if let peak = r.heart.max(by: { $0.value < $1.value }), let high = r.heartHigh {
            let inWorkout = r.workouts.first { peak.time >= $0.start - 600 && peak.time <= $0.end + 600 }
            parts.append("peaked at \(Int(high))" + (inWorkout.map { " in your \(HealthReport.clock(Int(($0.start - r.dayStart) / 60))) workout" } ?? ""))
        }
        return parts.isEmpty ? "Heart rate and stress through the day" : parts.joined(separator: " and ")
    }
    private func hourLabel(_ d: Date) -> String {
        let h = Calendar.current.component(.hour, from: d)
        return h == 0 ? "12 AM" : h == 12 ? "12 PM" : h < 12 ? "\(h) AM" : "\(h - 12) PM"
    }
    private func legend(_ text: String, _ color: Color, line: Bool = false) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: line ? 1 : 2).fill(color).frame(width: line ? 14 : 12, height: line ? 2 : 10)
            Text(text).font(.system(size: 11)).foregroundStyle(Ink.muted)
        }
    }
}
/// Last night's stages as a hypnogram, with totals.
private struct SleepCard: View {
    var report: HealthReport
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let night = report.night {
                let stages = (night.stages ?? []).sorted { $0.start < $1.start }
                let span = max(night.end - night.start, 60)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Mono("LAST NIGHT · \(clock(night.start)) → \(clock(night.end))".uppercased())
                        Text(title(stages)).font(.system(size: 16, weight: .medium))
                    }
                    Spacer()
                }
                if stages.isEmpty {
                    Text("Mi Fitness sent this night without stages.").font(.system(size: 12)).foregroundStyle(Ink.muted)
                } else {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 0) { ForEach(["AWAKE", "REM", "LIGHT", "DEEP"], id: \.self) { Mono($0).frame(height: 34, alignment: .center) } }.frame(width: 50, alignment: .leading)
                        GeometryReader { geo in
                            ForEach(Array(stages.enumerated()), id: \.offset) { _, s in
                                RoundedRectangle(cornerRadius: 3).fill(color(s.kind))
                                    .frame(width: max(2, geo.size.width * CGFloat((s.end - s.start) / span)), height: 26)
                                    .offset(x: geo.size.width * CGFloat((s.start - night.start) / span), y: CGFloat(s.kind.depth) * 34 + 4)
                            }
                        }.frame(height: 136)
                    }.accessibilityElement(children: .ignore).accessibilityLabel("Sleep stages through the night")
                }
                let asleep = report.asleepMinutes ?? 0
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    total("Deep", .deep, "target 15–25%", asleep)
                    total("REM", .rem, "target 20–25%", asleep)
                    total("Light", .light, nil, asleep)
                    total("Awake", .awake, nil, asleep)
                }
            } else {
                Mono("LAST NIGHT")
                Text("No sleep recorded for this date. Sleep comes from Mi Fitness through Ascend Bridge.").font(.system(size: 12)).foregroundStyle(Ink.muted)
            }
        }.healthCard()
    }
    private func clock(_ t: Double) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: t)); return HealthReport.clock((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }
    private func title(_ stages: [SleepStage]) -> String {
        let cycles = zip(stages, stages.dropFirst()).filter { $0.kind != .rem && $1.kind == .rem }.count + (stages.first?.kind == .rem ? 1 : 0)
        let deep = report.stageMinutes[.deep] ?? 0, firstHalf = stages.filter { $0.kind == .deep && $0.start < (report.night!.start + report.night!.end) / 2 }.map(\.minutes).reduce(0, +)
        var text = "\(HealthReport.duration(report.asleepMinutes ?? 0)) asleep"
        if cycles > 0 { text += ", \(cycles) REM \(cycles == 1 ? "cycle" : "cycles")" }
        if deep > 0 && firstHalf / deep > 0.6 { text += ", deep sleep front-loaded" }
        return text
    }
    private func color(_ kind: SleepStageKind) -> Color {
        switch kind.depth { case 3: Ink.accent; case 2: Health.light; case 1: Health.teal; default: Health.amber }
    }
    private func total(_ label: String, _ kind: SleepStageKind, _ target: String?, _ asleep: Double) -> some View {
        let minutes = report.stageMinutes.filter { kind == .awake ? $0.key.depth == 0 : $0.key == kind || (kind == .light && $0.key == .asleep) }.values.reduce(0, +)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(color(kind)).frame(width: 8, height: 8); Text(label).font(.system(size: 11)).foregroundStyle(Ink.muted) }
            Text(HealthReport.duration(minutes)).font(.system(size: 18, weight: .semibold))
            Text(kind == .awake ? " " : "\(asleep > 0 ? Int(minutes / asleep * 100) : 0)%" + (target.map { " · \($0)" } ?? "")).font(.system(size: 10, design: .monospaced)).foregroundStyle(Ink.muted)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.06)))
    }
}
private struct PlanCard: View {
    var report: HealthReport
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("AGAINST YOUR PLAN").padding(.bottom, 12)
            if let night = report.night, let bed = report.planBed, let wake = report.planWake, let drift = report.drift {
                row("Bedtime", clock(night.start), HealthReport.clock(bed), drift.bedtime, late: true)
                row("Wake", clock(night.end), HealthReport.clock(wake), drift.wake, late: false)
                let short = report.planMinutes - (report.asleepMinutes ?? 0)
                line("Time asleep", HealthReport.duration(report.asleepMinutes ?? 0), HealthReport.duration(report.planMinutes),
                     short > 5 ? "\(HealthReport.duration(short)) short" : "on plan", short > 15 ? Health.amber : Ink.muted)
            } else {
                Text(report.night == nil ? "No sleep recorded for this date." : "Set your routine's bedtime and wake to compare each night with your plan.").font(.system(size: 12)).foregroundStyle(Ink.muted)
            }
        }.healthCard()
    }
    private func clock(_ t: Double) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: t)); return HealthReport.clock((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }
    private func row(_ label: String, _ actual: String, _ plan: String, _ offset: Int, late: Bool) -> some View {
        let text = abs(offset) <= 15 ? "on time" : "\(HealthReport.duration(Double(abs(offset)))) \(offset > 0 ? "late" : "early")"
        return line(label, actual, plan, text, abs(offset) > 15 && (offset > 0) == late ? Health.amber : Ink.muted)
    }
    private func line(_ label: String, _ actual: String, _ plan: String, _ delta: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(label).foregroundStyle(Ink.muted); Spacer(); Text(delta).foregroundStyle(color) }.font(.system(size: 12))
            HStack(alignment: .firstTextBaseline, spacing: 8) { Text(actual).font(.system(size: 24, weight: .semibold)); Mono("PLAN \(plan.uppercased())") }
        }.padding(.vertical, 12).overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }
}
private struct TrendCard: View {
    var title: String, summary: String, values: [Double?], labels: [String], range: ClosedRange<Double>, target: Double?, color: Color
    var flag: (Double) -> Bool
    var note: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) { Text(title).font(.system(size: 14, weight: .medium)); Spacer(); Mono(summary) }
            GeometryReader { geo in
                let height = geo.size.height
                ZStack(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                            let last = i == values.count - 1
                            let fill: Color = v.map { flag($0) ? Health.amber : color } ?? .clear
                            RoundedRectangle(cornerRadius: 3).fill(fill.opacity(last ? 1 : 0.45))
                                .frame(height: v.map { max(3, height * CGFloat(min(1, max(0, ($0 - range.lowerBound) / (range.upperBound - range.lowerBound))))) } ?? 3)
                                .frame(maxWidth: .infinity)
                                .background(alignment: .bottom) { if v == nil { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 2) } }
                        }
                    }
                    if let target {
                        Rectangle().fill(Color.white.opacity(0.35)).frame(height: 1).mask(HStack(spacing: 3) { ForEach(0..<80, id: \.self) { _ in Rectangle().frame(width: 4) } })
                            .offset(y: -height * CGFloat(min(1, max(0, (target - range.lowerBound) / (range.upperBound - range.lowerBound)))))
                    }
                }
            }.frame(height: 100)
            HStack(spacing: 8) { ForEach(Array(labels.enumerated()), id: \.offset) { _, l in Text(l).font(.system(size: 9, design: .monospaced)).foregroundStyle(Ink.muted).frame(maxWidth: .infinity) } }
            Text(note).font(.system(size: 11)).foregroundStyle(Ink.muted).lineLimit(2).frame(minHeight: 30, alignment: .top)
        }.healthCard(padding: 18)
    }
}
