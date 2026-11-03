import AscendCore
import Charts
import SwiftUI

func bodyNumber(_ x: Double?, unit: String = "") -> String {
  x.map { String(format: "%.2f", $0) + unit } ?? "—"
}
func bodyClock(_ date: Date, calendar: Calendar) -> String {
  HealthReport.clock(
    calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date))
}
struct BodyHealthChip: View {
  @ObservedObject var store: BodyMeasurementStore
  var open: () -> Void
  var body: some View {
    Button(action: open) {
      HStack {
        Image(systemName: "scalemass")
        Text(
          "Body · \(bodyNumber(store.archive.records.last?.kilograms,unit:" kg")) · \(bodyNumber(store.archive.records.last{!$0.isManual && $0.value("bodyFatPercentage") != nil}?.value("bodyFatPercentage"),unit:"% scale estimate"))"
        )
        Spacer()
        Text("Open Body ↗")
      }.font(.system(size: 12)).padding(14).background(
        Ink.panel, in: RoundedRectangle(cornerRadius: 12))
    }.buttonStyle(.plain)
  }
}
struct BodyView: View {
  @ObservedObject var store: TrackerStore
  @ObservedObject var training: TrainingStore
  @ObservedObject var measurements: BodyMeasurementStore
  @State private var demos = false
  @State private var demoExercise: TrainingExercise?
  @State private var settings = false
  @State private var planEditor = false
  @State private var weightEditor = false
  @State private var editingWeight: BodyMeasurement?
  @State private var logging: TrainingExercise?
  @State private var history: TrainingExercise?
  @State private var chartDate: Date?
  @State private var photos = false
  @State private var photoAngle = PhotoAngle.front
  init(store: TrackerStore) {
    self.store = store
    training = store.training
    measurements = store.bodyMeasurements
  }
  private var a: TrainingArchive { training.archive }
  private var now: Date { Date() }
  private var cal: Calendar {
    var c = store.engine.calendar
    c.firstWeekday = 2
    return c
  }
  private var report: BodyGoalReport {
    .build(records: measurements.archive.records, goal: a.goal, now: now, calendar: cal)
  }
  private var score: TrainingScorecard {
    .build(training: a, health: store.document.health, now: now, calendar: cal)
  }
  private var week: DateInterval { cal.dateInterval(of: .weekOfYear, for: now)! }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if ProcessInfo.processInfo.environment["ASCEND_BODY_SAMPLE"] == "1" {
          Text("GENERATED SAMPLE DATA · NOT YOUR PERSONAL RECORDS").font(
            .system(size: 11, design: .monospaced)
          ).foregroundStyle(.orange)
        }
        if let error = training.error {
          Text(error).foregroundStyle(.orange).textSelection(.enabled)
        }
        goalHeader
        weightTrend
        todayCard
        stepsToday
        scorecard
        muscleCard
        photoCard
        DisclosureGroup("Scale readings & Dr Trust connection") {
          BodyMeasurementPanel(store: measurements, cloud: store.drTrust).padding(.top, 8)
        }
      }.padding(.bottom, 12)
    }
    .sheet(isPresented: $demos) { ExerciseDemoSheet() }
    .sheet(item: $demoExercise) { e in ExerciseDemoSheet(initialID: e.animationID) }
    .sheet(isPresented: $settings) { BodySettingsEditor(store: training, calendar: cal) }
    .sheet(isPresented: $planEditor) { TrainingPlanEditor(store: training) }
    .sheet(isPresented: $weightEditor) {
      ManualWeightEditor(store: measurements, existing: nil, calendar: cal)
    }
    .sheet(item: $editingWeight) { r in
      ManualWeightEditor(store: measurements, existing: r, calendar: cal)
    }
    .sheet(item: $logging) { e in SetLogEditor(store: training, exercise: e, calendar: cal) }
    .sheet(item: $history) { e in ExerciseHistoryView(store: training, exercise: e, calendar: cal) }
    .sheet(isPresented: $photos) {
      VStack {
        HStack {
          Text("Body photo comparison").font(.title2)
          Spacer()
          Button("Done") { photos = false }
        }
        PhotosView(store: store, initialArea: .body, initialAngle: photoAngle)
      }.padding(24).frame(minWidth: 850, minHeight: 650)
    }
  }
  private func title(_ kicker: String, _ headline: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Kicker(kicker)
      Text(headline).font(.system(size: 23, weight: .semibold)).tracking(-0.5)
    }
  }
  private func stat(_ label: String, _ value: String, _ note: String = "") -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label.uppercased()).font(.system(size: 10, design: .monospaced)).foregroundStyle(
        Ink.muted)
      Text(value).font(.system(size: 23, weight: .semibold)).monospacedDigit()
      if !note.isEmpty { Text(note).font(.system(size: 11)).foregroundStyle(Ink.muted) }
    }
  }
  private var goalHeader: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top) {
        title("BODY GOAL", report.headline)
        Spacer()
        Button("Goal & coach settings") { settings = true }
      }
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading,
        spacing: 18
      ) {
        stat("Current weight", bodyNumber(report.weight, unit: " kg"))
        stat("Body fat", bodyNumber(report.fat, unit: "%"), "Scale estimate · not a scan")
        stat(
          "Goal", bodyNumber(a.goal.targetFat, unit: "%"),
          a.goal.targetDate.map { store.engine.key($0) } ?? "Set a target date")
        stat(
          "Weight at goal", bodyNumber(report.goalWeight, unit: " kg"),
          "Assumes lean mass is retained")
        stat(
          "Actual / week", bodyNumber(report.actualLossPerWeek, unit: " kg"),
          "Loss · 4-week weekly averages")
        stat(
          "Needed / week", bodyNumber(report.neededLossPerWeek, unit: " kg"),
          "To the chosen deadline")
      }
      if let projected = report.projectedDate {
        Text(
          "At this pace: \(store.engine.key(projected)) · lean mass estimate \(bodyNumber(report.leanMass,unit:" kg"))."
        ).font(.system(size: 12)).foregroundStyle(Ink.accent)
      }
      if report.aggressive, let early = report.earliestDate, let gentle = report.gentlerDate {
        Text(
          "Planning range at 0.5–0.75% per week: \(store.engine.key(early)) to \(store.engine.key(gentle)). These estimates are not a medical prescription."
        ).font(.system(size: 12)).foregroundStyle(.orange)
      }
      ForEach(a.goal.checkpoints.sorted { $0.date < $1.date }) { p in
        Text(
          "Checkpoint · \(bodyNumber(p.targetFat,unit:"%"))\(p.targetWeight.map{" · \(bodyNumber($0,unit:" kg"))"} ?? "") · \(store.engine.key(p.date))"
        ).font(.system(size: 12)).foregroundStyle(Ink.muted)
      }
    }.panel(padding: 22)
  }
  private var weightTrend: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        title("WEIGHT TREND", "Follow the average.")
        Spacer()
        Button("Log weight") { weightEditor = true }
      }
      if measurements.archive.records.isEmpty {
        Text("Log your first weight or connect Dr Trust below.").foregroundStyle(Ink.muted)
      } else {
        Chart {
          ForEach(measurements.archive.records) { r in
            LineMark(
              x: .value("Date", r.date), y: .value("kg", r.kilograms),
              series: .value("Series", "Readings")
            ).foregroundStyle(Ink.accent.opacity(0.4))
            PointMark(x: .value("Date", r.date), y: .value("kg", r.kilograms)).foregroundStyle(
              Ink.accent.opacity(0.5)
            ).symbolSize(16)
          }
          ForEach(report.weekly) { r in
            LineMark(
              x: .value("Date", r.date), y: .value("kg", r.kilograms),
              series: .value("Series", "Weekly average")
            ).foregroundStyle(Color.mint).lineStyle(StrokeStyle(lineWidth: 3))
          }
          if let goal = report.goalWeight {
            RuleMark(y: .value("Goal", goal)).foregroundStyle(.orange.opacity(0.7)).lineStyle(
              StrokeStyle(dash: [5, 4])
            ).annotation(position: .top, alignment: .leading) {
              Text("Goal \(bodyNumber(goal)) kg").font(.caption2)
            }
          }
        }.chartYScale(domain: .automatic(includesZero: false)).chartXSelection(value: $chartDate)
          .frame(height: 170)
        if let date = chartDate,
          let r = measurements.archive.records.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
          })
        {
          Text(readingLabel(r)).font(.system(size: 12, design: .monospaced)).foregroundStyle(
            Ink.accent)
        }
        HStack {
          Label("Readings", systemImage: "circle.fill").foregroundStyle(Ink.accent)
          Label("Weekly average", systemImage: "line.diagonal").foregroundStyle(.mint)
          Spacer()
          Text("Week \(BodyGoalReport.weekNumber(now,weekOne:a.weekOne,calendar:cal))")
        }.font(.system(size: 10))
        DisclosureGroup("Reading history · edit manual entries only") {
          ForEach(measurements.archive.records.reversed()) { r in
            HStack {
              Text(readingLabel(r)).font(.system(size: 12)).textSelection(.enabled)
              Spacer()
              if r.isManual {
                Button("Edit") { editingWeight = r }
              } else {
                Text("Dr Trust · read only").font(.caption).foregroundStyle(Ink.muted)
              }
            }.padding(.vertical, 4)
          }
        }
      }
    }.panel(padding: 22)
  }
  private func readingLabel(_ r: BodyMeasurement) -> String {
    "\(store.engine.key(r.date)) · \(bodyClock(r.date,calendar:cal)) · Week \(BodyGoalReport.weekNumber(r.date,weekOne:a.weekOne,calendar:cal)) · \(bodyNumber(r.kilograms,unit:" kg"))\(r.isManual ? " · manual":"")"
  }
  private var todayCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      let session = a.today(now, calendar: cal)
      HStack {
        title("TODAY’S SESSION", session?.name ?? "Make room for movement.")
        Spacer()
        Button("Workout artwork") { demos = true }
        Button("Edit weekly plan") { planEditor = true }
      }
      HStack(spacing: 8) {
        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in
          let p = a.plan.first { $0.weekday == d }
          VStack(spacing: 5) {
            Text(cal.shortWeekdaySymbols[d - 1]).font(.system(size: 10, design: .monospaced))
            Text(p?.kind.rawValue.capitalized ?? "—").font(.system(size: 10))
            Text(p?.name ?? "Unplanned").font(.system(size: 10)).lineLimit(1)
          }.frame(maxWidth: .infinity).padding(8).background(
            Ink.accent.opacity(d == cal.component(.weekday, from: now) ? 0.16 : 0.035),
            in: RoundedRectangle(cornerRadius: 8))
        }
      }
      if let session {
        if session.kind == .cardio {
          Text(
            "\(session.cardioType) · \(Int(session.minutes)) min · incline \(bodyNumber(session.incline)) · speed \(bodyNumber(session.speed))"
          ).font(.system(size: 13))
        }
        Text("Rest between sets: \(session.restSeconds) s · \(Int(session.minutes)) min planned")
          .font(.system(size: 11)).foregroundStyle(Ink.muted)
        ForEach(session.supersets.indices, id: \.self) { i in
          Text(
            "Superset \(i+1): "
              + session.supersets[i].compactMap { id in a.exercises.first { $0.id == id }?.name }
              .joined(separator: " + ")
          ).font(.system(size: 12)).foregroundStyle(Ink.accent)
        }
        ForEach(session.exercises, id: \.self) { id in
          if let e = a.exercises.first(where: { $0.id == id }) { exerciseRow(e) }
        }
        HStack {
          Button("Mark session done") {
            training.complete(session, date: now, outcome: .done, calendar: cal)
          }
          Button("Rest day") {
            training.complete(session, date: now, outcome: .rest, calendar: cal)
          }
          Button("Skip today") {
            training.complete(session, date: now, outcome: .skipped, calendar: cal)
          }
        }
      } else {
        Text("Choose a weekday and add exercises in the plan editor.").font(.system(size: 12))
          .foregroundStyle(Ink.muted)
      }
      if let done = a.completions.last(where: { cal.isDate($0.date, inSameDayAs: now) }) {
        Text("Today marked: \(done.outcome.rawValue)").font(.system(size: 12)).foregroundStyle(
          Ink.accent)
      }
      ForEach(
        a.priorityVolume(now: now, calendar: cal).filter {
          $0.planned < $0.minimum || $0.logged < $0.minimum
        }
      ) { v in
        HStack {
          Image(systemName: "lightbulb")
          Text(
            "\(v.muscle.rawValue): \(v.planned) planned / \(v.logged) logged so far · aim for ≥\(v.minimum) hard sets/week"
          ).font(.system(size: 12))
          Spacer()
          Button("Review plan") { planEditor = true }
        }.padding(12).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
      }
    }.panel(padding: 22)
  }
  private func exerciseRow(_ e: TrainingExercise) -> some View {
    let last = a.lastLog(e.id, before: cal.startOfDay(for: now))
    return HStack {
      VStack(alignment: .leading, spacing: 5) {
        Text(e.name).font(.system(size: 15, weight: .medium))
        Text(
          "\(e.sets) × \(e.minReps)–\(e.maxReps)\(e.timed ? " s":" reps") · \(e.equipment)\(e.assisted ? " · assistance":"")"
        ).font(.system(size: 11)).foregroundStyle(Ink.muted)
        Text(
          last.map {
            "Last: "
              + $0.sets.map { "\(bodyNumber($0.weight)) × \($0.reps)" }.joined(separator: " · ")
          } ?? "No previous sets"
        ).font(.system(size: 11))
        if a.rules.progressionEnabled {
          Text(
            a.stalled(e, now: now)
              ? "Stalled for \(a.rules.stallWeeks)+ weeks · review recovery and progression"
              : (e.timed ? "+5 s when comfortable" : TrainingProgression.hint(e, last: last))
          ).font(.system(size: 11)).foregroundStyle(a.stalled(e, now: now) ? .orange : Ink.accent)
        }
      }
      Spacer()
      if ExerciseDemoLibrary.entries.contains(where: { $0.id == e.animationID }) {
        Button("Artwork") { demoExercise = e }
      }
      Button("History") { history = e }
      Button("Log sets") { logging = e }
    }.padding(.vertical, 9).overlay(alignment: .bottom) {
      Rectangle().fill(Ink.line).frame(height: 1)
    }
  }
  private var stepsToday: some View {
    let report = TrainingStepsReport.build(
      training: a, health: store.document.health, document: store.document, now: now)
    return VStack(alignment: .leading, spacing: 14) {
      title("STEPS TODAY", report.headline)
      HStack(spacing: 36) {
        stat("Watch steps", report.steps.map { Int($0).formatted() } ?? "—")
        stat("Daily floor", report.floor.formatted())
        stat("Habit target", report.target.map { Int($0).formatted() } ?? "Not configured")
      }
      ForEach(report.blocks) { item in
        HStack {
          Toggle(
            item.block.title,
            isOn: Binding(
              get: { item.checked },
              set: { on in
                training.change { a in
                  var ids = a.stepChecks[store.today] ?? []
                  ids.removeAll { $0 == item.id }
                  if on { ids.append(item.id) }
                  a.stepChecks[store.today] = ids
                }
              })
          ).disabled(item.evidence != nil)
          Spacer()
          Text(
            item.evidence
              ?? "Plan · ≈ \(item.block.steps.formatted()) steps · \(item.block.minutes) min"
          ).font(.system(size: 11)).foregroundStyle(Ink.muted)
        }
      }
      Text(report.remaining).font(.system(size: 13)).foregroundStyle(Ink.accent)
      if report.railsHint {
        Label(
          "Holding the rails? The watch doesn't count steps when your wrist is still.",
          systemImage: "hand.raised"
        ).font(.system(size: 12)).foregroundStyle(.orange)
      }
      Text(
        "Plan estimates are not added to watch totals. Watch evidence ticks blocks where the time window supports it; other boxes are manual. Easy evening walks are fine."
      ).font(.system(size: 11)).foregroundStyle(Ink.muted)
    }.panel(padding: 22)
  }
  private var scorecard: some View {
    VStack(alignment: .leading, spacing: 16) {
      title("THIS WEEK", "Consistency is the score.")
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading
      ) {
        stat("Strength", "\(score.strength) / 3")
        stat("Cardio", "\(score.cardio) / 3")
        stat("Walking days", "\(score.walkingDays) / 7", "≥\(a.rules.stepsFloor.formatted()) steps")
        stat("Long easy cardio", "\(score.longCardio) / 1", "45–75 min · low HR intensity")
      }
      let steps = store.document.health.steps(on: store.today, engine: store.engine)
      if let nudge = a.walkNudge(
        steps: steps, now: now,
        mealTimes: store.document.meals.entries.map { Date(timeIntervalSince1970: $0.takenAt) },
        calendar: cal)
      {
        Label(nudge, systemImage: "figure.walk").font(.system(size: 13)).foregroundStyle(Ink.accent)
      }
      Text(
        "Watch + manual completion on the same day count once. Missing step/HR data stays unknown; low-intensity credit needs heart-rate evidence. Intensity is an age-based estimate."
      ).font(.system(size: 11)).foregroundStyle(Ink.muted)
      ForEach(score.workouts) { w in
        VStack(alignment: .leading, spacing: 5) {
          HStack {
            Text(w.session ?? w.title).font(.system(size: 14, weight: .medium))
            Spacer()
            Text(
              "\(store.engine.key(w.start)) · \(bodyClock(w.start,calendar:cal))–\(bodyClock(w.end,calendar:cal))"
            ).font(.system(size: 11)).foregroundStyle(Ink.muted)
          }
          Text(
            "\(Int(w.minutes)) min · \(w.intensity) · HR \(w.averageHR.map{String(Int($0))} ?? "—") avg / \(w.maxHR.map{String(Int($0))} ?? "—") max · \(bodyNumber(w.distance.map{$0/1000},unit:" km")) · \(bodyNumber(w.calories,unit:" kcal"))"
          ).font(.system(size: 11))
          if w.late {
            Button(
              "Late, may delay sleep · routine bed \(HealthReport.clock(store.document.routine.bedMinute)) ↗"
            ) { store.pendingScreen = "Routine" }.buttonStyle(.plain).foregroundStyle(.orange)
          }
        }.padding(12).background(
          Ink.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
      }
      if a.rules.calorieCaution {
        Text("Watch calories can run high. Shown for reference; never used to suggest eating more.")
          .font(.system(size: 11)).foregroundStyle(Ink.muted)
      }
    }.panel(padding: 22)
  }
  private var muscleCard: some View {
    let volumes = a.muscleVolume(from: week.start, to: min(week.end, now))
    return VStack(alignment: .leading, spacing: 16) {
      title("WEEKLY MUSCLE VOLUME", "Give every region its share.")
      HStack(alignment: .top, spacing: 28) {
        BodyMapView(
          volumes: Dictionary(uniqueKeysWithValues: volumes.map { ($0.key.rawValue, $0.value) }),
          exerciseNames: muscleExercises)
        VStack(alignment: .leading, spacing: 12) {
          Text("Hard sets logged this week").font(.system(size: 17, weight: .medium))
          Text(
            "Neutral 0 · dim 1–9 · accent 10–20 · warning 21+\nA tagged hard set counts once for each region. Warm-up sets are excluded. Targets are a general reference; edit your plan to suit recovery."
          ).font(.system(size: 12)).foregroundStyle(Ink.muted).fixedSize(
            horizontal: false, vertical: true)
          ForEach(volumes.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { m in
            HStack {
              Text(m.title)
              Spacer()
              Text("\(volumes[m]!) sets").monospacedDigit()
            }.font(.system(size: 12))
          }
          if volumes.isEmpty {
            Text("Log hard sets to light up your training map.").foregroundStyle(Ink.muted)
          }
        }.frame(maxWidth: .infinity)
      }
    }.panel(padding: 22)
  }
  private var muscleExercises: [String: [String]] {
    var names: [String: Set<String>] = [:]
    for l in a.logs
    where l.date >= week.start && l.date <= now && l.sets.contains(where: { $0.hard }) {
      let name = a.exercises.first { $0.id == l.exerciseID }?.name ?? "Exercise"
      for m in l.muscles { names[m.rawValue, default: []].insert(name) }
    }
    return names.mapValues { $0.sorted() }
  }
  private var photoCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      title("PROGRESS PHOTOS", "Same angle. See the change.")
      HStack(spacing: 16) {
        ForEach([PhotoAngle.front, .left, .back], id: \.self) { angle in
          let latest = store.document.photos.photos(.body, angle: angle).last
          VStack(spacing: 8) {
            if let latest,
              let image = PhotoCache.image(store.progressPhotoURL(latest), maxPixel: 400)
            {
              Image(nsImage: image).resizable().scaledToFit().frame(height: 120)
            } else {
              Image(systemName: "person.crop.rectangle").font(.system(size: 32)).foregroundStyle(
                Ink.muted
              ).frame(height: 90)
            }
            Text(angle.label).font(.system(size: 12, weight: .medium))
            Text(latest?.day ?? "No photo yet").font(.system(size: 11)).foregroundStyle(Ink.muted)
            Button("Compare with first") {
              photoAngle = angle
              photos = true
            }.disabled(latest == nil)
          }.frame(maxWidth: .infinity)
        }
      }
      Button("Open Photos") { store.pendingScreen = "Photos" }
    }.panel(padding: 22)
  }
}
