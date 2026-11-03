import AscendCore
import SwiftUI

struct BodyMaintenanceCard: View {
  @ObservedObject var store: TrackerStore
  @ObservedObject var training: TrainingStore
  @ObservedObject var measurements: BodyMeasurementStore
  @State private var window = 14
  private var report: BodyMaintenanceReport {
    .build(
      training: training.archive, records: measurements.archive.records, document: store.document,
      now: Date(), window: window)
  }
  private func calories(_ value: Double?) -> String {
    value.map { "\(Int(BodyMaintenanceReport.round($0)).formatted())" } ?? "—"
  }
  var body: some View {
    let r = report
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        VStack(alignment: .leading, spacing: 6) {
          Kicker("YOUR MAINTENANCE")
          Text(r.headline).font(.system(size: 23, weight: .semibold)).tracking(-0.4)
        }
        Spacer()
        Picker("Maintenance window", selection: $window) {
          Text("14 days").tag(14)
          Text("28 days").tag(28)
        }.labelsHidden().pickerStyle(.segmented).frame(width: 170)
      }
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), spacing: 12, alignment: .topLeading), count: 3),
        alignment: .leading, spacing: 12
      ) {
        measured(r)
        formula(r)
        device(r)
      }
      if let deficit = r.deficit, let pace = r.predictedLossPerWeek, let target = r.currentTarget {
        Text(
          "At today’s \(Int(target.rounded()).formatted()) kcal target: about \(Int(abs(deficit).rounded()).formatted()) kcal/day \(deficit>=0 ? "deficit":"surplus") · \(String(format:"%.2f",abs(pace))) kg/week \(pace>=0 ? "loss":"gain"). Based on \(r.measured == nil ? "the formula estimate":"your intake/weight estimate")."
        ).font(.system(size: 12)).foregroundStyle(Ink.muted)
      }
      if let target = r.suggestedTarget, let pace = r.goalPace {
        Text(
          "Planning target to review: about \(Int(target).formatted()) kcal/day for \(String(format:"%.2f",pace)) kg/week loss. Your habit target has not changed."
        ).font(.system(size: 13)).foregroundStyle(Ink.accent)
      }
      if let note = r.suggestionNote { Text(note).font(.system(size: 12)).foregroundStyle(.orange) }
      if let lazy = r.lazyDay, let active = r.activeDay {
        HStack(spacing: 24) {
          Label("Quiet-day formula ≈ \(calories(lazy))", systemImage: "chair")
          Label("Active-day formula ≈ \(calories(active))", systemImage: "figure.walk")
        }.font(.system(size: 11)).foregroundStyle(Ink.muted)
      }
      Text(
        "These are estimates. The 7,700 kcal/kg approximation is affected by water shifts and adaptation. Activity multipliers are heuristics. Watch calories never change the suggested target or justify eating back activity calories."
      ).font(.system(size: 11)).foregroundStyle(Ink.muted).fixedSize(
        horizontal: false, vertical: true)
      DisclosureGroup("Review full-day logging · previous \(window) closed days") {
        VStack(alignment: .leading, spacing: 8) {
          Text(
            "A full day has at least two confirmed meals and 1,200 kcal, or your explicit completion mark. Only full days enter the intake average; missing days are not zero. Mark a day complete only after reviewing its whole intake. The logging threshold is not an intake recommendation."
          ).font(.system(size: 11)).foregroundStyle(Ink.muted)
          ForEach(r.days.reversed()) { day in
            HStack {
              Text(day.key).font(.system(size: 11, design: .monospaced))
              Text("\(day.meals) meals · \(Int(day.calories.rounded()).formatted()) kcal").font(
                .system(size: 11))
              Spacer()
              if day.complete { Text("Full day").font(.system(size: 10)).foregroundStyle(.mint) }
              Toggle(
                "Mark complete",
                isOn: Binding(
                  get: { day.marked },
                  set: { on in
                    training.change { a in
                      var set = Set(a.completedNutritionDays ?? [])
                      if on { set.insert(day.key) } else { set.remove(day.key) }
                      a.completedNutritionDays = set.sorted()
                    }
                  })
              ).font(.system(size: 11))
            }
          }
        }.padding(.top, 10)
      }
      if let error = training.error { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
    }.panel(padding: 22)
  }
  private func tile(_ label: String, _ value: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(
        Ink.muted)
      Text(value).font(.system(size: 25, weight: .semibold)).monospacedDigit()
      Text(detail).font(.system(size: 11)).foregroundStyle(Ink.muted).fixedSize(
        horizontal: false, vertical: true)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(
      Ink.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
  }
  private func measured(_ r: BodyMaintenanceReport) -> some View {
    let detail =
      r.measured != nil
      ? "kcal/day · \(r.fullDays)/\(r.window) full days · \(r.weighIns) weigh-ins. Intake average uses complete days. Weight rate uses the actual spacing of the two seven-day averages."
      : r.missing.joined(separator: " ")
    return tile("MEASURED · FROM LOGS", calories(r.measured), detail)
  }
  private func formula(_ r: BodyMaintenanceReport) -> some View {
    let detail =
      r.formula.map { _ in
        "kcal/day · BMR \(calories(r.bmr)) × \(String(format:"%.3f",r.factor ?? 0)) · \(r.averageSteps.map{Int($0).formatted()} ?? "—") avg steps/day. Multiplier also reflects completed strength days."
      }
      ?? "Add \(r.formulaMissing.joined(separator:", ")) in Goal & coach settings or sync watch activity."
    return tile("FORMULA · MIFFLIN–ST JEOR", calories(r.formula), detail)
  }
  private func device(_ r: BodyMaintenanceReport) -> some View {
    tile(
      "DEVICE ESTIMATE · ACTIVE ONLY", calories(r.deviceActive),
      r.deviceActive == nil
        ? "No watch energy records in this window."
        : "active kcal/day · \(r.deviceDays) observed days. This archive contains active energy, not total energy; it is not a full-day maintenance estimate."
    )
  }
}
