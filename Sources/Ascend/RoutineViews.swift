import SwiftUI
import AscendCore

struct RoutineDial: View {
    let store: TrackerStore
    let now: Date
    var compact = false
    private var routine: RoutinePreferences { store.document.routine }
    private func color(_ phase: RoutinePhase) -> Color {
        switch phase {
        case .sleep: Ink.accent.opacity(0.25)
        case .morning: Ink.accent.opacity(0.55)
        case .daytime: Ink.accent
        case .windDown: Ink.lamp
        }
    }
    var body: some View {
        ZStack {
            Canvas { context, size in
                let side = min(size.width, size.height), center = CGPoint(x: size.width / 2, y: size.height / 2), radius = side * (compact ? 0.43 : 0.38)
                func point(_ minute: Double, _ distance: CGFloat) -> CGPoint {
                    let angle = minute / 1440 * .pi * 2 - .pi / 2
                    return CGPoint(x: center.x + CGFloat(cos(angle)) * distance, y: center.y + CGFloat(sin(angle)) * distance)
                }
                let bounds = Array(Set([0, routine.wakeMinute, routine.morningEndMinute, routine.windDownMinute, routine.bedMinute, 1440])).sorted()
                for i in 0..<(bounds.count - 1) {
                    let start = Double(bounds[i]) + 5, end = Double(bounds[i + 1]) - 5
                    guard start < end else { continue }
                    var path = Path(); path.move(to: point(start, radius))
                    for minute in stride(from: start, through: end, by: 2) { path.addLine(to: point(minute, radius)) }
                    path.addLine(to: point(end, radius))
                    context.stroke(path, with: .color(color(routine.phase(at: (bounds[i] + bounds[i + 1]) / 2))), style: StrokeStyle(lineWidth: compact ? 5 : 10, lineCap: .round))
                }
                if !compact {
                    for hour in 0..<24 {
                        var tick = Path(); tick.move(to: point(Double(hour * 60), radius - 16)); tick.addLine(to: point(Double(hour * 60), radius - (hour % 6 == 0 ? 25 : 21)))
                        context.stroke(tick, with: .color(Ink.line), lineWidth: 1)
                    }
                    for hour in [0,6,12,18] {
                        context.draw(Text(String(format: "%02d", hour)).font(.bt(size: 11, design: .monospaced)).foregroundColor(Ink.muted), at: point(Double(hour * 60), radius + 23))
                    }
                    for event in store.engine.routineEvents(on: store.engine.key(now)) where event.habitID != nil {
                        let p = point(Double(store.engine.minute(event.date)), radius)
                        context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(.white))
                    }
                }
                let minute = Double(store.engine.minute(now))
                var hand = Path(); hand.move(to: point(minute, radius * (compact ? 0.66 : 0.56))); hand.addLine(to: point(minute, radius - 10))
                context.stroke(hand, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: compact ? 1.5 : 2, lineCap: .round))
            }
            VStack(spacing: compact ? 0 : 7) {
                if !compact { Kicker(routine.configured ? "Right now" : "Example routine") }
                Text(timeText(now, engine: store.engine)).font(.bt(size: compact ? 18 : 38, weight: .medium, design: .rounded)).monospacedDigit().tracking(compact ? -0.7 : -1.8)
                if !compact { Text(routine.configured ? routine.phase(at: store.engine.minute(now)).rawValue : "Set your own times").font(.bt(size: 12)).foregroundStyle(Ink.muted) }
            }
        }.aspectRatio(1, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("24-hour routine clock")
            .accessibilityValue("\(timeText(now, engine: store.engine)), \(routine.configured ? routine.phase(at: store.engine.minute(now)).rawValue : "example schedule; configure your times")")
    }
}
struct RoutineEditor: View {
    @ObservedObject var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State private var wake: Date
    @State private var bed: Date
    @State private var morning: Int
    @State private var windDown: Int
    init(store: TrackerStore) {
        self.store = store; let r = store.document.routine
        _wake = State(initialValue: store.engine.time(on: store.today, minute: r.wakeMinute)!)
        _bed = State(initialValue: store.engine.time(on: store.today, minute: r.bedMinute)!)
        _morning = State(initialValue: r.morningMinutes); _windDown = State(initialValue: r.windDownMinutes)
    }
    private var preferences: RoutinePreferences {
        var r = RoutinePreferences(); r.configured = true; r.wakeMinute = store.engine.minute(wake); r.bedMinute = store.engine.minute(bed); r.morningMinutes = morning; r.windDownMinutes = windDown; return r
    }
    private var validation: String? { do { try preferences.validate(); return nil } catch { return error.localizedDescription } }
    private var dirty: Bool { let r = store.document.routine; return r.wakeMinute != preferences.wakeMinute || r.bedMinute != preferences.bedMinute || r.morningMinutes != morning || r.windDownMinutes != windDown }
    var body: some View {
        EditorShell(title: "Your daily rhythm", dirty: dirty) {
            Text("Set your usual times. Wind-down is calculated before bedtime, including across midnight.").font(.bt(size: 12)).foregroundStyle(Ink.muted)
            HStack(spacing: 24) {
                FieldGroup(label: "Wake up") { DatePicker("Wake up", selection: $wake, displayedComponents: .hourAndMinute).labelsHidden() }
                FieldGroup(label: "Go to bed") { DatePicker("Go to bed", selection: $bed, displayedComponents: .hourAndMinute).labelsHidden() }
            }
            FieldGroup(label: "Morning window") { Stepper("\(morning) minutes after waking", value: $morning, in: 15...360, step: 15).font(.bt(size: 12)) }
            FieldGroup(label: "Wind-down") { Stepper("\(windDown) minutes before bed", value: $windDown, in: 15...360, step: 15).font(.bt(size: 12)) }
            if let validation { Text(validation).font(.bt(size: 12)).foregroundStyle(.orange) }
            else { Text("Wind down at \(HealthReport.clock(preferences.windDownMinute)). Your sleep window is \(Double(1440 - preferences.awakeMinutes) / 60, specifier: "%.1f") hours.").font(.bt(size: 13)).foregroundStyle(Ink.accent) }
            Text("Clock time zone: \(store.document.timeZoneID). These settings shape the clock; sleep duration is still logged separately.").font(.bt(size: 11)).foregroundStyle(Ink.muted)
            SaveError(store: store)
        } actions: { HStack { Spacer(); PrimaryButton(label: "Save routine") { if store.saveRoutine(preferences) { dismiss() } }.disabled(validation != nil) } }
    }
}
