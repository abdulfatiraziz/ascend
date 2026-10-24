import SwiftUI
import Charts
import AscendCore

struct HealthView: View {
    @ObservedObject var store: TrackerStore
    @State private var day: String
    @State private var stepsHelp = false
    init(store: TrackerStore) { self.store = store; _day = State(initialValue: store.today) }
    private var archive: HealthArchive { store.document.health }
    private var heart: [HealthRecord] { archive.records(.heartRate, on: day, engine: store.engine) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Kicker("Mi Fitness → Health Connect → this Mac")
                        Text(archive.lastSync.map { "Last synced \(timeText(Date(timeIntervalSince1970: $0), engine: store.engine)) · \(dateText(store.engine.key(Date(timeIntervalSince1970: $0)), engine: store.engine))" } ?? "Connect your phone to bring your routine into focus.").font(.system(size: 12)).foregroundStyle(Ink.muted)
                        Text("Read-only. Stored locally. Excluded from AI. Sleep and step habits fill from these readings; a value you type yourself is kept.").font(.system(size: 11)).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                }
                PhoneLinkPanel(link: store.phoneLink)
                if archive.lastSync == nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your phone is the bridge.").font(.system(size: 20, weight: .semibold))
                        Text("1. Sync your watch in Mi Fitness and keep its Health Connect sharing on.\n2. Install or update Ascend Bridge with Install phone app above.\n3. In Ascend Bridge, choose health permissions, then Pair with Mac and confirm the code here.\n4. Whenever you want, tap Sync to Mac on the phone. Both devices just need the same Wi-Fi.").font(.system(size: 13)).lineSpacing(7)
                        Text("The companion reads the last 14 days of Mi Fitness data. Ascend keeps earlier imported records, refreshes corrections without duplicates and creates a backup before every import. No watch readings are fabricated.").font(.system(size: 12)).foregroundStyle(Ink.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading).panel()
                }
                HStack {
                    Kicker("Your readings")
                    Spacer()
                    Button { day = store.engine.adding(-1, to: day) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).accessibilityLabel("Previous health day")
                    DatePicker("Health date", selection: Binding(get: { store.engine.date(day) ?? Date() }, set: { day = store.engine.key($0) }), in: ...Date(), displayedComponents: .date).labelsHidden().fixedSize()
                    Button { day = store.engine.adding(1, to: day) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).disabled(day >= store.today).accessibilityLabel("Next health day")
                    Button("Today") { day = store.today }.buttonStyle(.plain).font(.system(size: 12))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 12) {
                    card(.heartRate); restingCard; card(.oxygen)
                    card(.steps); distanceCard; card(.activeEnergy)
                    card(.sleep); bedWakeCard
                    // Mi Fitness writes workouts only when one is recorded on the watch; speed and elevation aren't shown.
                    if archive.hasWorkouts { card(.workout) }
                }
                if let night = archive.sleepSessions(on: day, engine: store.engine).first { sleepPanel(night) }
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("Heart rate through the day").font(.system(size: 15, weight: .semibold)); Spacer(); Text("\(heart.map(\.weight).reduce(0, +)) samples").font(.system(size: 11)).foregroundStyle(Ink.muted) }
                    if heart.isEmpty {
                        Text("No heart-rate samples for this date. Sync Mi Fitness and check that heart-rate sharing is allowed.").font(.system(size: 12)).foregroundStyle(Ink.muted).frame(maxWidth: .infinity, minHeight: 110)
                    } else {
                        Chart(heart) { r in
                            PointMark(x: .value("Time", Date(timeIntervalSince1970: r.start)), y: .value("BPM", r.value)).symbolSize(9).foregroundStyle(Ink.accent)
                        }.chartYAxisLabel("bpm").frame(height: 150)
                        Text("\(Int(heart.map(\.lowest).min() ?? 0))–\(Int(heart.map(\.highest).max() ?? 0)) bpm observed. " + (heart.contains { $0.samples != nil } ? "Older days show 5-minute averages; gaps are not filled in." : "Dots show recorded samples; gaps are not filled in.")).font(.system(size: 11)).foregroundStyle(Ink.muted)
                    }
                }.panel()
                Text("Only records Mi Fitness writes to Health Connect can arrive here. This is a historical sync, not a live heart-rate stream. Values describe recorded activity; activity calories do not represent food intake. Interval records use their start date; sleep uses its ending date. Missing or denied types display no new data, and previously imported records remain local.").font(.system(size: 11)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                if !archive.errors.isEmpty {
                    VStack(alignment: .leading, spacing: 7) { Kicker("Some types could not refresh"); ForEach(archive.errors.keys.sorted(), id: \.self) { key in Text("\(HealthMetric(rawValue: key)?.title ?? key): \(archive.errors[key] ?? "")").font(.system(size: 12)).foregroundStyle(.orange) } }.panel()
                }
            }.padding(.bottom, 10)
        }
        .onChange(of: store.today) { old, new in if day == old { day = new } }
        .sheet(isPresented: $stepsHelp) { stepsExplanation }
    }
    private func duration(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
    private static let stageRows = ["Awake", "REM", "Light", "Deep"]
    private func stageColor(_ kind: SleepStageKind) -> Color {
        switch kind.depth { case 3: Ink.accent; case 2: Ink.accent.opacity(0.55); case 1: Color(red: 0.45, green: 0.78, blue: 0.86); default: Color.orange.opacity(0.75) }
    }
    /// The main night's stages as a cycle chart, with time and share per stage.
    private func sleepPanel(_ night: HealthRecord) -> some View {
        let stages = (night.stages ?? []).sorted { $0.start < $1.start }
        let minutes = night.stageMinutes
        let total = minutes.values.reduce(0, +)
        let engine = store.engine
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sleep stages").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(timeText(Date(timeIntervalSince1970: night.start), engine: engine)) – \(timeText(Date(timeIntervalSince1970: night.end), engine: engine))").font(.system(size: 11)).foregroundStyle(Ink.muted)
            }
            if stages.isEmpty {
                Text(night.detail == "Asleep stages"
                     ? "This night was imported before stages were sent. Update Ascend Bridge to 0.2.1 and tap Sync to Mac to see deep, light, REM and awake time."
                     : "Mi Fitness reported only a session window for this night, without stages.").font(.system(size: 12)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            } else {
                Chart(Array(stages.enumerated()), id: \.offset) { _, stage in
                    RectangleMark(xStart: .value("Start", Date(timeIntervalSince1970: stage.start)), xEnd: .value("End", Date(timeIntervalSince1970: stage.end)),
                                  y: .value("Stage", Self.stageRows[stage.kind.depth]), height: .ratio(0.9))
                        .foregroundStyle(stageColor(stage.kind))
                }.chartYScale(domain: Self.stageRows).frame(height: 140)
                HStack(spacing: 22) {
                    ForEach([SleepStageKind.deep, .rem, .light, .awake], id: \.self) { kind in
                        let value = kind == .awake ? (minutes[.awake] ?? 0) + (minutes[.awakeInBed] ?? 0) + (minutes[.outOfBed] ?? 0) : kind == .light ? (minutes[.light] ?? 0) + (minutes[.asleep] ?? 0) : minutes[kind] ?? 0
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) { Circle().fill(stageColor(kind)).frame(width: 7, height: 7); Kicker(kind.title) }
                            Text(duration(value)).font(.system(size: 16, weight: .semibold))
                            Text(total > 0 ? "\(Int((value / total * 100).rounded()))%" : "—").font(.system(size: 10)).foregroundStyle(Ink.muted)
                        }
                    }
                    Spacer()
                }
                Text("As reported by Mi Fitness. Stage estimates from a wrist device are approximate; Ascend shows them as recorded and doesn't score or diagnose them.").font(.system(size: 11)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            }
        }.panel()
    }
    private func card(_ metric: HealthMetric) -> some View {
        // Sleep shows the main night; overlapping copies are merged and naps are listed separately.
        let records = metric == .sleep ? archive.sleepSessions(on: day, engine: store.engine) : archive.records(metric, on: day, engine: store.engine)
        let denied = archive.permissions[metric.rawValue] == false
        let failed = archive.errors[metric.rawValue] != nil
        let average = metric == .heartRate || metric == .oxygen || metric == .speed
        let value = records.isEmpty ? nil : metric == .sleep ? records[0].value : (average ? HealthArchive.average(records) : records.map(\.value).reduce(0,+))
        let naps = records.dropFirst().map(\.value).reduce(0, +)
        let sleepDetail = records.first.map { main in
            let minutes = main.stageMinutes
            let summary = minutes.isEmpty ? (main.detail == "Asleep stages" ? "Asleep stages" : "Session window")
                : [SleepStageKind.deep, .rem, .light].compactMap { kind in minutes[kind].map { "\(kind.title) \(duration($0))" } }.joined(separator: " · ")
            return summary + (naps > 0 ? " · + \(naps.formatted(.number.precision(.fractionLength(1)))) h nap" : "")
        } ?? ""
        let note = denied ? "Not shared · earlier data retained" : failed ? "Refresh failed · earlier data retained"
            : records.isEmpty ? (metric == .steps ? "No Mi Fitness steps received for this date" : "No records for this date")
            : metric == .sleep ? sleepDetail : metric == .heartRate ? heartNote(records) : metric == .oxygen ? oxygenNote
            : average ? "Average of recorded samples" : metric == .steps ? "Mi Fitness · daily aggregate"
            : records.contains(where: { $0.detail == "In progress" }) ? "So far today · updates each sync"
            : "\(records.count) recorded \(records.count == 1 ? "interval" : "intervals")"
        return tile(metric.title, value.map { $0.formatted(.number.precision(.fractionLength(metric == .steps || metric == .heartRate ? 0 : 1))) }, metric.unit, note, help: metric == .steps)
    }
    private func tile(_ title: String, _ value: String?, _ unit: String, _ note: String, help: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Kicker(title)
                Spacer()
                if help {
                    Button { stepsHelp = true } label: { Image(systemName: "questionmark.circle") }.buttonStyle(.plain).foregroundStyle(Ink.accent).accessibilityLabel("Why steps may be missing")
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value ?? "—").font(.system(size: 26, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(unit).font(.system(size: 10)).foregroundStyle(Ink.muted)
            }
            Text(note).font(.system(size: 10)).foregroundStyle(Ink.muted).lineLimit(2).frame(minHeight: 26, alignment: .top)
        }.frame(maxWidth: .infinity, alignment: .leading).panel(padding: 14)
    }
    private var night: HealthRecord? { archive.sleepSessions(on: day, engine: store.engine).first }
    private var vitals: NightVitals? { night.map(archive.nightVitals) }
    /// Mi Fitness can hold back heart rate for hours, so show when the newest sample is from.
    private func heartNote(_ records: [HealthRecord]) -> String {
        guard let last = records.map(\.start).max() else { return "" }
        let stale = day == store.today && Date().timeIntervalSince1970 - last > 3 * 3600
        return "\(records.map(\.weight).reduce(0, +)) samples · latest \(timeText(Date(timeIntervalSince1970: last), engine: store.engine))" + (stale ? " · newer readings not shared yet" : "")
    }
    private var oxygenNote: String {
        guard let vitals, let average = vitals.averageOxygen, let low = vitals.lowestOxygen else { return "Average of recorded samples" }
        return "Asleep: average \(average.formatted(.number.precision(.fractionLength(1))))% · lowest \(Int(low))%"
    }
    private var restingCard: some View {
        let note = night == nil ? "No sleep recorded for this date"
            : vitals?.restingHeartRate == nil ? "No heart-rate samples while asleep"
            : "Lowest while asleep · \(vitals!.heartSamples) samples, average \(Int(vitals!.averageHeartRate!.rounded()))"
        return tile("Resting heart rate", vitals?.restingHeartRate.map { "\(Int($0))" }, "bpm", note)
    }
    private var distanceCard: some View {
        let recorded = archive.records(.distance, on: day, engine: store.engine)
        let estimate = archive.estimatedDistance(on: day, engine: store.engine)
        let meters = recorded.isEmpty ? estimate : recorded.map(\.value).reduce(0, +)
        return tile("Distance", meters.map { ($0 / 1000).formatted(.number.precision(.fractionLength(1))) }, "km",
                    !recorded.isEmpty ? "Recorded by Mi Fitness" : estimate == nil ? "No steps for this date" : "Estimated from steps × \(HealthArchive.strideMeters.formatted()) m stride")
    }
    private var bedWakeCard: some View {
        let engine = store.engine
        let drift = night.flatMap(engine.drift)
        let routine = store.document.routine
        func describe(_ minutes: Int) -> String { abs(minutes) <= 15 ? "on time" : "\(duration(Double(abs(minutes)))) \(minutes > 0 ? "late" : "early")" }
        let note = night == nil ? "No sleep recorded for this date"
            : drift.map { "Bed \(describe($0.bedtime)) · wake \(describe($0.wake)) vs \(clockTime(routine.bedMinute))–\(clockTime(routine.wakeMinute)) plan" }
            ?? "Set your routine to compare with your plan"
        return tile("Bed & wake", night.map { "\(timeText(Date(timeIntervalSince1970: $0.start), engine: engine)) → \(timeText(Date(timeIntervalSince1970: $0.end), engine: engine))" }, "", note)
    }
    private var stepsExplanation: some View {
        let total = archive.records.filter { $0.metric == .steps }.count
        let selected = archive.records(.steps, on: day, engine: store.engine)
        return EditorShell(title: "Where are my steps?") {
            Text("Mi Fitness → Health Connect → Ascend").font(.system(size: 13, weight: .medium))
            if archive.lastSync == nil {
                Text("No health transfer has been saved yet. Sync your watch and phone first.")
            } else if archive.permissions["steps"] == false {
                Text("Steps read permission wasn't granted in the last transfer. Choose health permissions in Ascend Bridge on your phone. Earlier imported data is retained.")
            } else if let error = archive.errors["steps"] {
                Text("Steps could not refresh in the last transfer. Earlier imported data is retained.")
                Text(error).foregroundStyle(.orange)
            } else if total == 0 {
                Text("The saved transfers contain no Mi Fitness step records. Permission allows a read; Mi Fitness must also publish its step data to Health Connect.")
            } else if selected.isEmpty {
                Text("No Mi Fitness steps were received for \(dateText(day, engine: store.engine)). Other dates have imported steps; use the date controls to review them.")
            } else {
                Text("This date has a Mi Fitness daily total. It may differ from a phone-wide total that combines other apps or the phone's own step counter.")
            }
            FieldGroup(label: "Check on your phone") {
                Text("1. Open Mi Fitness and finish syncing the watch. Confirm steps appear there.\n\n2. In Mi Fitness, review Health Connect sharing and allow steps to be written.\n\n3. In Android Health Connect, browse Steps entries and check that Mi Fitness is listed as a source. Steps visible only inside Mi Fitness have not necessarily been shared.\n\n4. Open Ascend Bridge, keep your phone unlocked and tap Sync to Mac.").fixedSize(horizontal: false, vertical: true)
            }
            Text("Ascend currently reads only Mi Fitness. Phone-only steps and records from other apps are excluded. A dash means unavailable, not zero. For manual tracking, log your Walk 10,000 steps habit; that stays separate from imported readings.").font(.system(size: 12)).foregroundStyle(Ink.muted)
        } actions: {
            HStack { Spacer(); PrimaryButton(label: "Got it") { stepsHelp = false } }
        }
        .font(.system(size: 13))
    }
}
