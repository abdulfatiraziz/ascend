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
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("Tonight: lights out by \(HealthReport.clock(store.document.routine.bedMinute)).").font(.bt(size: 25)).foregroundStyle(Ink.ivory)
                        facts.ledeDetail.font(.bt(size: 12)).foregroundStyle(Ink.muted)
                        Spacer()
                    }
                    HStack(alignment: .top, spacing: 22) {
                        VStack(spacing: 10) {
                            HStack { CardTitle("The day on one dial"); Spacer(); Button("Edit times") { editor = .routine }.font(.bt(size: 11)).buttonStyle(.borderless) }
                            WatchDial(facts: facts).frame(width: 380, height: 380)
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
    var body: some View {
        let cal = facts.engine.calendar, routine = facts.doc.routine, plan = facts.plan
        let lastNight = facts.lastNight, naps = facts.naps, bedOffset = facts.bedOffset
        let minutesToBed = facts.minutesToBed, momentName = facts.momentName, nowClock = facts.clockMinute
        return Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let side = min(size.width, size.height)
            let k = side / 400
            let R = 150 * k
            func pt(_ m: Double, _ r: CGFloat) -> CGPoint {
                let a = m / 1440 * .pi * 2 - .pi / 2
                return CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
            }
            func arc(_ m1: Double, _ m2: Double, _ r: CGFloat) -> Path {
                var end = m2; if end < m1 { end += 1440 }
                var p = Path()
                p.addArc(center: c, radius: r, startAngle: .radians(m1 / 1440 * .pi * 2 - .pi / 2), endAngle: .radians(end / 1440 * .pi * 2 - .pi / 2), clockwise: false)
                return p
            }
            func circle(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
            // case, bezel, face
            ctx.stroke(circle(192 * k), with: .linearGradient(Gradient(colors: [Ink.lamp, Ink.goldDim, Ink.accent]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: size.height)), lineWidth: 3 * k)
            ctx.fill(circle(186 * k), with: .color(Color(hex: 0x0A231B)))
            ctx.fill(circle(166 * k), with: .radialGradient(Gradient(colors: [Color(hex: 0x15402F), Color(hex: 0x0A261D)]), center: CGPoint(x: c.x, y: c.y - 30 * k), startRadius: 0, endRadius: 190 * k))
            ctx.stroke(circle(166 * k), with: .color(Ink.accent.opacity(0.35)), lineWidth: 1)
            for i in 0..<96 {
                let m = Double(i * 15), major = i % 4 == 0
                var t = Path(); t.move(to: pt(m, 183 * k)); t.addLine(to: pt(m, (major ? 175 : 179) * k))
                ctx.stroke(t, with: .color(major ? Ink.accent.opacity(0.7) : Ink.ivory.opacity(0.18)), lineWidth: major ? 1.4 : 1)
            }
            let r = routine
            // sleep plan: recessed band
            ctx.stroke(arc(Double(r.bedMinute), Double(r.wakeMinute), R), with: .color(Color(hex: 0x04110D)), lineWidth: 16 * k)
            ctx.stroke(arc(Double(r.bedMinute), Double(r.wakeMinute), R + 8.5 * k), with: .color(Ink.goldDim.opacity(0.6)), lineWidth: 1)
            ctx.stroke(arc(Double(r.bedMinute), Double(r.wakeMinute), R - 8.5 * k), with: .color(Ink.goldDim.opacity(0.6)), lineWidth: 1)
            // awake track and black tie hours
            ctx.stroke(arc(Double(r.wakeMinute), Double(r.windDownMinute), R), with: .color(Ink.accent.opacity(0.22)), lineWidth: 2)
            ctx.stroke(arc(Double(r.windDownMinute), Double(r.bedMinute), R), with: .color(Ink.lamp.opacity(0.95)), style: StrokeStyle(lineWidth: 6 * k, lineCap: .round))
            // last night and naps, from the watch
            func clockMinute(_ t: Double) -> Double {
                let d = Date(timeIntervalSince1970: t)
                return Double(cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d))
            }
            if let n = lastNight {
                ctx.stroke(arc(clockMinute(n.start), clockMinute(n.end), R - 22 * k), with: .color(Ink.offTrack), style: StrokeStyle(lineWidth: 5 * k, lineCap: .round))
            }
            for nap in naps {
                ctx.stroke(arc(clockMinute(nap.start), clockMinute(nap.end), R - 22 * k), with: .color(Ink.offTrack.opacity(0.5)), style: StrokeStyle(lineWidth: 5 * k, lineCap: .round))
            }
            // hour batons and 12-hour labels
            for h in 0..<24 where h % 6 != 0 {
                var t = Path(); t.move(to: pt(Double(h * 60), R - 34 * k)); t.addLine(to: pt(Double(h * 60), R - 42 * k))
                ctx.stroke(t, with: .color(Ink.ivory.opacity(0.45)), style: StrokeStyle(lineWidth: h % 3 == 0 ? 2.2 : 1.2, lineCap: .round))
            }
            for (m, label) in [(0, "12 AM"), (360, "6 AM"), (720, "12 PM"), (1080, "6 PM")] {
                ctx.draw(Text(label).font(.bt(size: 10.5 * k, design: .monospaced)).foregroundColor(Ink.accent), at: pt(Double(m), R - 46 * k))
            }
            // plan dots on the bezel: meals ivory, meds gold
            for e in plan {
                let p = pt(Double(e.minute % 1440), R + 18 * k)
                switch e.kind {
                case .meal: ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.6 * k, y: p.y - 3.6 * k, width: 7.2 * k, height: 7.2 * k)), with: .color(e.done ? Ink.onTrack : Ink.ivory))
                case .meds:
                    var pill = ctx; pill.translateBy(x: p.x, y: p.y); pill.rotate(by: .degrees(Double(e.minute % 1440) / 1440 * 360))
                    pill.fill(Path(roundedRect: CGRect(x: -5 * k, y: -2.6 * k, width: 10 * k, height: 5.2 * k), cornerRadius: 2.6 * k), with: .color(e.done ? Ink.onTrack : Ink.accent))
                default: break
                }
            }
            // sub-dials
            func sub(_ x: CGFloat, _ title: String, _ value: String, _ frac: Double, _ color: Color) {
                let sc = CGPoint(x: c.x + x * k, y: c.y + 6 * k), sr = 27 * k
                ctx.fill(Path(ellipseIn: CGRect(x: sc.x - sr, y: sc.y - sr, width: sr * 2, height: sr * 2)), with: .color(Color(hex: 0x0A231B)))
                ctx.stroke(Path(ellipseIn: CGRect(x: sc.x - sr, y: sc.y - sr, width: sr * 2, height: sr * 2)), with: .color(Ink.accent.opacity(0.45)), lineWidth: 1)
                for i in 0..<12 {
                    let a = Double(i) / 12 * .pi * 2
                    var t = Path(); t.move(to: CGPoint(x: sc.x + CGFloat(cos(a)) * 24 * k, y: sc.y + CGFloat(sin(a)) * 24 * k)); t.addLine(to: CGPoint(x: sc.x + CGFloat(cos(a)) * 21 * k, y: sc.y + CGFloat(sin(a)) * 21 * k))
                    ctx.stroke(t, with: .color(Ink.ivory.opacity(0.25)), lineWidth: 1)
                }
                let a = frac * .pi * 2 - .pi / 2
                var h = Path(); h.move(to: sc); h.addLine(to: CGPoint(x: sc.x + CGFloat(cos(a)) * 18 * k, y: sc.y + CGFloat(sin(a)) * 18 * k))
                ctx.stroke(h, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: sc.x - 2.2, y: sc.y - 2.2, width: 4.4, height: 4.4)), with: .color(color))
                ctx.draw(Text(title).font(.bt(size: 8.5 * k, design: .monospaced)).tracking(1.4).foregroundColor(Ink.muted), at: CGPoint(x: sc.x, y: sc.y + 40 * k))
                ctx.draw(Text(value).font(.bt(size: 12 * k)).foregroundColor(color), at: CGPoint(x: sc.x, y: sc.y + 53 * k))
            }
            if let n = lastNight {
                let m = clockMinute(n.start)
                sub(-50, "ASLEEP", HealthReport.clock(Int(m)), m.truncatingRemainder(dividingBy: 720) / 720, n.minute > bedOffset ? Ink.offTrack : Ink.onTrack)
            } else { sub(-50, "ASLEEP", "—", 0, Ink.muted) }
            let left = minutesToBed
            sub(50, "LIGHTS OUT", left == 0 ? "now" : RoutineFacts.span(left), Double(left % 720) / 720, Ink.lamp)
            // centre
            ctx.draw(Text(momentName.uppercased()).font(.bt(size: 9 * k, design: .monospaced)).tracking(2.5).foregroundColor(Ink.muted), at: CGPoint(x: c.x, y: c.y - 74 * k))
            ctx.draw(Text(HealthReport.clock(nowClock)).font(.bt(size: 38 * k)).foregroundColor(Ink.ivory), at: CGPoint(x: c.x, y: c.y - 42 * k))
            // the hand: a pointer on the bezel, never across the centre
            let now = Double(nowClock)
            var hand = Path(); hand.move(to: pt(now, R - 30 * k)); hand.addLine(to: pt(now, R + 12 * k))
            ctx.stroke(hand, with: .color(Ink.lamp), style: StrokeStyle(lineWidth: 3 * k, lineCap: .round))
            let l = pt(now, R - 34 * k)
            ctx.fill(Path(ellipseIn: CGRect(x: l.x - 4.5 * k, y: l.y - 4.5 * k, width: 9 * k, height: 9 * k)), with: .color(Color(hex: 0x0A231B)))
            ctx.stroke(Path(ellipseIn: CGRect(x: l.x - 4.5 * k, y: l.y - 4.5 * k, width: 9 * k, height: 9 * k)), with: .color(Ink.lamp), lineWidth: 1.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Routine dial")
        .accessibilityValue("\(HealthReport.clock(facts.clockMinute)), \(facts.momentName)")
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
