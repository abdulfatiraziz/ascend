import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AscendCore

struct MealsView: View {
    @ObservedObject var store: TrackerStore
    @ObservedObject var meals: MealController
    @State private var day: String
    init(store: TrackerStore) { self.store = store; meals = store.meals; _day = State(initialValue: store.today) }
    private var entries: [MealEntry] { store.document.meals.on(day) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Kicker("Photo → Claude estimate → your review")
                        Text("Snap meals in Ascend Bridge or drop photos here. Confirmed meals set your Calorie and Protein check-ins for that day.").font(.system(size: 12)).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    Button { day = store.engine.adding(-1, to: day) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).accessibilityLabel("Previous day")
                    DatePicker("Meal date", selection: Binding(get: { store.engine.date(day) ?? Date() }, set: { day = store.engine.key($0) }), in: ...Date(), displayedComponents: .date).labelsHidden().fixedSize()
                    Button { day = store.engine.adding(1, to: day) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).disabled(day >= store.today).accessibilityLabel("Next day")
                    Button("Today") { day = store.today }.buttonStyle(.plain).font(.system(size: 12))
                    PrimaryButton(label: "Add photo…") { choose() }
                }
                totals
                if entries.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No meals for this day.").font(.system(size: 18, weight: .semibold))
                        Text("On your phone: open Ascend Bridge → Take meal photo, add a short note like “2 rotis, dal”, then Sync to Mac on the same Wi-Fi. Or drag a food photo onto this window.").font(.system(size: 12)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading).panel()
                }
                ForEach(entries) { MealCard(store: store, meals: meals, meal: $0) }
                Text("Photo estimates are rough, often 20–30% off, mostly from oil and portion size. Adjust the numbers before confirming. Photos stay on this Mac; each estimate sends that photo and its note to Claude through your personal Claude profile.").font(.system(size: 11)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            }.padding(.bottom, 10)
        }
        .dropDestination(for: URL.self) { urls, _ in add(urls.filter(ChatPhotos.isImage)); return true }
        .onChange(of: store.today) { old, new in if day == old { day = new } }
    }
    private var totals: some View {
        let t = store.document.meals.totals(day), habits = store.document.mealHabits
        let kcalLimit = habits.calories?.latest.target?.maximum, proteinGoal = habits.protein?.latest.target?.minimum
        return HStack(spacing: 28) {
            stat("Calories", t.kcal, unit: "kcal", target: kcalLimit.map { "≤ \(Int($0.rounded()))" }, good: kcalLimit.map { t.kcal <= $0 })
            stat("Protein", t.protein, unit: "g", target: proteinGoal.map { "≥ \(Int($0))" }, good: proteinGoal.map { t.protein >= $0 })
            stat("Carbs", t.carbs, unit: "g", target: nil, good: nil)
            stat("Fat", t.fat, unit: "g", target: nil, good: nil)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(t.confirmed) confirmed").font(.system(size: 12))
                if t.pending > 0 { Text("\(t.pending) to review").font(.system(size: 11)).foregroundStyle(Ink.accent) }
            }
        }.panel(padding: 16)
    }
    private func stat(_ title: String, _ value: Double, unit: String, target: String?, good: Bool?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Kicker(title)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(value.rounded()))").font(.system(size: 24, weight: .semibold)).foregroundStyle(good == false ? Color.orange : Color.white)
                Text(unit).font(.system(size: 10)).foregroundStyle(Ink.muted)
            }
            if let target { Text("Target \(target)").font(.system(size: 10)).foregroundStyle(Ink.muted) }
        }
    }
    private func choose() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true; panel.message = "Choose meal photos"
        if panel.runModal() == .OK { add(panel.urls) }
    }
    /// Uses each file's creation time (not later than now) as the meal time.
    private func add(_ urls: [URL]) {
        for url in urls.prefix(10) {
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            do { if let meal = try store.addMeal(photo: url, takenAt: created, note: "", source: "mac") { meals.enqueue(meal.id); day = meal.day } }
            catch { store.notice = error.localizedDescription }
        }
    }
}
private struct MealCard: View {
    @ObservedObject var store: TrackerStore
    @ObservedObject var meals: MealController
    var meal: MealEntry
    @State private var kcal = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0
    @State private var note = ""
    @State private var confirmDelete = false
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            PhotoThumbnail(url: store.mealPhotoURL(meal), size: 120)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(meal.estimate?.name ?? (meals.estimating.contains(meal.id) ? "Estimating…" : meal.error == nil ? "Waiting to estimate" : "Estimate failed")).font(.system(size: 15, weight: .semibold))
                    if meal.confirmed { Label("Logged", systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Ink.accent) }
                    Spacer()
                    Text("\(Date(timeIntervalSince1970: meal.takenAt).formatted(date: .omitted, time: .shortened)) · \(meal.source == "phone" ? "Phone" : "Mac")").font(.system(size: 11)).foregroundStyle(Ink.muted)
                }
                if let estimate = meal.estimate {
                    Text("≈ \(Int(estimate.kcal)) kcal (\(Int(estimate.kcalLow))–\(Int(estimate.kcalHigh))) · \(estimate.confidence) confidence" + (estimate.items.isEmpty ? "" : " · " + estimate.items.joined(separator: ", "))).font(.system(size: 11)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    if !estimate.notes.isEmpty { Text(estimate.notes).font(.system(size: 11)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true) }
                }
                if meals.estimating.contains(meal.id) { ProgressView().controlSize(.small) }
                if let error = meal.error {
                    HStack { Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true); Button("Retry") { meals.retry(meal.id) }.font(.system(size: 11)) }
                }
                TextField("Note (for example: 2 rotis, dal, cooked in ghee)", text: $note).textFieldStyle(.roundedBorder).font(.system(size: 12)).disabled(meal.confirmed)
                HStack(spacing: 10) {
                    field("kcal", $kcal); field("Protein g", $protein); field("Carbs g", $carbs); field("Fat g", $fat)
                }.disabled(meal.confirmed)
                HStack {
                    Button("Delete…") { confirmDelete = true }.font(.system(size: 11))
                    if meal.estimate != nil && !meal.confirmed { Button("Re-estimate") { saveNote(); meals.retry(meal.id) }.font(.system(size: 11)).disabled(meals.estimating.contains(meal.id)) }
                    Spacer()
                    if meal.confirmed { Button("Edit") { store.reopenMeal(meal.id) }.font(.system(size: 12)) }
                    else { PrimaryButton(label: "Confirm meal") { store.confirmMeal(meal.id, kcal: kcal, protein: protein, carbs: carbs, fat: fat, note: note) }.disabled(meal.estimate == nil && kcal == 0) }
                }
            }
        }.panel(padding: 14)
            .onAppear(perform: load)
            .onChange(of: meal.estimate) { _, _ in if !meal.confirmed { load() } }
            .confirmationDialog("Delete this meal?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete meal", role: .destructive) { store.deleteMeal(meal.id) }; Button("Cancel", role: .cancel) {}
            } message: { Text(meal.confirmed ? "Its calories and protein are removed from that day's totals. Undo is available until your next edit." : "Undo is available until your next edit.") }
    }
    private func field(_ label: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10)).foregroundStyle(Ink.muted)
            TextField(label, value: value, format: .number.precision(.fractionLength(0))).textFieldStyle(.roundedBorder).frame(width: 82).font(.system(size: 12))
        }
    }
    private func load() {
        let v = meal.values
        kcal = v.kcal.rounded(); protein = v.protein.rounded(); carbs = v.carbs.rounded(); fat = v.fat.rounded(); note = meal.note
    }
    /// A changed note is saved before re-estimating so Claude sees it.
    private func saveNote() {
        guard note != meal.note else { return }
        store.updateMealNote(meal.id, note)
    }
}
