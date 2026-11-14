import SwiftUI
import AscendCore

/// Routine: the day on one dial, the night ahead, and the last 7 nights. Read only; taps live on Today.
struct RoutineView: View {
    @ObservedObject var store: TrackerStore
    @Binding var editor: Editor?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let facts = RoutineFacts(store: store, now: timeline.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 14) { Text("Tonight: lights out by \(HealthReport.clock(store.document.routine.bedMinute)).").font(.bt(size: 25)).foregroundStyle(Ink.ivory).fixedSize(); facts.ledeDetail.font(.bt(size: 12)).foregroundStyle(Ink.muted).fixedSize(); Spacer(minLength: 0) }
                        VStack(alignment: .leading, spacing: 4) { Text("Tonight: lights out by \(HealthReport.clock(store.document.routine.bedMinute)).").font(.bt(size: 25)).foregroundStyle(Ink.ivory); facts.ledeDetail.font(.bt(size: 12)).foregroundStyle(Ink.muted) }
                    }
                    HStack(alignment: .top, spacing: 22) {
                        VStack(spacing: 10) {
                            HStack { CardTitle("The day on one dial"); Spacer(); Button("Edit times") { editor = .routine }.font(.bt(size: 11)).buttonStyle(.borderless) }
                            WatchDial(facts: facts).frame(width: 392, height: 392)
                            DialLegend()
                        }
                        .padding(22).frame(width: 440)
                        .background(RadialGradient(colors: [Color(hex: 0x12392C), Ink.panel, Ink.background], center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 520), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ink.line))
                        VStack(spacing: 16) {
                            NightAheadCard(facts: facts)
                            NightsCard(facts: facts)
                        }.frame(maxWidth: .infinity)
                    }
                }.padding(.bottom, 8)
            }.scrollIndicators(.never)
        }
    }
}

/// Everything the Routine tab shows, worked out once per refresh.
@MainActor struct RoutineFacts {
    let store: TrackerStore
    let now: Date
    var engine: TrackerEngine { store.engine }
    var doc: TrackerDocument { store.document }
    var day: String { store.today }
    var clockMinute: Int { engine.calendar.component(.hour, from: now) * 60 + engine.calendar.component(.minute, from: now) }
    var nowMinute: Int { TrackerDocument.eveningMinute(clockMinute, wake: doc.routine.wakeMinute) }
    var plan: [PlanEvent] { doc.dayPlan(on: day, engine: engine) }
    var ahead: [PlanEvent] { doc.planAhead(on: day, now: nowMinute, engine: engine) }
    var lastNight: NightOnset? { doc.onset(endingOn: day, engine: engine) }
    /// Naps today: sleep ending today that started after noon.
    var naps: [HealthRecord] {
        doc.health.sleepSessions(on: day, engine: engine).filter { engine.calendar.component(.hour, from: Date(timeIntervalSince1970: $0.start)) >= 12 }
    }
    var nights: [(day: String, onset: NightOnset?)] { (0..<7).reversed().map { i in let d = engine.adding(-i, to: day); return (d, doc.onset(endingOn: d, engine: engine)) } }
    var bedOffset: Int { let b = doc.routine.bedMinute; return b >= 12 * 60 ? b - 1440 : b }
    var onTime: Int { nights.compactMap(\.onset).filter { $0.minute <= bedOffset }.count }
    var known: Int { nights.compactMap(\.onset).count }
    var average: Int? { let o = nights.compactMap(\.onset); return o.isEmpty ? nil : o.map(\.minute).reduce(0, +) / o.count }
    var minutesToBed: Int { max(0, TrackerDocument.eveningMinute(doc.routine.bedMinute, wake: doc.routine.wakeMinute) - nowMinute) }
    /// What the dial's centre calls this moment: the meal window you're in, black tie hours, or the routine phase.
    var momentName: String {
        if let e = plan.first(where: { $0.kind == .windDown }), nowMinute >= e.minute, nowMinute < (e.endMinute ?? e.minute) { return "Black tie hours" }
        if let m = plan.first(where: { $0.kind == .meal && nowMinute >= $0.minute && nowMinute < ($0.endMinute ?? $0.minute) }) { return "\(m.title) window" }
        return doc.routine.phase(at: clockMinute).rawValue
    }
    var ledeDetail: Text {
        guard let n = lastNight else { return Text("No sleep from the watch for last night yet") }
        let late = n.minute > bedOffset
        return Text("Last night ") + Text(HealthReport.clock(n.minute)).foregroundColor(late ? Ink.offTrack : Ink.onTrack)
            + Text(" · \(onTime) of \(known) nights on time this week")
    }
    /// Things earlier today that didn't happen, as plain facts. Meals aren't listed: they're logged only when you want.
    var earlier: [(text: String, warn: Bool)] {
        var out: [(String, Bool)] = []
        for e in plan where e.kind == .meds && !e.done && e.minute < nowMinute { out.append(("\(e.title) not tapped", true)) }
        if let gym = doc.gymHabit, engine.isDue(gym, on: day) {
            out.append((engine.completed(gym, on: day) ? "Gym · done" : "Gym day · no workout yet", false))
        }
        let urges = doc.urgeLogs.filter { engine.key($0.timestamp) == day }
        if !urges.isEmpty {
            let spots = Set(urges.compactMap(\.spot)).sorted()
            out.append(("\(urges.count) urge\(urges.count == 1 ? "" : "s")\(spots.isEmpty ? "" : " · " + spots.joined(separator: ", "))", false))
        }
        return out
    }
    static func span(_ minutes: Int) -> String {
        minutes < 60 ? "in \(minutes) min" : "in \(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }
}

// MARK: - The watch

struct WatchDial: View {
    let facts: RoutineFacts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownAt = Date()
    private let intro = 1.4
    var body: some View {
        let cal = facts.engine.calendar, routine = facts.doc.routine, plan = facts.plan
        let lastNight = facts.lastNight, naps = facts.naps, bedOffset = facts.bedOffset
        let minutesToBed = facts.minutesToBed, momentName = facts.momentName, nowClock = facts.clockMinute
        let windSpan = max(1, routine.windDownMinutes)
        let skip = reduceMotion, start = shownAt, intro = intro
        return TimelineView(.animation(minimumInterval: 1 / 60, paused: skip || Date().timeIntervalSince(start) > intro + 0.2)) { tl in
            let raw = skip ? 1 : min(1, max(0, tl.date.timeIntervalSince(start) / intro))
            let p = 1 - pow(1 - raw, 3)  // ease out
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let k = min(size.width, size.height) / 400
                func ang(_ m: Double) -> Double { m / 1440 * .pi * 2 - .pi / 2 }
                func pt(_ m: Double, _ r: CGFloat) -> CGPoint { CGPoint(x: c.x + CGFloat(cos(ang(m))) * r * k, y: c.y + CGFloat(sin(ang(m))) * r * k) }
                func ring(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r * k, y: c.y - r * k, width: r * 2 * k, height: r * 2 * k)) }
                func arc(_ m1: Double, _ m2: Double, _ r: CGFloat, grow: Bool = true) -> Path {
                    var span = m2 - m1; if span < 0 { span += 1440 }
                    var path = Path()
                    path.addArc(center: c, radius: r * k, startAngle: .radians(ang(m1)), endAngle: .radians(ang(m1 + span * (grow ? p : 1))), clockwise: false)
                    return path
                }
                func clockMin(_ t: Double) -> Double {
                    let d = Date(timeIntervalSince1970: t); return Double(cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d))
                }
                let fade = GraphicsContext.Shading.color(.clear)
                _ = fade

                // Case and bezel
                ctx.fill(ring(197), with: .linearGradient(Gradient(colors: [Ink.lamp, Ink.goldDim, Color(hex: 0x5E4D2E), Ink.accent]),
                                                         startPoint: CGPoint(x: c.x - 197 * k, y: c.y - 197 * k), endPoint: CGPoint(x: c.x + 197 * k, y: c.y + 197 * k)))
                ctx.fill(ring(193), with: .color(Color(hex: 0x081E17)))
                ctx.stroke(ring(168.5), with: .color(Ink.accent.opacity(0.35)), lineWidth: 0.8)
                // Face
                ctx.fill(ring(168), with: .radialGradient(Gradient(colors: [Color(hex: 0x17442F), Color(hex: 0x0D2D22), Color(hex: 0x0A251C)]),
                                                           center: CGPoint(x: c.x, y: c.y - 40 * k), startRadius: 0, endRadius: 200 * k))

                // Bezel ticks: hours gold, quarters faint dots
                for i in 0..<96 {
                    let m = Double(i * 15)
                    if i % 4 == 0 {
                        let h = i / 4, major = h % 6 == 0
                        if major { continue }
                        var t = Path(); t.move(to: pt(m, 189)); t.addLine(to: pt(m, h % 3 == 0 ? 179 : 183))
                        ctx.stroke(t, with: .color(Ink.accent.opacity(h % 3 == 0 ? 0.9 : 0.6)), style: StrokeStyle(lineWidth: (h % 3 == 0 ? 1.8 : 1.1) * k, lineCap: .round))
                    } else {
                        let q = pt(m, 186)
                        ctx.fill(Path(ellipseIn: CGRect(x: q.x - 0.7 * k, y: q.y - 0.7 * k, width: 1.4 * k, height: 1.4 * k)), with: .color(Ink.ivory.opacity(0.22)))
                    }
                }
                for (m, label) in [(0, "12 AM"), (360, "6 AM"), (720, "12 PM"), (1080, "6 PM")] {
                    ctx.draw(Text(label).font(.bt(size: 9.5 * k, weight: .medium, design: .monospaced)).tracking(0.6).foregroundColor(Ink.accent), at: pt(Double(m), 176.5))
                }

                // Event ring: meals and meds sit on their own hairline
                ctx.stroke(ring(146), with: .color(Ink.ivory.opacity(0.08)), lineWidth: 0.8)
                for e in plan where e.kind == .meal || e.kind == .meds {
                    let m = Double(e.minute % 1440), q = pt(m, 146)
                    var g = ctx; g.opacity = p
                    if e.kind == .meal {
                        g.fill(Path(ellipseIn: CGRect(x: q.x - 3.4 * k, y: q.y - 3.4 * k, width: 6.8 * k, height: 6.8 * k)), with: .color(e.done ? Ink.onTrack : Ink.ivory))
                    } else {
                        g.translateBy(x: q.x, y: q.y); g.rotate(by: .radians(ang(m)))
                        g.fill(Path(roundedRect: CGRect(x: -2.6 * k, y: -5.2 * k, width: 5.2 * k, height: 10.4 * k), cornerRadius: 2.6 * k), with: .color(e.done ? Ink.onTrack : Ink.accent))
                    }
                }

                // Plan channel: sleep plan and black tie hours
                let channel: CGFloat = 126, cw: CGFloat = 13
                ctx.stroke(ring(channel), with: .color(Color.black.opacity(0.22)), lineWidth: cw * k)
                ctx.stroke(arc(Double(routine.bedMinute), Double(routine.wakeMinute), channel), with: .color(Color(hex: 0x03100C)), lineWidth: cw * k)
                ctx.stroke(arc(Double(routine.bedMinute), Double(routine.wakeMinute), channel + cw / 2), with: .color(Ink.goldDim.opacity(0.55)), lineWidth: 0.8)
                ctx.stroke(arc(Double(routine.bedMinute), Double(routine.wakeMinute), channel - cw / 2), with: .color(Ink.goldDim.opacity(0.55)), lineWidth: 0.8)
                ctx.stroke(arc(Double(routine.windDownMinute), Double(routine.bedMinute), channel),
                           with: .linearGradient(Gradient(colors: [Ink.accent, Ink.lamp]), startPoint: pt(Double(routine.windDownMinute), channel), endPoint: pt(Double(routine.bedMinute), channel)),
                           lineWidth: (cw - 4) * k)

                // Sleep track: last night and naps, from the watch
                let track: CGFloat = 108
                ctx.stroke(ring(track), with: .color(Ink.ivory.opacity(0.06)), lineWidth: 4 * k)
                if let n = lastNight {
                    ctx.stroke(arc(clockMin(n.start), clockMin(n.end), track), with: .color(Ink.offTrack), style: StrokeStyle(lineWidth: 4 * k, lineCap: .round))
                }
                for nap in naps {
                    ctx.stroke(arc(clockMin(nap.start), clockMin(nap.end), track), with: .color(Ink.offTrack.opacity(0.5)), style: StrokeStyle(lineWidth: 4 * k, lineCap: .round))
                }

                // Now: a GMT-style pointer on the bezel, a hairline across the tracks
                let nowM = Double(nowClock) * p
                var line = Path(); line.move(to: pt(nowM, 150)); line.addLine(to: pt(nowM, 101))
                ctx.stroke(line, with: .color(Ink.lamp.opacity(0.85)), style: StrokeStyle(lineWidth: 1.2 * k, lineCap: .round))
                var tri = ctx; let tip = pt(nowM, 153)
                tri.translateBy(x: tip.x, y: tip.y); tri.rotate(by: .radians(ang(nowM) + .pi / 2))
                var arrow = Path(); arrow.move(to: .zero); arrow.addLine(to: CGPoint(x: -5.5 * k, y: -11 * k)); arrow.addLine(to: CGPoint(x: 5.5 * k, y: -11 * k)); arrow.closeSubpath()
                tri.fill(arrow, with: .color(Ink.lamp))
                let dot = pt(nowM, 101)
                ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 2.4 * k, y: dot.y - 2.4 * k, width: 4.8 * k, height: 4.8 * k)), with: .color(Ink.lamp))

                // Centre: moment, time, two sub-dials
                ctx.draw(Text(momentName.uppercased()).font(.bt(size: 8.5 * k, design: .monospaced)).tracking(2.4).foregroundColor(Ink.muted), at: CGPoint(x: c.x, y: c.y - 58 * k))
                ctx.draw(Text(HealthReport.clock(nowClock)).font(.bt(size: 31 * k)).foregroundColor(Ink.ivory), at: CGPoint(x: c.x, y: c.y - 30 * k))

                func sub(_ x: CGFloat, _ title: String, _ value: String, _ color: Color, hand: Double?, fill: Double?) {
                    let sc = CGPoint(x: c.x + x * k, y: c.y + 24 * k), sr: CGFloat = 21 * k
                    let rect = CGRect(x: sc.x - sr, y: sc.y - sr, width: sr * 2, height: sr * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(Color(hex: 0x081E17)))
                    ctx.stroke(Path(ellipseIn: rect), with: .color(Ink.accent.opacity(0.4)), lineWidth: 0.8)
                    for i in 0..<12 {
                        let a = Double(i) / 12 * .pi * 2 - .pi / 2, long = i % 3 == 0
                        var t = Path()
                        t.move(to: CGPoint(x: sc.x + CGFloat(cos(a)) * (sr - 2 * k), y: sc.y + CGFloat(sin(a)) * (sr - 2 * k)))
                        t.addLine(to: CGPoint(x: sc.x + CGFloat(cos(a)) * (sr - (long ? 6 : 4) * k), y: sc.y + CGFloat(sin(a)) * (sr - (long ? 6 : 4) * k)))
                        ctx.stroke(t, with: .color(Ink.ivory.opacity(long ? 0.4 : 0.2)), lineWidth: 0.8)
                    }
                    if let f = fill, f > 0 {
                        var a = Path(); a.addArc(center: sc, radius: sr - 9 * k, startAngle: .radians(-.pi / 2), endAngle: .radians(-.pi / 2 + f * p * .pi * 2), clockwise: false)
                        ctx.stroke(a, with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: 3 * k, lineCap: .round))
                    }
                    if let h = hand {
                        let a = h * p * .pi * 2 - .pi / 2
                        var l = Path(); l.move(to: sc); l.addLine(to: CGPoint(x: sc.x + CGFloat(cos(a)) * (sr - 6 * k), y: sc.y + CGFloat(sin(a)) * (sr - 6 * k)))
                        ctx.stroke(l, with: .color(color), style: StrokeStyle(lineWidth: 1.4 * k, lineCap: .round))
                    }
                    ctx.fill(Path(ellipseIn: CGRect(x: sc.x - 2 * k, y: sc.y - 2 * k, width: 4 * k, height: 4 * k)), with: .color(hand == nil ? Ink.muted : color))
                    ctx.draw(Text(title).font(.bt(size: 7.5 * k, design: .monospaced)).tracking(1.6).foregroundColor(Ink.muted), at: CGPoint(x: sc.x, y: sc.y + 32 * k))
                    ctx.draw(Text(value).font(.bt(size: 11 * k, weight: .medium)).foregroundColor(color), at: CGPoint(x: sc.x, y: sc.y + 45 * k))
                }
                if let n = lastNight {
                    let m = clockMin(n.start)
                    sub(-36, "ASLEEP", HealthReport.clock(Int(m)), n.minute > bedOffset ? Ink.offTrack : Ink.onTrack, hand: m.truncatingRemainder(dividingBy: 720) / 720, fill: nil)
                } else {
                    sub(-36, "ASLEEP", "No data", Ink.muted, hand: nil, fill: nil)
                }
                // Lights out: the gold arc is the black tie window still to go
                let left = minutesToBed
                let frac = left > windSpan ? nil : Double(left) / Double(windSpan)
                sub(36, "LIGHTS OUT", left == 0 ? "now" : RoutineFacts.span(left), Ink.lamp, hand: left > windSpan ? Double(left % 720) / 720 : frac, fill: frac ?? Double(min(left, 720)) / 720)
            }
        }
        .onAppear { shownAt = Date() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Routine dial")
        .accessibilityValue("\(HealthReport.clock(nowClock)), \(momentName)")
    }
}

struct DialLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            item({ RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x04110D)).overlay(RoundedRectangle(cornerRadius: 2).stroke(Ink.goldDim)).frame(width: 16, height: 4) }, text: "Sleep plan")
            item({ Capsule().fill(Ink.lamp).frame(width: 16, height: 4) }, text: "Black tie hours")
            item({ Capsule().fill(Ink.offTrack).frame(width: 16, height: 4) }, text: "Last night")
            item({ Circle().fill(Ink.ivory).frame(width: 7, height: 7) }, text: "Meals")
            item({ Capsule().fill(Ink.accent).frame(width: 10, height: 5) }, text: "Meds")
        }.font(.bt(size: 11.5)).foregroundStyle(Ink.muted)
    }
    private func item<S: View>(@ViewBuilder _ swatch: () -> S, text: String) -> some View { HStack(spacing: 6) { swatch(); Text(text) } }
}

// MARK: - The night ahead

struct NightAheadCard: View {
    let facts: RoutineFacts
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) { CardTitle("The night ahead"); Spacer(); Text("From your plan · nothing to tap").font(.bt(size: 12)).foregroundStyle(Ink.muted) }
                .padding(.bottom, 10)
            HStack(spacing: 10) {
                Text(HealthReport.clock(facts.clockMinute)).font(.bt(size: 12, design: .monospaced)).foregroundStyle(Ink.accent).frame(width: 78, alignment: .trailing)
                Circle().fill(Ink.accent).frame(width: 9, height: 9).background(Circle().fill(Ink.accent.opacity(0.18)).frame(width: 17, height: 17)).frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOW").font(.bt(size: 10.5, design: .monospaced)).tracking(2.5).foregroundStyle(Ink.accent)
                    LinearGradient(colors: [Ink.accent, Ink.accent.opacity(0)], startPoint: .leading, endPoint: .trailing).frame(height: 1)
                }
            }.padding(.bottom, 6)
            let ahead = facts.ahead
            if ahead.isEmpty {
                Text("Nothing left on the plan tonight.").font(.bt(size: 13)).foregroundStyle(Ink.muted).padding(.vertical, 12)
            }
            ForEach(Array(ahead.enumerated()), id: \.element.id) { i, e in
                if i > 0 { Line() }
                row(e)
            }
            let earlier = facts.earlier
            if !earlier.isEmpty {
                Line().padding(.top, 6)
                HStack(spacing: 8) {
                    Text("EARLIER TODAY").font(.bt(size: 10, design: .monospaced)).tracking(2).foregroundStyle(Ink.muted)
                    ForEach(earlier, id: \.text) { item in
                        Text(item.text).font(.bt(size: 11.5)).lineLimit(1).padding(.horizontal, 9).padding(.vertical, 4)
                            .foregroundStyle(item.warn ? Ink.watch : Ink.muted)
                            .overlay(Capsule().stroke(item.warn ? Ink.watch.opacity(0.35) : Ink.line))
                    }
                    Spacer(minLength: 0)
                }.padding(.top, 12)
            }
        }.panel(padding: 22)
    }
    private func row(_ e: PlanEvent) -> some View {
        let current = e.kind == .meal && facts.nowMinute >= e.minute && facts.nowMinute < (e.endMinute ?? e.minute)
        let status: String = e.done ? (e.kind == .meds ? "TAKEN" : "LOGGED") : current ? "OPEN" : RoutineFacts.span(e.minute - facts.nowMinute)
        let detail = current ? "Window till \(HealthReport.clock(e.endMinute ?? e.minute)) · \(e.detail)" : e.detail
        return HStack(spacing: 10) {
            Text(HealthReport.clock(e.minute)).font(.bt(size: 12, design: .monospaced)).foregroundStyle(Ink.muted).frame(width: 78, alignment: .trailing)
            marker(e).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title).font(e.kind == .windDown ? .bt(size: 19, weight: .semibold) : .bt(size: 14.5, weight: .medium)).foregroundStyle(e.done ? Ink.onTrack : Ink.ivory)
                Text(detail).font(.bt(size: 11.5)).foregroundStyle(Ink.muted).lineLimit(1)
            }
            Spacer()
            Text(status).font(.bt(size: 11, design: .monospaced)).foregroundStyle(e.done ? Ink.onTrack : current ? Ink.accent : Ink.muted)
        }
        .padding(.vertical, 8).padding(.horizontal, current ? 6 : 0)
        .background(LinearGradient(colors: [Ink.accent.opacity(current ? 0.08 : 0), .clear], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 10))
    }
    @ViewBuilder private func marker(_ e: PlanEvent) -> some View {
        switch e.kind {
        case .windDown: Circle().fill(Ink.lamp).frame(width: 9, height: 9)
        case .bed: Circle().fill(Ink.ivory).frame(width: 9, height: 9)
        default:
            if e.done { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Ink.onTrack) }
            else { Circle().stroke(e.kind == .meds ? Ink.accent : Ink.goldDim, lineWidth: 1.5).frame(width: 9, height: 9) }
        }
    }
}

// MARK: - Last 7 nights

struct NightsCard: View {
    let facts: RoutineFacts
    /// Chart spans 11 pm (-60) to 5 am (300).
    private let top = -60, bottom = 300
    var body: some View {
        let nights = facts.nights
        let bed = facts.bedOffset
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) { CardTitle("Last 7 nights · asleep at"); Spacer(); Text("From the watch").font(.bt(size: 12)).foregroundStyle(Ink.muted) }
                .padding(.bottom, 14)
            GeometryReader { g in
                let h = g.size.height, w = g.size.width - 64
                let y: (Int) -> CGFloat = { CGFloat(min(max($0, top), bottom) - top) / CGFloat(bottom - top) * h }
                ZStack(alignment: .topLeading) {
                    ForEach([-60, 60, 180, 300], id: \.self) { m in
                        Text(HealthReport.clock(m).replacingOccurrences(of: ":00", with: "").uppercased()).font(.bt(size: 10, design: .monospaced)).foregroundStyle(Ink.muted)
                            .frame(width: 56, alignment: .trailing).position(x: 28, y: y(m))
                    }
                    Path { p in p.move(to: CGPoint(x: 64, y: y(bed))); p.addLine(to: CGPoint(x: g.size.width, y: y(bed))) }
                        .stroke(Ink.accent.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    ForEach(Array(nights.enumerated()), id: \.offset) { i, n in
                        let x = 64 + w * (CGFloat(i) + 0.5) / 7
                        Rectangle().fill(Ink.line).frame(width: 1, height: h).position(x: 64 + w * CGFloat(i) / 7, y: h / 2)
                        if let o = n.onset {
                            let ok = o.minute <= bed
                            Circle().fill(ok ? Ink.onTrack : Ink.offTrack).frame(width: 12, height: 12)
                                .background(Circle().fill((ok ? Ink.onTrack : Ink.offTrack).opacity(0.15)).frame(width: 20, height: 20))
                                .position(x: x, y: y(o.minute))
                            Text(HealthReport.clock(o.minute).replacingOccurrences(of: " am", with: "").replacingOccurrences(of: " pm", with: ""))
                                .font(.bt(size: 10, design: .monospaced)).foregroundStyle(Ink.ivory).position(x: x, y: y(o.minute) - 17)
                        } else {
                            Text("—").font(.bt(size: 11)).foregroundStyle(Ink.muted).position(x: x, y: h / 2)
                        }
                    }
                }
            }.frame(height: 96).padding(.top, 8)
            HStack(spacing: 0) {
                Color.clear.frame(width: 64)
                ForEach(Array(nights.enumerated()), id: \.offset) { _, n in
                    Text(dateText(n.day, engine: facts.engine, pattern: "EEE")).font(.bt(size: 10, design: .monospaced)).foregroundStyle(Ink.muted).frame(maxWidth: .infinity)
                }
            }.padding(.top, 10)
            Line().padding(.top, 12)
            HStack {
                if let avg = facts.average {
                    let late = avg - bed
                    (Text("Average ") + Text(HealthReport.clock(avg)).foregroundColor(Ink.ivory) + Text(late > 0 ? " · \(late / 60) h \(String(format: "%02d", late % 60)) late" : " · on time"))
                } else { Text("No nights from the watch yet") }
                Spacer()
                if let best = nights.compactMap(\.onset).min(by: { $0.minute < $1.minute }) {
                    Text("Best ") + Text(HealthReport.clock(best.minute)).foregroundColor(Ink.ivory) + Text(" on \(dateText(best.day, engine: facts.engine, pattern: "EEE"))")
                }
            }.font(.bt(size: 12)).foregroundStyle(Ink.muted).padding(.top, 12)
        }.panel(padding: 22)
    }
}
