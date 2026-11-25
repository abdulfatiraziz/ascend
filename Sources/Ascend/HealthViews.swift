import SwiftUI
import Charts
import AscendCore

// MARK: - Pieces

enum Health {
    static let amber = Ink.watch
    static let teal = Color(hex: 0x7FC4B8)
    static let green = Ink.onTrack
    static let light = Ink.accent.opacity(0.55)
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
    var body: some View { Text(prefix + text).font(.bt(size: 10.5, design: .monospaced)).tracking(1.4).foregroundStyle(color) }
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
                Text(value ?? "—").font(.bt(size: 30, weight: .semibold)).tracking(-0.5).lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(.bt(size: 10, design: .monospaced)).foregroundStyle(Ink.muted)
            }
            Sparkline(values: series, color: color).frame(height: 26)
            Text(note).font(.bt(size: 11)).foregroundStyle(Ink.muted).lineLimit(2).frame(minHeight: 28, alignment: .top)
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
                        Text(rec.map { "\($0.score)" } ?? "—").font(.bt(size: 38, weight: .semibold))
                        Text("/ 100").font(.bt(size: 9, design: .monospaced)).foregroundStyle(Ink.muted)
                    }
                }.frame(width: 128, height: 128).accessibilityElement(children: .ignore).accessibilityLabel(rec.map { "Recovery \($0.score) out of 100" } ?? "Recovery not available")
                VStack(alignment: .leading, spacing: 11) {
                    factor("Resting HR", report.restingHeartRate.map { r in "\(Int(r))" + (report.restingBaseline.map { " · \(Int($0.rounded()))" } ?? "") } ?? "—", rec?.resting, Ink.accent)
                    factor("Sleep", report.asleepMinutes.map { HealthReport.duration($0) } ?? "—", rec?.sleep, Health.teal)
                    factor("Night stress", report.overnightStress.map { "\(Int($0.rounded()))" + ($0 < 30 ? " · relaxed" : "") } ?? "—", rec?.stress, Health.amber)
                }
            }
            Text("Resting heart rate against your 14-day baseline (40%), time asleep against your plan (40%) and overnight stress (20%).").font(.bt(size: 11)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
        }.healthCard()
    }
    private func factor(_ label: String, _ value: String, _ part: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(label).foregroundStyle(Ink.muted); Spacer(); Text(value) }.font(.bt(size: 11))
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
                    Text(caption).font(.bt(size: 16, weight: .medium))
                }
                Spacer()
                HStack(spacing: 14) { legend("Heart rate", Ink.accent, line: true); legend("Stress", Health.amber, line: true); legend("Asleep", Ink.accent.opacity(0.25)); legend("Workout", Health.amber.opacity(0.3)) }
            }
            if r.heart.isEmpty && r.stress.isEmpty {
                Text("No heart-rate or stress readings for this date. Sign in to the Mi Fitness cloud under Sources for all-day readings.").font(.bt(size: 12)).foregroundStyle(Ink.muted).frame(maxWidth: .infinity, minHeight: 120)
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
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in AxisGridLine().foregroundStyle(Color.white.opacity(0.06)); AxisValueLabel().font(.bt(size: 9, design: .monospaced)) } }
                .frame(height: 190)
                Chart {
                    if let sleep { RectangleMark(xStart: .value("From", Date(timeIntervalSince1970: max(sleep.0, r.dayStart))), xEnd: .value("To", Date(timeIntervalSince1970: sleep.1))).foregroundStyle(Ink.accent.opacity(0.10)) }
                    ForEach(r.stress, id: \.time) { p in
                        LineMark(x: .value("Time", Date(timeIntervalSince1970: p.time)), y: .value("Stress", p.value)).foregroundStyle(Health.amber).interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 1.6))
                    }
                    if isToday { RuleMark(x: .value("Now", Date())).foregroundStyle(Color.white.opacity(0.45)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4])) }
                }
                .chartXScale(domain: start...end).chartYScale(domain: 0...100)
                .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { value in AxisGridLine().foregroundStyle(Color.white.opacity(0.05)); AxisValueLabel { if let d = value.as(Date.self) { Text(hourLabel(d)).font(.bt(size: 9, design: .monospaced)) } } } }
                .chartYAxis { AxisMarks(position: .leading, values: [0, 50, 100]) { _ in AxisGridLine().foregroundStyle(Color.white.opacity(0.05)); AxisValueLabel().font(.bt(size: 9, design: .monospaced)) } }
                .frame(height: 80)
                Text("Top: heart rate in bpm. Bottom: stress 0–100. 10-minute averages; gaps are not filled in.").font(.bt(size: 11)).foregroundStyle(Ink.muted)
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
            Text(text).font(.bt(size: 11)).foregroundStyle(Ink.muted)
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
                        Text(title(stages)).font(.bt(size: 16, weight: .medium))
                    }
                    Spacer()
                }
                if stages.isEmpty {
                    Text("Mi Fitness sent this night without stages.").font(.bt(size: 12)).foregroundStyle(Ink.muted)
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
                Text("No sleep recorded for this date. Sleep comes from Mi Fitness through Cipher Bridge.").font(.bt(size: 12)).foregroundStyle(Ink.muted)
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
            HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(color(kind)).frame(width: 8, height: 8); Text(label).font(.bt(size: 11)).foregroundStyle(Ink.muted) }
            Text(HealthReport.duration(minutes)).font(.bt(size: 18, weight: .semibold))
            Text(kind == .awake ? " " : "\(asleep > 0 ? Int(minutes / asleep * 100) : 0)%" + (target.map { " · \($0)" } ?? "")).font(.bt(size: 10, design: .monospaced)).foregroundStyle(Ink.muted)
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
                Text(report.night == nil ? "No sleep recorded for this date." : "Set your routine's bedtime and wake to compare each night with your plan.").font(.bt(size: 12)).foregroundStyle(Ink.muted)
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
            HStack { Text(label).foregroundStyle(Ink.muted); Spacer(); Text(delta).foregroundStyle(color) }.font(.bt(size: 12))
            HStack(alignment: .firstTextBaseline, spacing: 8) { Text(actual).font(.bt(size: 24, weight: .semibold)); Mono("PLAN \(plan.uppercased())") }
        }.padding(.vertical, 12).overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }
}
private struct TrendCard: View {
    var title: String, summary: String, values: [Double?], labels: [String], range: ClosedRange<Double>, target: Double?, color: Color
    var flag: (Double) -> Bool
    var note: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) { Text(title).font(.bt(size: 14, weight: .medium)); Spacer(); Mono(summary) }
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
            HStack(spacing: 8) { ForEach(Array(labels.enumerated()), id: \.offset) { _, l in Text(l).font(.bt(size: 9, design: .monospaced)).foregroundStyle(Ink.muted).frame(maxWidth: .infinity) } }
            Text(note).font(.bt(size: 11)).foregroundStyle(Ink.muted).lineLimit(2).frame(minHeight: 30, alignment: .top)
        }.healthCard(padding: 18)
    }
}
