import AscendCore
import Charts
import SwiftUI

struct ManualWeightEditor: View {
  @ObservedObject var store: BodyMeasurementStore
  let existing: BodyMeasurement?
  let calendar: Calendar
  @Environment(\.dismiss) var dismiss
  @State private var weight = ""
  @State private var date = Date()
  @State private var error: String?
  @State private var deleting = false
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(existing == nil ? "Log weight" : "Edit manual weight").font(.title2)
      TextField("Kilograms · 2 decimals", text: $weight).onSubmit { save() }
      DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
      HStack {
        Text("Time")
        DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute).labelsHidden()
          .environment(\.locale, Locale(identifier: "en_US_POSIX"))
        Text(bodyClock(date, calendar: calendar)).font(.caption).foregroundStyle(Ink.muted)
      }
      Text("Manual weight only. Scale body-fat estimates remain unchanged.").font(.caption)
        .foregroundStyle(Ink.muted)
      if let error { Text(error).foregroundStyle(.orange) }
      HStack {
        if existing != nil {
          Button("Delete manual reading", role: .destructive) { deleting = true }
        }
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Save") { save() }.keyboardShortcut(.defaultAction)
      }
    }.padding(24).frame(width: 470).onAppear {
      weight = existing.map { String(format: "%.2f", $0.kilograms) } ?? ""
      date = existing?.date ?? Date()
    }.confirmationDialog("Delete this manual reading?", isPresented: $deleting) {
      Button("Delete", role: .destructive) {
        do {
          try store.deleteManual(existing!.id)
          dismiss()
        } catch { self.error = error.localizedDescription }
      }
    }
  }
  private func save() {
    guard let kg = Double(weight), kg > 0, kg <= 1000 else {
      error = "Enter a valid weight in kg."
      return
    }
    do {
      try store.saveManual(id: existing?.id, kilograms: (kg * 100).rounded() / 100, date: date)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}
struct BodySettingsEditor: View {
  @ObservedObject var store: TrainingStore
  let calendar: Calendar
  @State private var draft = TrainingArchive()
  @State private var fat = ""
  @State private var weight = ""
  @State private var age = ""
  @State private var height = ""
  @State private var due = Date()
  @State private var hasDue = false
  @State private var formError: String?
  @Environment(\.dismiss) var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Body goal & coach rules").font(.title2)
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Save") { save() }.keyboardShortcut(.defaultAction)
      }
      ScrollView {
        Form {
          Section("Goal") {
            TextField("Target body fat % (optional)", text: $fat)
            TextField("Target weight kg (optional)", text: $weight)
            Toggle("Use a target date", isOn: $hasDue)
            if hasDue { DatePicker("Target date", selection: $due, displayedComponents: .date) }
            DatePicker("Week 1 starts", selection: $draft.weekOne, displayedComponents: .date)
            TextField("Age for HR / maintenance estimates (optional)", text: $age)
            TextField("Height cm for maintenance (optional)", text: $height)
            Picker(
              "Formula sex coefficient",
              selection: Binding(
                get: { draft.maintenanceSex?.rawValue ?? "" },
                set: { draft.maintenanceSex = MaintenanceSex(rawValue: $0) })
            ) {
              Text("Not set").tag("")
              Text("Male").tag("male")
              Text("Female").tag("female")
            }
          }
          Section("Goal checkpoints") {
            ForEach($draft.goal.checkpoints) { $p in
              HStack {
                TextField("Body fat %", value: $p.targetFat, format: .number).frame(width: 90)
                DatePicker("Date", selection: $p.date, displayedComponents: .date)
                TextField(
                  "Weight kg (optional)",
                  text: Binding(
                    get: { p.targetWeight.map { String($0) } ?? "" },
                    set: { p.targetWeight = Double($0) })
                ).frame(width: 125)
                Button("Remove") { draft.goal.checkpoints.removeAll { $0.id == p.id } }
              }
            }
            Button("Add checkpoint") { draft.goal.checkpoints.append(BodyCheckpoint()) }
          }
          Section("Walking") {
            Toggle("Evening step nudge", isOn: $draft.rules.stepsEnabled)
            Stepper(
              "Daily steps floor: \(draft.rules.stepsFloor)", value: $draft.rules.stepsFloor,
              in: 1000...50000, step: 500)
            minutePicker("Nudge after", value: $draft.rules.nudgeMinute)
            Text(
              "10–20 min walk after your next meal. Recent meal entries let the nudge prefer within 30 min after a meal. Missing steps do not trigger a false low-step warning."
            ).font(.caption).foregroundStyle(Ink.muted)
          }
          Section("Strength") {
            Toggle("Priority-muscle volume warnings", isOn: $draft.rules.volumeWarnings)
            Stepper(
              "Minimum hard sets/week: \(draft.rules.priorityMinimum)",
              value: $draft.rules.priorityMinimum, in: 1...30)
            ForEach(PriorityMuscle.allCases, id: \.self) { m in
              Toggle(
                m.rawValue,
                isOn: Binding(
                  get: { draft.rules.priorities.contains(m) },
                  set: { on in
                    draft.rules.priorities.removeAll { $0 == m }
                    if on { draft.rules.priorities.append(m) }
                  }))
            }
            Toggle("Progression hints & stall flags", isOn: $draft.rules.progressionEnabled)
            Stepper(
              "Stall threshold: \(draft.rules.stallWeeks) weeks", value: $draft.rules.stallWeeks,
              in: 2...26)
            Text(
              "Suggestions never modify the plan automatically. Use the plan editor to accept a change."
            ).font(.caption).foregroundStyle(Ink.muted)
          }
          Section("Timing & cardio") {
            Toggle("Flag late hard sessions", isOn: $draft.rules.lateEnabled)
            minutePicker("Hard sessions should end by", value: $draft.rules.lateMinute)
            Toggle(
              "Flat walking pad is walking below HR threshold", isOn: $draft.rules.walkingPadRule)
            TextField("Walking-only HR cutoff", value: $draft.rules.walkingHR, format: .number)
            Text(
              "Watch type codes do not include incline. A walking-pad plan with zero incline and low/unknown HR earns walking only; incline treadmill plans count as cardio. HR intensity is an age-based estimate."
            ).font(.caption).foregroundStyle(Ink.muted)
          }
          Section("Daily step blocks") {
            ForEach($draft.stepBlocks) { $block in
              VStack(alignment: .leading) {
                TextField("Block name", text: $block.title)
                HStack {
                  Picker("Day", selection: $block.day) {
                    ForEach(StepDayKind.allCases, id: \.self) {
                      Text($0.rawValue.capitalized).tag($0)
                    }
                  }
                  Picker("Timing", selection: $block.anchor) {
                    ForEach(StepAnchor.allCases, id: \.self) {
                      Text($0.rawValue.capitalized).tag($0)
                    }
                  }
                }
                HStack {
                  TextField("Steps", value: $block.steps, format: .number)
                  TextField("Minutes", value: $block.minutes, format: .number)
                  Button("Remove") { draft.stepBlocks.removeAll { $0.id == block.id } }
                }
              }
            }
            Button("Add block") {
              draft.stepBlocks.append(
                .init(title: "Walk", day: .every, anchor: .dinner, steps: 1500, minutes: 15))
            }
            Toggle("Treadmill rails hint", isOn: $draft.railsHintEnabled)
            TextField(
              "Low-step threshold (steps / min)", value: $draft.railsStepsPerMinute, format: .number
            )
          }
          Section("Calories") {
            Toggle("Show watch-calorie caution", isOn: $draft.rules.calorieCaution)
            Text(
              "Calories are informational. Turning off this note never enables eat-back recommendations."
            ).font(.caption).foregroundStyle(Ink.muted)
          }
        }.formStyle(.grouped)
      }
      if let error = formError ?? store.error { Text(error).foregroundStyle(.orange) }
    }.padding(24).frame(width: 700, height: 700).onAppear {
      draft = store.archive
      fat = draft.goal.targetFat.map { String($0) } ?? ""
      weight = draft.goal.targetWeight.map { String($0) } ?? ""
      age = draft.age.map { String($0) } ?? ""
      height = draft.heightCM.map { String($0) } ?? ""
      due = draft.goal.targetDate ?? Date().addingTimeInterval(90 * 86400)
      hasDue = draft.goal.targetDate != nil
    }
  }
  private func minutePicker(_ title: String, value: Binding<Int>) -> some View {
    HStack {
      Text(title)
      Spacer()
      DatePicker(
        title,
        selection: Binding(
          get: {
            calendar.date(
              bySettingHour: value.wrappedValue / 60, minute: value.wrappedValue % 60, second: 0,
              of: Date())!
          },
          set: {
            value.wrappedValue =
              calendar.component(.hour, from: $0) * 60 + calendar.component(.minute, from: $0)
          }), displayedComponents: .hourAndMinute
      ).labelsHidden().environment(\.locale, Locale(identifier: "en_US_POSIX"))
    }
  }
  private func save() {
    guard fat.isEmpty || Double(fat) != nil, weight.isEmpty || Double(weight) != nil,
      age.isEmpty || Int(age) != nil, height.isEmpty || Double(height) != nil
    else {
      formError =
        "Enter numeric goal values and a whole-number age, or leave optional fields blank."
      return
    }
    draft.goal.targetFat = Double(fat)
    draft.goal.targetWeight = Double(weight)
    draft.goal.targetDate = hasDue ? due : nil
    draft.age = Int(age)
    draft.heightCM = Double(height)
    if store.save(draft) { dismiss() }
  }
}
struct TrainingPlanEditor: View {
  @ObservedObject var store: TrainingStore
  @Environment(\.dismiss) var dismiss
  @State private var draft = TrainingArchive()
  @State private var weekday = 2
  @State private var exercise: TrainingExercise?
  private var index: Int? { draft.plan.firstIndex { $0.weekday == weekday } }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Weekly training plan").font(.title2)
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Save plan") { if store.save(draft) { dismiss() } }.keyboardShortcut(.defaultAction)
      }
      Picker("Weekday", selection: $weekday) {
        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in
          Text(Calendar.current.weekdaySymbols[d - 1]).tag(d)
        }
      }.pickerStyle(.segmented)
      ScrollView {
        if let i = index {
          sessionForm(i)
        } else {
          Button("Add session for this day") {
            var s = TrainingSession()
            s.weekday = weekday
            draft.plan.append(s)
          }.padding()
        }
        Divider()
        HStack {
          Text("Exercise library").font(.headline)
          Spacer()
          Button("New exercise") { exercise = TrainingExercise() }
        }
        ForEach(draft.exercises) { e in
          HStack {
            VStack(alignment: .leading) {
              Text(e.name)
              Text(e.muscles.map(\.title).joined(separator: ", ")).font(.caption).foregroundStyle(
                Ink.muted)
            }
            Spacer()
            Button("Edit") { exercise = e }
            if let i = index {
              Button("Add to session") {
                if !draft.plan[i].exercises.contains(e.id) { draft.plan[i].exercises.append(e.id) }
              }.disabled(draft.plan[i].exercises.contains(e.id))
            }
          }.padding(.vertical, 6)
        }
      }
      if let error = store.error { Text(error).foregroundStyle(.orange) }
    }.padding(24).frame(width: 780, height: 680).onAppear { draft = store.archive }.sheet(
      item: $exercise
    ) { e in
      TrainingExerciseEditor(exercise: e) { new in
        if let i = draft.exercises.firstIndex(where: { $0.id == new.id }) {
          draft.exercises[i] = new
        } else {
          draft.exercises.append(new)
        }
      }
    }
  }
  private func sessionForm(_ i: Int) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      TextField("Session name", text: $draft.plan[i].name)
      Picker("Type", selection: $draft.plan[i].kind) {
        ForEach(TrainingKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
      }
      Stepper(
        "Rest: \(draft.plan[i].restSeconds) s", value: $draft.plan[i].restSeconds, in: 0...600,
        step: 15)
      TextField("Planned minutes", value: $draft.plan[i].minutes, format: .number)
      if draft.plan[i].kind == .cardio {
        TextField(
          "Cardio type (incline treadmill / walking pad / other)", text: $draft.plan[i].cardioType)
        HStack {
          TextField("Minutes", value: $draft.plan[i].minutes, format: .number)
          TextField("Incline", value: $draft.plan[i].incline, format: .number)
          TextField("Speed", value: $draft.plan[i].speed, format: .number)
        }
      }
      ForEach(Array(draft.plan[i].exercises.enumerated()), id: \.element) { position, id in
        HStack {
          Text("\(position+1). \(draft.exercises.first{$0.id==id}?.name ?? "Exercise")")
          Spacer()
          Button("↑") { draft.plan[i].exercises.swapAt(position, position - 1) }.disabled(
            position == 0)
          Button("↓") { draft.plan[i].exercises.swapAt(position, position + 1) }.disabled(
            position == draft.plan[i].exercises.count - 1)
          if position + 1 < draft.plan[i].exercises.count {
            Toggle(
              "Pair with next",
              isOn: Binding(
                get: {
                  draft.plan[i].supersets.contains {
                    Set($0) == Set([id, draft.plan[i].exercises[position + 1]])
                  }
                },
                set: { on in
                  let next = draft.plan[i].exercises[position + 1]
                  draft.plan[i].supersets.removeAll { $0.contains(id) || $0.contains(next) }
                  if on { draft.plan[i].supersets.append([id, next]) }
                })
            ).font(.caption)
          }
          Button("Remove") {
            draft.plan[i].supersets.removeAll { $0.contains(id) }
            draft.plan[i].exercises.removeAll { $0 == id }
          }
        }
      }
      Button("Remove this day", role: .destructive) { draft.plan.remove(at: i) }
    }.padding(.vertical, 8)
  }
}
struct TrainingExerciseEditor: View {
  let exercise: TrainingExercise
  var save: (TrainingExercise) -> Void
  @State private var draft = TrainingExercise()
  @State private var error: String?
  @State private var demos = false
  @Environment(\.dismiss) var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Exercise details").font(.title2)
      TextField("Name", text: $draft.name)
      TextField("Equipment", text: $draft.equipment)
      HStack {
        Stepper("Sets \(draft.sets)", value: $draft.sets, in: 1...20)
        TextField("Min reps", value: $draft.minReps, format: .number)
        TextField("Max reps", value: $draft.maxReps, format: .number)
        TextField("Starting kg", value: $draft.startingWeight, format: .number)
      }
      Toggle("Assisted movement (less assistance is progress)", isOn: $draft.assisted)
      Toggle("Compound movement", isOn: $draft.compound)
      Toggle("Timed holds (seconds instead of reps)", isOn: $draft.timed)
      Text("Priority muscles · explicit tags avoid assuming all chest work is upper chest").font(
        .caption)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))]) {
        ForEach(PriorityMuscle.allCases, id: \.self) { m in
          Toggle(
            m.rawValue,
            isOn: Binding(
              get: { draft.priorityTags.contains(m) },
              set: { on in
                draft.priorityTags.removeAll { $0 == m }
                if on { draft.priorityTags.append(m) }
              })
          ).font(.system(size: 11))
        }
      }
      HStack {
        Button(draft.animationID == nil ? "Choose workout artwork" : "Change workout artwork") {
          demos = true
        }
        if draft.animationID != nil { Button("Remove artwork") { draft.animationID = nil } }
      }
      Text("Muscle tags").font(.headline)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], alignment: .leading) {
        ForEach(MuscleRegion.allCases, id: \.self) { m in
          Toggle(
            m.title,
            isOn: Binding(
              get: { draft.muscles.contains(m) },
              set: { on in
                draft.muscles.removeAll { $0 == m }
                if on { draft.muscles.append(m) }
              })
          ).toggleStyle(.checkbox).font(.system(size: 11))
        }
      }
      if let error { Text(error).foregroundStyle(.orange) }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Save exercise") {
          var a = TrainingArchive()
          a.exercises = [draft]
          do {
            try a.validate()
            save(draft)
            dismiss()
          } catch { self.error = error.localizedDescription }
        }.keyboardShortcut(.defaultAction)
      }
    }.padding(24).frame(width: 650).onAppear { draft = exercise }.sheet(isPresented: $demos) {
      ExerciseDemoSheet(initialID: draft.animationID) { draft.animationID = $0 }
    }
  }
}
struct SetLogEditor: View {
  @ObservedObject var store: TrainingStore
  let exercise: TrainingExercise
  let calendar: Calendar
  @State private var date = Date()
  @State private var sets: [TrainingSet] = []
  @Environment(\.dismiss) var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(exercise.name).font(.title2)
      HStack {
        DatePicker("Session date", selection: $date, in: ...Date(), displayedComponents: .date)
        DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute).environment(
          \.locale, Locale(identifier: "en_US_POSIX"))
      }
      HStack {
        Text("Weight kg").frame(width: 100)
        Text(exercise.timed ? "Seconds" : "Reps").frame(width: 70)
        Text("RPE (optional)").frame(width: 105)
        Text("Hard set")
      }.font(.caption).foregroundStyle(Ink.muted)
      ScrollView {
        ForEach(sets.indices, id: \.self) { i in
          HStack {
            TextField("kg", value: $sets[i].weight, format: .number.precision(.fractionLength(2)))
              .frame(width: 100)
            TextField(exercise.timed ? "Seconds" : "Reps", value: $sets[i].reps, format: .number)
              .frame(width: 70)
            TextField(
              "RPE",
              text: Binding(
                get: { sets[i].rpe.map { String($0) } ?? "" }, set: { sets[i].rpe = Double($0) })
            ).frame(width: 105)
            Toggle("Hard set", isOn: $sets[i].hard).labelsHidden()
            Button("Remove") { sets.remove(at: i) }
          }
        }
      }.frame(maxHeight: 260)
      HStack {
        Button("Add set") {
          sets.append(sets.last ?? .init(weight: exercise.startingWeight, reps: exercise.minReps))
        }.disabled(sets.count >= 30)
        Button("Same as last") {
          if let last = store.archive.lastLog(exercise.id, before: date) { sets = last.sets }
        }
        Spacer()
      }
      Text("Tab moves between fields. Command–Return saves. Mark warm-up sets as not hard.").font(
        .caption
      ).foregroundStyle(Ink.muted)
      if let error = store.error { Text(error).foregroundStyle(.orange) }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Save sets") {
          let log = LiftLog(
            exerciseID: exercise.id, date: date, sets: sets, muscles: exercise.muscles,
            priorityTags: exercise.priorityTags)
          if store.change({ $0.logs.append(log) }) { dismiss() }
        }.keyboardShortcut(.return, modifiers: .command)
      }
    }.padding(24).frame(width: 580).onAppear {
      sets = Array(
        repeating: .init(weight: exercise.startingWeight, reps: exercise.minReps),
        count: exercise.sets)
    }
  }
}
struct ExerciseHistoryView: View {
  @ObservedObject var store: TrainingStore
  let exercise: TrainingExercise
  let calendar: Calendar
  @Environment(\.dismiss) var dismiss
  private var logs: [LiftLog] {
    store.archive.logs.filter { $0.exerciseID == exercise.id }.sorted { $0.date < $1.date }
  }
  private var all: [TrainingSet] { logs.flatMap(\.sets) }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(exercise.name).font(.title2)
        Spacer()
        Button("Done") { dismiss() }
      }
      if exercise.timed {
        Text("Best hold: \(all.map(\.reps).max() ?? 0) s · no estimated 1RM for timed holds").font(
          .system(size: 12))
      } else if exercise.assisted {
        Text(
          "Best assistance: \(bodyNumber(all.map(\.weight).min(),unit:" kg")) · lower is progress. External-load volume shown below; e1RM is not valid for assisted moves."
        ).font(.system(size: 12))
      } else {
        Text(
          "Best set: \(all.max{$0.epley<$1.epley}.map{"\(bodyNumber($0.weight)) kg × \($0.reps)"} ?? "—") · Epley estimated 1RM: \(bodyNumber(all.map(\.epley).max(),unit:" kg"))"
        ).font(.system(size: 12))
      }
      Chart(logs) { l in
        BarMark(
          x: .value("Session", l.date),
          y: .value(
            exercise.timed ? "Seconds" : "Volume",
            exercise.timed
              ? Double(l.sets.map(\.reps).reduce(0, +)) : l.sets.map(\.volume).reduce(0, +))
        ).foregroundStyle(Ink.accent)
      }.frame(height: 180)
      ScrollView {
        ForEach(logs.reversed()) { l in
          HStack {
            Text(
              "\(l.date.formatted(.dateTime.day().month(.abbreviated).year())) · \(bodyClock(l.date,calendar:calendar))"
            )
            Text(l.sets.map { "\(bodyNumber($0.weight)) × \($0.reps)" }.joined(separator: " · "))
            if isPR(l) { Text("PR").foregroundStyle(.mint) }
            Spacer()
            Button("Delete log", role: .destructive) {
              store.change { $0.logs.removeAll { $0.id == l.id } }
            }
          }.font(.system(size: 11)).padding(.vertical, 6)
        }
      }
      Text("Estimated 1RM is a trend aid, not a tested maximum. PRs compare with earlier sessions.")
        .font(.caption).foregroundStyle(Ink.muted)
    }.padding(24).frame(width: 720, height: 560)
  }
  private func isPR(_ l: LiftLog) -> Bool {
    let previous = logs.filter { $0.date < l.date }.flatMap(\.sets)
    if exercise.timed { return (l.sets.map(\.reps).max() ?? 0) > (previous.map(\.reps).max() ?? 0) }
    if exercise.assisted {
      return (l.sets.map(\.weight).min() ?? .infinity) < (previous.map(\.weight).min() ?? .infinity)
    }
    return (l.sets.map(\.epley).max() ?? 0) > (previous.map(\.epley).max() ?? 0)
  }
}
