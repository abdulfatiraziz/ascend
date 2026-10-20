import SwiftUI
import Charts
import AscendCore

struct PatternsView: View {
    @ObservedObject var store: TrackerStore
    @Binding var editor: Editor?
    @State private var selectedDay: String
    @State private var trends = false
    @State private var range = 28
    init(store: TrackerStore, editor: Binding<Editor?>) {
        self.store = store; _editor = editor; _selectedDay = State(initialValue: store.today)
    }
    var body: some View {
        let analysis = PatternsEngine(document: store.document, today: store.today)
        let selected = analysis.day(selectedDay)
        let rows = analysis.closedDays(range)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Kicker("Your observations + Mi Fitness")
                    Text("Sleep, caffeine and how your day felt. Private on this Mac.").font(.system(size: 12)).foregroundStyle(Ink.muted)
                }
                Spacer()
                Button(trends ? "Today’s check-in" : "Daily check-in") { editor = .observation(trends ? store.today : selectedDay) }.buttonStyle(.plain).font(.system(size: 12)).padding(9).background(Ink.panel, in: RoundedRectangle(cornerRadius: 7))
                PrimaryButton(label: "Log caffeine") { editor = .caffeine(nil, trends ? store.today : selectedDay) }
            }
            HStack {
                Picker("Patterns view", selection: $trends) { Text("Daily story").tag(false); Text("Trends & patterns").tag(true) }.labelsHidden().pickerStyle(.segmented).frame(width: 255)
                Spacer()
                if trends {
                    Picker("Completed days", selection: $range) { Text("14 days").tag(14); Text("28 days").tag(28); Text("84 days").tag(84) }.labelsHidden().frame(width: 120)
                } else {
                    Button { selectedDay = store.engine.adding(-1, to: selectedDay) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).accessibilityLabel("Previous story day")
                    DatePicker("Story date", selection: Binding(get: { store.engine.date(selectedDay) ?? Date() }, set: { selectedDay = store.engine.key($0) }), in: ...Date(), displayedComponents: .date).labelsHidden().fixedSize()
                    Button { selectedDay = store.engine.adding(1, to: selectedDay) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).disabled(selectedDay >= store.today).accessibilityLabel("Next story day")
                    Button("Today") { selectedDay = store.today }.buttonStyle(.plain).font(.system(size: 12))
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if trends { trendContent(rows, analysis: analysis) }
                    else { dailyContent(selected, analysis: analysis) }
                }.padding(.bottom, 8)
            }
        }
        .onChange(of: store.today) { old, new in if selectedDay == old { selectedDay = new } }
    }
    private func dailyContent(_ day: PatternDay, analysis: PatternsEngine) -> some View {
        let knownAmounts = day.caffeine.allSatisfy { $0.milligrams != nil }
        let amount = day.caffeine.compactMap(\.milligrams).reduce(0, +)
        let caffeineText = day.caffeine.isEmpty ? (day.caffeineComplete ? "0 mg" : "—") : knownAmounts ? "\(amount.formatted(.number.precision(.fractionLength(0...1)))) mg" : "\(day.caffeine.count) entries"
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                summary("Sleep window", value: day.night.map { "\($0.window.hours.formatted(.number.precision(.fractionLength(1)))) h" } ?? "—", detail: day.night.map { "\(timeText($0.window.bedtime, engine: store.engine)) → \(timeText($0.window.wakeTime, engine: store.engine)) · \($0.manuallyCorrected ? "manual" : "Mi Fitness")" } ?? "Add a window or sync your watch")
                summary("Caffeine logged", value: caffeineText, detail: day.caffeineComplete ? (knownAmounts ? "Log marked complete" : "Complete log · some amounts unknown") : "Log not marked complete")
                summary("Overall energy", value: day.energy.map { "\($0)/5" } ?? "—", detail: "\(day.urgesComplete ? "\(day.urgeCount) urges · log complete" : "\(day.urgeCount) urge entries · log incomplete")")
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Kicker("The day's timeline"); Spacer(); Text(store.document.timeZoneID).font(.system(size: 10)).foregroundStyle(Ink.muted) }
                    let events = analysis.timeline(on: selectedDay)
                    if events.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Start connecting the dots.").font(.system(size: 19, weight: .medium))
                            Text("Log caffeine when it happens, rate your overall energy, and add a sleep window if your watch hasn't shared one yet.").font(.system(size: 12)).foregroundStyle(Ink.muted)
                        }.padding(.vertical, 28)
                    }
                    ForEach(events) { event in
                        if event.caffeineID != nil || event.urgeID != nil || event.id.hasPrefix("sleep-") {
                            Button { open(event) } label: { timelineRow(event) }.buttonStyle(.plain)
                        } else { timelineRow(event) }
                        Line()
                    }
                    Text("Sleep belongs to its wake date. The main watch session is used; naps are not added to the overnight window.").font(.system(size: 10)).foregroundStyle(Ink.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).panel(padding: 16)
                context(day).frame(width: 250)
            }
            Text("These observations do not change habit check-ins. Missing entries stay unknown until you mark a log complete. Notes and wellbeing records stay outside AI context.").font(.system(size: 11)).foregroundStyle(Ink.muted)
        }
    }
    private func summary(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Kicker(title)
            Text(value).font(.system(size: 28, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.system(size: 10)).foregroundStyle(Ink.muted).lineLimit(3).frame(minHeight: 28, alignment: .top)
        }.frame(maxWidth: .infinity, alignment: .leading).panel(padding: 15)
    }
    private func context(_ day: PatternDay) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker("Your context")
            contextRow("Mood", value: day.mood.map { "\($0)/5" } ?? "Not rated")
            contextRow("Stress", value: day.stress.map { "\($0)/5" } ?? "Not rated")
            if let hours = day.night?.window.asleepHours { contextRow(day.night?.manuallyCorrected == true ? "Asleep (logged)" : "Reported asleep", value: "\(hours.formatted(.number.precision(.fractionLength(1)))) h") }
            Line()
            Text(day.caffeineComplete ? "✓ Caffeine log complete" : "○ Caffeine log incomplete").font(.system(size: 11)).foregroundStyle(Ink.muted)
            Text(day.urgesComplete ? "✓ Urge log complete" : "○ Urge log incomplete").font(.system(size: 11)).foregroundStyle(Ink.muted)
            if let note = store.document.wellbeing.observation(on: selectedDay)?.note, !note.isEmpty { Text(note).font(.system(size: 12)).textSelection(.enabled) }
            Button("Edit this day's check-in") { editor = .observation(selectedDay) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Ink.accent)
        }.frame(maxWidth: .infinity, alignment: .leading).panel(padding: 16)
    }
    private func contextRow(_ title: String, value: String) -> some View { HStack { Text(title).foregroundStyle(Ink.muted); Spacer(); Text(value) }.font(.system(size: 12)) }
    private func timelineRow(_ e: PatternTimelineEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) { Text(timeText(e.start, engine: store.engine)).monospacedDigit(); Text(dateText(store.engine.key(e.start), engine: store.engine, pattern: "d MMM")).font(.system(size: 9)).foregroundStyle(Ink.muted) }.font(.system(size: 12)).frame(width: 50, alignment: .leading)
            Image(systemName: e.symbol).foregroundStyle(Ink.accent).frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(e.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                Text([e.end.map { "Until \(timeText($0, engine: store.engine))" }, e.detail.isEmpty ? nil : e.detail].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(Ink.muted)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
    private func open(_ event: PatternTimelineEvent) {
        if let id = event.caffeineID, let entry = store.document.wellbeing.caffeine.first(where: { $0.id == id }) { editor = .caffeine(entry, selectedDay) }
        else if let id = event.urgeID { editor = .urge(id) }
        else { editor = .observation(selectedDay) }
    }
    private func trendContent(_ rows: [PatternDay], analysis: PatternsEngine) -> some View {
        let nights = rows.compactMap(\.night)
        let average = nights.isEmpty ? nil : nights.map { $0.window.hours }.reduce(0, +) / Double(nights.count)
        let regularity = analysis.clockRegularity(nights.map { $0.window.bedtime })
        return VStack(alignment: .leading, spacing: 18) {
            Text("Last \(range) completed dates · \(dateText(rows.first?.day ?? store.today, engine: store.engine, pattern: "d MMM"))–\(dateText(rows.last?.day ?? store.today, engine: store.engine, pattern: "d MMM"))").font(.system(size: 12)).foregroundStyle(Ink.muted)
            HStack(alignment: .top, spacing: 12) {
                summary("Sleep window average", value: average.map { "\($0.formatted(.number.precision(.fractionLength(1)))) h" } ?? "—", detail: "\(nights.count) nights with a main sleep window")
                summary("Bedtime variation", value: regularity.map { "\(Int($0.rounded())) min" } ?? "—", detail: "Typical difference from your usual bedtime")
                summary("Energy coverage", value: "\(rows.filter { $0.energy != nil }.count)/\(range)", detail: "Completed dates with an overall energy rating")
            }
            trendChart(rows, title: "Sleep window", unit: "h", color: Ink.accent) { $0.night?.window.hours }
            trendChart(rows, title: "Overall energy", unit: "/5", color: .mint, upperBound: 5) { $0.energy.map(Double.init) }
            trendChart(rows, title: "Caffeine", unit: "mg", color: .orange) { $0.caffeineMg }
            VStack(alignment: .leading, spacing: 8) {
                Text("Patterns to explore").font(.system(size: 20, weight: .semibold))
                Text("Comparisons need 14 paired dates and at least 5 in each group. Today stays out while it is still in progress. Group averages describe associations; they don't establish causes.").font(.system(size: 12)).foregroundStyle(Ink.muted)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                ForEach(analysis.comparisons(days: range)) { comparison in comparisonCard(comparison) }
            }
            Text("Sleep windows include time awake. The 7-hour grouping and six-hour caffeine window are comparison settings, not personalized health targets. Habit comparisons use the current cycle's scoring rules; unlogged scheduled habits count as missed. Caffeine timing uses logged events even when amounts are unknown, while dose charts require known amounts and complete logs.").font(.system(size: 11)).foregroundStyle(Ink.muted)
        }
    }
    private func trendChart(_ rows: [PatternDay], title: String, unit: String, color: Color, upperBound: Double? = nil, value: (PatternDay) -> Double?) -> some View {
        let points = rows.compactMap { d -> TrendPoint? in guard let v = value(d), let date = store.engine.date(d.day) else { return nil }; return TrendPoint(id: d.day, date: date, value: v) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack { Text(title).font(.system(size: 14, weight: .medium)); Spacer(); Text("\(points.count) of \(range) dates · \(unit)").font(.system(size: 10)).foregroundStyle(Ink.muted) }
            if points.isEmpty { Text("No completed dates with this data yet.").font(.system(size: 12)).foregroundStyle(Ink.muted).frame(maxWidth: .infinity, minHeight: 70) }
            else {
                Chart(points) { p in PointMark(x: .value("Date", p.date), y: .value(title, p.value)).symbolSize(30).foregroundStyle(color) }
                    .chartYScale(domain: 0...(upperBound ?? max(1, (points.map(\.value).max() ?? 1) * 1.15)))
                    .chartXScale(domain: (store.engine.date(rows.first!.day)!)...(store.engine.date(store.engine.adding(1, to: rows.last!.day))!)).frame(height: 100)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).panel(padding: 16)
    }
    private func comparisonCard(_ c: PatternComparison) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(c.title).font(.system(size: 14, weight: .medium))
            Text(c.ready ? "\(c.pairedDays) paired dates · exploratory comparison" : "Collecting context · \(c.pairedDays)/14 paired dates").font(.system(size: 10)).foregroundStyle(c.ready ? Ink.accent : Ink.muted)
            Text(c.metric).font(.system(size: 10)).foregroundStyle(Ink.muted)
            HStack(alignment: .top, spacing: 12) {
                group(c.first, comparison: c)
                group(c.second, comparison: c)
            }
            Text(c.explanation).font(.system(size: 10)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            if !c.ready { Text("Needs 14 paired dates, with at least 5 per group.").font(.system(size: 10)).foregroundStyle(Ink.muted) }
        }.frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading).panel(padding: 16)
    }
    private func group(_ g: PatternGroup, comparison: PatternComparison) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(g.label).font(.system(size: 11)).foregroundStyle(Ink.muted)
            Text(comparison.ready ? (g.average.map { "\($0.formatted(.number.precision(.fractionLength(1))))\(comparison.unit)" } ?? "—") : "—").font(.system(size: 24, weight: .medium))
            Text("n = \(g.count) dates").font(.system(size: 10)).foregroundStyle(Ink.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct TrendPoint: Identifiable { let id: String; let date: Date; let value: Double }
