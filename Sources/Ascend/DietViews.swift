import AscendCore
import SwiftUI

struct DietDashboard: View {
    @ObservedObject var store: TrackerStore
    let day: String
    @State private var editing = false
    private var plan: DietPlan? { store.document.diet }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Kicker("YOUR DIET PLAN")
                    Text(plan == nil ? "Give your meals a rhythm." : "Plan the day. Keep the week flexible.").font(.system(size: 20, weight: .semibold))
                }
                Spacer()
                if plan?.sourceNoteID != nil { Button("Pinned plan ↗") { store.pendingScreen = "Notes" } }
                Button(plan == nil ? "Set up plan…" : "Edit plan…") { editing = true }
            }
            if let plan {
                budget
                let totals = store.document.meals.totals(day)
                if let goal = store.document.mealHabits.protein.flatMap({ store.engine.target(for: $0, on: day)?.minimum }) {
                    HStack { Text("Protein left today").foregroundStyle(Ink.muted); Spacer(); Text("\(max(0, goal-totals.protein).pretty) g").fontWeight(.semibold) }.font(.system(size: 13))
                }
                if day == store.today, let next = nextSlot(plan) { Label("Next: \(next.name) · \(HealthReport.clock(next.startMinute))", systemImage: "clock").font(.system(size: 12)).foregroundStyle(Ink.accent) }
                ForEach(plan.slots.sorted { $0.startMinute < $1.startMinute }) { slot in
                    DietSlotRow(slot: slot, meals: assigned(slot, plan: plan))
                }
                if !plan.sweetOptions.isEmpty {
                    Text("Sweet choices · " + plan.sweetOptions.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                }
                let outside = plan.unplannedSweets(store.document.meals, day: day, calendar: store.engine.calendar)
                if !outside.isEmpty {
                    Label("\(outside.count) sweet outside the planned window · the linked sweets habit counts as incomplete. Editing or deleting the tagged meal recalculates this.", systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Text("Tag meals as Sweet or Café swap below. Only confirmed meals fill slots. A café swap replaces the breakfast slot; all food still counts in the calorie total.").font(.system(size: 10)).foregroundStyle(Ink.muted)
                Divider()
                GramCalculator(store: store, day: day, references: plan.references)
            } else {
                Text("Add editable meal windows, weekday calorie budgets, food references and weight checkpoints. Your existing habits and pinned notes remain the source of your plan.").font(.system(size: 12)).foregroundStyle(Ink.muted)
            }
        }.panel(padding: 20)
        .sheet(isPresented: $editing) { DietPlanEditor(store: store) }
    }
    private var budget: some View {
        Group {
            if let b = DietBudget.build(document: store.document, day: day) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 30) {
                        dietStat("WEEKLY BUDGET", b.planned.pretty + " kcal")
                        dietStat("LOGGED", b.consumed.pretty + " kcal")
                        dietStat(b.remaining >= 0 ? "REMAINING THIS WEEK" : "OVER THIS WEEK", abs(b.remaining).pretty + " kcal")
                    }
                    Text("Week of \(b.start) · \(b.loggedDays)/7 days have food or calorie logs · \(b.targetDays)/7 days have targets. Remaining uses recorded intake; unlogged food is unknown.").font(.system(size: 10)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                }.padding(14).background(Ink.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    private func dietStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Kicker(label); Text(value).font(.system(size: 19, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func assigned(_ slot: DietSlot, plan: DietPlan) -> [MealEntry] {
        let matches = store.document.meals.on(day).filter { $0.confirmed && plan.slot(for: $0, calendar: store.engine.calendar)?.id == slot.id }
        if slot.cafeReplacement, matches.contains(where: { $0.dietKind == .cafe }) { return matches.filter { $0.dietKind == .cafe } }
        return matches
    }
    private func nextSlot(_ plan: DietPlan) -> DietSlot? {
        let minute = store.engine.minute(Date())
        return plan.slots.sorted { $0.startMinute < $1.startMinute }.first { $0.endMinute > minute && assigned($0, plan: plan).isEmpty }
    }
}
private struct DietSlotRow: View {
    let slot: DietSlot
    let meals: [MealEntry]
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: meals.isEmpty ? "circle" : "checkmark.circle.fill").foregroundStyle(meals.isEmpty ? Ink.muted : Ink.accent).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(slot.name).fontWeight(.medium); Text("\(HealthReport.clock(slot.startMinute))–\(HealthReport.clock(slot.endMinute))").foregroundStyle(Ink.muted) }.font(.system(size: 12))
                Text(slot.portion).font(.system(size: 11)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                if meals.contains(where: { $0.dietKind == .cafe }) { Text("Breakfast replaced by café meal").font(.system(size: 10)).foregroundStyle(Ink.accent) }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                Text("Plan \(slot.kcal.map { $0.pretty } ?? "—") kcal · \(slot.protein.map { $0.pretty } ?? "—") g P").foregroundStyle(Ink.muted)
                if !meals.isEmpty { Text("Logged \(meals.reduce(0) { $0+$1.values.kcal }.pretty) kcal · \(meals.reduce(0) { $0+$1.values.protein }.pretty) g P").foregroundStyle(Ink.accent) }
            }.font(.system(size: 10)).fixedSize()
        }.padding(.vertical, 7)
    }
}
private struct GramCalculator: View {
    @ObservedObject var store: TrackerStore
    let day: String
    let references: [FoodReference]
    @State private var input = ""
    @State private var kind: MealDietKind = .standard
    @State private var time = Date()
    @State private var resultMessage: String?
    private var calculation: FoodCalculation? { try? FoodCalculation.parse(input, references: references) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Weigh it. Log it.").font(.system(size: 16, weight: .semibold)); Spacer(); Text("Your editable references per 100 g").font(.system(size: 10)).foregroundStyle(Ink.muted) }
            if references.isEmpty { Text("Add food references in Edit plan to use the gram calculator.").font(.system(size: 12)).foregroundStyle(Ink.muted) }
            else {
                Text(references.map(\.name).joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(Ink.muted)
                TextField("rice 85 g · +1 tbsp oil · oil spray ×4", text: $input).textFieldStyle(.roundedBorder)
                HStack {
                    Picker("Type", selection: $kind) { ForEach(MealDietKind.allCases, id: \.self) { Text($0.label).tag($0) } }.frame(width: 145)
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute).labelsHidden().environment(\.locale, Locale(identifier: "en_US"))
                    Spacer()
                    if let c = calculation { Text("\(c.totals.kcal.pretty) kcal · \(c.totals.protein.pretty) g protein").font(.system(size: 12, weight: .medium)) }
                    Button("Log portion") { log() }.disabled(calculation == nil)
                }
                if !input.isEmpty && calculation == nil {
                    Text(parseError).font(.system(size: 11)).foregroundStyle(.orange)
                }
                Text("References use the nutrient numbers you enter; fill missing nutrient values before relying on macro totals. Oil sprays require your measured grams per spray. Saving a portion creates one confirmed meal; Undo is available. Add oil separately only when it is not already included in a meal estimate.").font(.system(size: 10)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                if let resultMessage { Text(resultMessage).font(.system(size: 11)).foregroundStyle(Ink.accent) }
            }
        }
    }
    private var parseError: String { do { _ = try FoodCalculation.parse(input, references: references); return "" } catch { return error.localizedDescription } }
    private func log() {
        guard let c = calculation, let date = store.engine.date(day) else { return }
        let cal = store.engine.calendar
        guard let when = cal.date(bySettingHour: cal.component(.hour, from: time), minute: cal.component(.minute, from: time), second: 0, of: date), when <= Date() else { resultMessage = "Choose a time that has already passed."; return }
        if store.addCalculatedMeal(c, at: when, kind: kind) { input = ""; resultMessage = "Portion logged." }
    }
}
struct DietCheckpointStatus: View {
    @ObservedObject var store: TrackerStore
    @ObservedObject var measurements: BodyMeasurementStore
    var body: some View {
        Group {
            if let plan = store.document.diet, !plan.checkpoints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker("DIET CHECKPOINTS · ORANGE DIAMONDS ON CHART")
                    Text(status(plan)).font(.system(size: 14, weight: .medium))
                    Text("Compared with the average of daily weigh-ins in the seven days ending at the latest checkpoint. Two separate weigh-in dates are needed. Targets are editable in Meals → Edit plan.").font(.system(size: 11)).foregroundStyle(Ink.muted)
                }.panel(padding: 16)
            }
        }
    }
    private func status(_ plan: DietPlan) -> String {
        DietCheckpointReport.build(plan: plan, records: measurements.archive.records, day: store.today, calendar: store.engine.calendar).label
    }
}
