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
        case .windDown: Color(red: 0.84, green: 0.77, blue: 1)
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
                        context.draw(Text(String(format: "%02d", hour)).font(.system(size: 11, design: .monospaced)).foregroundColor(Ink.muted), at: point(Double(hour * 60), radius + 23))
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
                Text(timeText(now, engine: store.engine)).font(.system(size: compact ? 18 : 38, weight: .medium, design: .rounded)).monospacedDigit().tracking(compact ? -0.7 : -1.8)
                if !compact { Text(routine.configured ? routine.phase(at: store.engine.minute(now)).rawValue : "Set your own times").font(.system(size: 12)).foregroundStyle(Ink.muted) }
            }
        }.aspectRatio(1, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("24-hour routine clock")
            .accessibilityValue("\(timeText(now, engine: store.engine)), \(routine.configured ? routine.phase(at: store.engine.minute(now)).rawValue : "example schedule; configure your times")")
    }
}
struct RoutineView: View {
    @ObservedObject var store: TrackerStore
    @Binding var editor: Editor?
    private var timed: [RoutineEvent] { store.engine.routineEvents(on: store.today) }
    private var anytime: [Habit] { store.engine.due(on: store.today, includeMilestones: true).filter { !store.document.routine.configured || $0.latest.scheduledMinute == nil } }
    var body: some View {
        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 24) {
              GeometryReader { layout in
               ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Kicker("Your 24-hour rhythm"); Spacer(); Button("Edit times") { editor = .routine }.font(.system(size: 11)).buttonStyle(.borderless) }
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in RoutineDial(store: store, now: timeline.date) }.frame(width: min(300, max(200, layout.size.height - 225))).frame(maxWidth: .infinity)
                    HStack(spacing: 12) { ForEach(RoutinePhase.allCases, id: \.self) { phase in Text(phase.rawValue).font(.system(size: 10)).foregroundStyle(Ink.muted) } }.frame(maxWidth: .infinity)
                    Line().padding(.vertical, 8)
                    if store.document.routine.configured {
                        Text("Wind-down begins at \(clockTime(store.document.routine.windDownMinute)).").font(.system(size: 14, weight: .medium))
                        Text("Sleep window: \(clockTime(store.document.routine.bedMinute)) → \(clockTime(store.document.routine.wakeMinute)) · \(Double(1440 - store.document.routine.awakeMinutes) / 60, specifier: "%.1f") hours").font(.system(size: 12)).foregroundStyle(Ink.muted)
                    } else {
                        Text("Make the clock yours.").font(.system(size: 18, weight: .medium))
                        Text("The dial shows example windows until you set your wake and bed times. It never logs sleep or completes a habit automatically.").font(.system(size: 12)).foregroundStyle(Ink.muted)
                        PrimaryButton(label: "Set my routine", fullWidth: true) { editor = .routine }
                    }
                    Text("Exact habit times appear as dots. Add them in a habit’s editor. Untimed habits stay in Anytime.").font(.system(size: 11)).foregroundStyle(Ink.muted).padding(.top, 8)
                }.panel().id("routine-top")
               }
              }.frame(maxWidth: 380)
              ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        VStack(alignment: .leading, spacing: 7) {
                            Kicker("Up next")
                            if let next = store.engine.nextRoutineEvent(after: timeline.date) {
                                Text(next.title).font(.system(size: 24, weight: .medium)).tracking(-0.7)
                                Text("\(timeText(next.date, engine: store.engine))\(store.engine.key(next.date) == store.today ? "" : " tomorrow") · \(store.document.timeZoneID)").font(.system(size: 12)).foregroundStyle(Ink.muted)
                            } else { Text("Set times to see your next step.").font(.system(size: 18)).foregroundStyle(Ink.muted) }
                        }
                    }
                    Line()
                    if store.document.restDays.contains(store.today) { Label("Rest day · routine anchors still show", systemImage: "moon.stars").font(.system(size: 12)).foregroundStyle(Ink.accent) }
                    ForEach(timed) { event in
                        HStack(alignment: .top, spacing: 16) {
                            Text(timeText(event.date, engine: store.engine)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Ink.muted).frame(width: 45, alignment: .leading).padding(.top, 14)
                            if let id = event.habitID, let habit = store.document.habits.first(where: { $0.id == id }) {
                                HabitRow(store: store, habit: habit, day: store.today, onLog: { editor = .metric(habit, store.today) }, onEdit: { editor = .habit(habit, nil) })
                            } else {
                                VStack(alignment: .leading, spacing: 5) { Text(event.title).font(.system(size: 13)); Text("Routine window").font(.system(size: 10)).foregroundStyle(Ink.muted); Line().padding(.top, 12) }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 13)
                            }
                        }
                    }
                    Kicker("Anytime · \(anytime.count)").padding(.top, 10)
                    ForEach(anytime) { habit in
                        HabitRow(store: store, habit: habit, day: store.today, onLog: { editor = .metric(habit, store.today) }, onEdit: { editor = .habit(habit, nil) })
                    }
                    if anytime.isEmpty { Text("No untimed tasks today.").font(.system(size: 12)).foregroundStyle(Ink.muted) }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
              }
            }.onChange(of: store.document.routine) { _, _ in proxy.scrollTo("routine-top", anchor: .top) }
        }
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
            Text("Set your usual times. Wind-down is calculated before bedtime, including across midnight.").font(.system(size: 12)).foregroundStyle(Ink.muted)
            HStack(spacing: 24) {
                FieldGroup(label: "Wake up") { DatePicker("Wake up", selection: $wake, displayedComponents: .hourAndMinute).labelsHidden() }
                FieldGroup(label: "Go to bed") { DatePicker("Go to bed", selection: $bed, displayedComponents: .hourAndMinute).labelsHidden() }
            }
            FieldGroup(label: "Morning window") { Stepper("\(morning) minutes after waking", value: $morning, in: 15...360, step: 15).font(.system(size: 12)) }
            FieldGroup(label: "Wind-down") { Stepper("\(windDown) minutes before bed", value: $windDown, in: 15...360, step: 15).font(.system(size: 12)) }
            if let validation { Text(validation).font(.system(size: 12)).foregroundStyle(.orange) }
            else { Text("Wind down at \(clockTime(preferences.windDownMinute)). Your sleep window is \(Double(1440 - preferences.awakeMinutes) / 60, specifier: "%.1f") hours.").font(.system(size: 13)).foregroundStyle(Ink.accent) }
            Text("Clock time zone: \(store.document.timeZoneID). These settings shape the clock; sleep duration is still logged separately.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            SaveError(store: store)
        } actions: { HStack { Spacer(); PrimaryButton(label: "Save routine") { if store.saveRoutine(preferences) { dismiss() } }.disabled(validation != nil) } }
    }
}
