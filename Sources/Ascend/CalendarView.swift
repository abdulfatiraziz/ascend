import SwiftUI
import AscendCore

struct DayActions: View {
    @ObservedObject var store: TrackerStore
    let day: String
    @State private var confirmReset = false
    var body: some View {
        Menu {
            Button(store.document.restDays.contains(day) ? "Resume day" : "Mark as rest day") {
                store.setRestDay(day, rest: !store.document.restDays.contains(day))
            }
            Divider()
            Button("Reset this date…", role: .destructive) { confirmReset = true }
                .disabled(!store.document.checkIns.contains { $0.day == day } && !store.document.restDays.contains(day))
        } label: { Label("Day options", systemImage: "ellipsis.circle") }
        .menuStyle(.borderlessButton).fixedSize().disabled(day > store.today)
        .confirmationDialog("Reset \(dateText(day, engine: store.engine))?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset this date", role: .destructive) { store.resetDay(day) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Clears this date’s check-ins, numeric values and rest marker. Other dates and your plan stay intact. A safety backup and Undo will be available.") }
    }
}

struct CalendarView: View {
    @ObservedObject var store: TrackerStore
    @Binding var day: String
    @Binding var editor: Editor?
    @State private var month: Date
    init(store: TrackerStore, day: Binding<String>, editor: Binding<Editor?>) {
        self.store = store; _day = day; _editor = editor
        _month = State(initialValue: store.engine.date(day.wrappedValue) ?? Date())
    }
    private var engine: TrackerEngine { store.engine }
    private var monthStart: Date { engine.calendar.date(from: engine.calendar.dateComponents([.year, .month], from: month))! }
    private var monthDays: [String] {
        let count = engine.calendar.range(of: .day, in: .month, for: monthStart)!.count
        return (0..<count).map { engine.adding($0, to: engine.key(monthStart)) }
    }
    private var offset: Int { (engine.calendar.component(.weekday, from: monthStart) + 5) % 7 }
    private var rest: Bool { store.document.restDays.contains(day) }
    private var tasks: [Habit] { engine.reviewTasks(on: day) }
    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            ScrollView {
              VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left") }.help("Previous month")
                    Text(dateText(engine.key(month), engine: engine, pattern: "MMMM yyyy")).font(.system(size: 20, weight: .medium)).frame(maxWidth: .infinity)
                    Button { move(1) } label: { Image(systemName: "chevron.right") }.help("Next month")
                }.buttonStyle(.plain)
                HStack { Text("M"); Spacer(); Text("T"); Spacer(); Text("W"); Spacer(); Text("T"); Spacer(); Text("F"); Spacer(); Text("S"); Spacer(); Text("S") }.font(.system(size: 11)).foregroundStyle(Ink.muted).padding(.horizontal, 14)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 7) {
                    ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 57) }
                    ForEach(monthDays, id: \.self) { key in cell(key) }
                }
                HStack(spacing: 14) {
                    Label("Target met", systemImage: "circle.fill").foregroundStyle(Ink.accent)
                    Label("Rest", systemImage: "moon.fill").foregroundStyle(Ink.muted)
                }.font(.system(size: 10))
                Text("Select a date to review or correct its check-ins. Future dates show the plan. All dates use \(store.document.timeZoneID).").font(.system(size: 12)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                Button("Jump to today") { day = store.today; month = engine.date(day)! }.buttonStyle(.borderless)
                if !store.document.previousCycles.isEmpty {
                    Menu("Previous cycles") {
                        ForEach(Array(store.document.previousCycles.enumerated()), id: \.offset) { _, cycle in
                            Button("\(cycle.title) · \(cycle.start) – \(cycle.end)") { day = cycle.start; month = engine.date(day)! }
                        }
                    }.menuStyle(.borderlessButton).fixedSize()
                }
              }.padding(20)
            }.frame(maxWidth: 400, maxHeight: .infinity, alignment: .top).background(Ink.panel, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Kicker(day == store.today ? "Today" : day > store.today ? "Planned · read only" : "History · editable")
                        Text(dateText(day, engine: engine, pattern: "EEEE, d MMM")).font(.system(size: 22, weight: .medium))
                    }
                    Spacer(); DayActions(store: store, day: day)
                }
                let score = engine.score(on: day)
                HStack {
                    Text(rest ? "Rest day" : "\(score.completed) / \(score.scheduled) recurring").font(.system(size: 13))
                    Spacer(); Text(rest ? "☾" : score.percentLabel).foregroundStyle(Ink.accent)
                }
                if rest { Text("Excluded from consistency. Logged values are preserved. Resume this day to edit recurring tasks.").font(.system(size: 12)).foregroundStyle(Ink.muted) }
                Line()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tasks) { habit in
                            HabitRow(store: store, habit: habit, day: day, onLog: { editor = .metric(habit, day) })
                        }
                        if tasks.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "calendar.badge.checkmark").font(.system(size: 26)).foregroundStyle(Ink.muted)
                                Text("No tasks scheduled for this date.")
                                Text("Dates before a habit was created don’t count as missed days.").foregroundStyle(Ink.muted)
                            }.font(.system(size: 12)).frame(maxWidth: .infinity).padding(.vertical, 50)
                        }
                    }
                }
                Text("One-off tasks appear on their due date and stay separate from your recurring score.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
    private func move(_ delta: Int) {
        if let date = engine.calendar.date(byAdding: .month, value: delta, to: monthStart),
           (1900...2200).contains(engine.calendar.component(.year, from: date)) { month = date }
    }
    private func cell(_ key: String) -> some View {
        let score = engine.score(on: key)
        let isRest = store.document.restDays.contains(key)
        let reached = key <= store.today && (score.ratio ?? 0) >= store.document.cycle.target
        return Button { day = key } label: {
            VStack(spacing: 7) {
                Text(String(Int(key.suffix(2))!)).font(.system(size: 13, weight: key == store.today ? .bold : .regular))
                if isRest { Image(systemName: "moon.fill").font(.system(size: 9)) }
                else { Text(score.scheduled == 0 ? "—" : key > store.today ? "\(score.scheduled) due" : "\(score.completed)/\(score.scheduled)").font(.system(size: 8, design: .monospaced)) }
            }.frame(maxWidth: .infinity).frame(height: 57)
                .foregroundStyle(reached ? Ink.accent : key > store.today ? Ink.muted : .white)
                .background(day == key ? Ink.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(day == key ? Ink.accent : key == store.today ? Ink.line : .clear))
        }.buttonStyle(.plain).accessibilityLabel("\(dateText(key, engine: engine)), \(isRest ? "Rest day" : "\(score.completed) of \(score.scheduled)"), \(key > store.today ? "planned" : "editable")")
    }
}
