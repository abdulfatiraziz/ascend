import SwiftUI
import AppKit
import AscendCore
import UniformTypeIdentifiers

@MainActor final class TrackerStore: ObservableObject {
    @Published private(set) var document: TrackerDocument
    @Published var today: String
    @Published var notice: String?
    @Published var pendingLog: UUID?
    @Published var pendingScreen: String?
    @Published private(set) var undoLabel: String?
    private var undoDocument: TrackerDocument?
    let notifications = ReminderService()
    let assistant: ChatController
    let meals: MealController
    let medsReader: MedController
    let phoneLink: PhoneLinkService
    @Published private(set) var lastUrgeID: UUID?
    @Published var pendingUrge: UUID?
    @Published private(set) var saveError: String?
    let storageURL: URL
    var engine: TrackerEngine { TrackerEngine(document: document) }
    private var timer: Timer?
    private var recoveryLocked = false

    init() {
        let folder = ProcessInfo.processInfo.environment["ASCEND_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ascend", isDirectory: true)
        storageURL = folder.appendingPathComponent("tracker.json")
        assistant = ChatController(folder: folder.appendingPathComponent("Claude", isDirectory: true))
        meals = MealController()
        medsReader = MedController()
        // Isolated QA data folders don't advertise on the network unless asked to.
        phoneLink = PhoneLinkService(enabled: ProcessInfo.processInfo.environment["ASCEND_DATA_DIR"] == nil || ProcessInfo.processInfo.environment["ASCEND_PHONE_LINK"] == "1")
        let initial = TrackerDocument.seeded(today: "2026-01-01", timeZoneID: TimeZone.current.identifier)
        let key = TrackerEngine(document: initial).key(Date())
        today = key
        document = TrackerDocument.seeded(today: key, timeZoneID: TimeZone.current.identifier)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: storageURL.path) {
                do { document = try Self.read(storageURL) }
                catch {
                    let originalError = error.localizedDescription
                    let backup = storageURL.appendingPathExtension("backup")
                    if let recovered = try? Self.read(backup) {
                        document = recovered
                        notice = "Recovered your last valid backup. The unreadable file is preserved. \(originalError)"
                        let recovery = folder.appendingPathComponent("unreadable-\(Int(Date().timeIntervalSince1970)).json")
                        try FileManager.default.copyItem(at: storageURL, to: recovery)
                        try FileManager.default.removeItem(at: storageURL)
                        save()
                    } else {
                        recoveryLocked = true
                        saveError = "Your data file could not be read. It has not been overwritten. Restore a valid backup from Settings. \(originalError)"
                    }
                }
            } else { save() }
        } catch { saveError = error.localizedDescription }
        today = engine.key(Date())
        notifications.refresh(document)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDay() }
        }
        meals.store = self; phoneLink.store = self; medsReader.store = self
        removeOrphanMealPhotos(); removeOrphanMedPhotos()
        meals.estimatePending(); medsReader.resumePending()
    }
    private static func read(_ url: URL) throws -> TrackerDocument {
        let doc = try JSONDecoder().decode(TrackerDocument.self, from: Data(contentsOf: url))
        try doc.validate()
        return doc
    }
    func refreshDay() {
        let key = engine.key(Date())
        if today != key { today = key; notifications.refresh(document) }
    }
    @discardableResult func save() -> Bool {
        guard !recoveryLocked else { notice = "Restore a valid backup before making changes. Your unreadable data file is preserved."; return false }
        do {
            try document.validate()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            if FileManager.default.fileExists(atPath: storageURL.path), (try? Self.read(storageURL)) != nil {
                let previous = try Data(contentsOf: storageURL)
                try previous.write(to: storageURL.appendingPathExtension("backup"), options: .atomic)
            }
            try data.write(to: storageURL, options: .atomic)
            saveError = nil
            notifications.refresh(document)
            return true
        } catch { saveError = "Changes could not be saved: \(error.localizedDescription)"; return false }
    }
    @discardableResult private func change(_ update: (inout TrackerDocument) -> Void) -> Bool {
        refreshDay()
        guard saveError == nil else { notice = saveError; return false }
        let previous = document
        var candidate = previous
        update(&candidate)
        do {
            try candidate.validate()
            if candidate == previous { return true }
            document = candidate
            guard save() else { document = previous; return false }
            undoDocument = nil; undoLabel = nil
            return true
        } catch { notice = error.localizedDescription; return false }
    }
    @discardableResult func toggle(_ habit: Habit, day: String) -> Bool {
        guard day <= today, (engine.isDue(habit, on: day) || engine.entry(for: habit, day: day) != nil), !document.restDays.contains(day) || habit.kind == .milestone else { return false }
        let done = engine.completed(habit, on: day)
        return change { $0.setEntry(CheckIn(habitID: habit.id, day: day, completed: !done)) }
    }
    @discardableResult func log(_ habit: Habit, value: Double?, day: String) -> Bool {
        guard day <= today, (engine.isDue(habit, on: day) || engine.entry(for: habit, day: day) != nil), !document.restDays.contains(day), value.map({ $0.isFinite && $0 >= 0 }) ?? true else { return false }
        return change {
            if let value { $0.setEntry(CheckIn(habitID: habit.id, day: day, value: value)) }
            else { $0.checkIns.removeAll { $0.habitID == habit.id && $0.day == day } }
        }
    }
    @discardableResult func setRestDay(_ day: String, rest: Bool) -> Bool {
        guard day <= today, engine.date(day) != nil else { return false }
        return change { if rest { $0.restDays.insert(day) } else { $0.restDays.remove(day) } }
    }
    @discardableResult private func protectedChange(label: String, _ update: (inout TrackerDocument) -> Void) -> Bool {
        guard saveError == nil else { notice = saveError; return false }
        do {
            let backup = storageURL.deletingLastPathComponent().appendingPathComponent("before-\(label)-\(today)-\(UUID().uuidString).json")
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: backup, options: .atomic)
            let previous = document
            if change(update) { undoDocument = previous; undoLabel = label.replacingOccurrences(of: "-", with: " "); return true }
            return false
        } catch { notice = "No changes made. The safety backup could not be saved: \(error.localizedDescription)"; return false }
    }
    func resetDay(_ day: String) {
        guard day <= today, engine.date(day) != nil else { return }
        protectedChange(label: "reset-day") { $0.resetDay(day) }
    }
    func resetProgress() { protectedChange(label: "reset-progress") { $0.resetProgress() } }
    func restart(length: Int) {
        guard [84, 90].contains(length) else { return }
        protectedChange(label: "restart-cycle") { $0.restart(on: today, length: length) }
    }
    func undoProgressAction() {
        guard let previous = undoDocument else { return }
        if change({ $0 = previous }) { undoDocument = nil; undoLabel = nil }
    }
    @discardableResult func saveReminders(_ preferences: ReminderPreferences) -> Bool {
        change { $0.reminders = preferences }
    }
    func completeMilestone(_ habit: Habit) {
        refreshDay()
        let done = engine.milestoneCompleted(habit)
        guard today >= document.cycle.start, today <= document.cycle.end else { return }
        change { doc in
            doc.checkIns.removeAll { $0.habitID == habit.id && $0.day >= doc.cycle.start && $0.day <= doc.cycle.end }
            if !done { doc.checkIns.append(CheckIn(habitID: habit.id, day: today, completed: true)) }
        }
    }
    @discardableResult func saveGoal(id: UUID?, title: String, symbol: String, start: String, end: String) -> Bool {
        change { doc in
            let w = GoalWindow(effectiveDay: today, start: start, end: end)
            if let id, let i = doc.goals.firstIndex(where: { $0.id == id }) {
                doc.goals[i].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                doc.goals[i].symbol = symbol
                if doc.goals[i].latest.start != start || doc.goals[i].latest.end != end { doc.goals[i].revise(w) }
            } else { doc.goals.append(Goal(title: title.trimmingCharacters(in: .whitespacesAndNewlines), symbol: symbol, windows: [w])) }
        }
    }
    @discardableResult func saveHabit(id: UUID?, goalID: UUID, kind: HabitKind, title: String, note: String,
                   period: Period, schedule: Schedule, target: MetricTarget?, scheduledMinute: Int? = nil) -> Bool {
        change { doc in
            let r = HabitRevision(effectiveDay: today, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                note: note, period: period, schedule: schedule, target: target, scheduledMinute: scheduledMinute)
            if let id, let i = doc.habits.firstIndex(where: { $0.id == id }) {
                var comparison = r; comparison.effectiveDay = doc.habits[i].latest.effectiveDay
                if comparison != doc.habits[i].latest { doc.habits[i].revise(r) }
            }
            else { doc.habits.append(Habit(goalID: goalID, kind: kind, createdDay: today, revisions: [r])) }
        }
    }
    @discardableResult func archive(_ habit: Habit) -> Bool {
        change { doc in if let i = doc.habits.firstIndex(where: { $0.id == habit.id }) { doc.habits[i].archivedDay = today } }
    }
    func restore(_ habit: Habit) {
        // Restoring creates a new habit, so archived days remain unchanged.
        let r = habit.latest
        var schedule = r.schedule
        if habit.kind == .milestone, let due = schedule.once, due < today { schedule.once = today }
        saveHabit(id: nil, goalID: habit.goalID, kind: habit.kind, title: r.title, note: r.note,
                  period: r.period, schedule: schedule, target: r.target, scheduledMinute: r.scheduledMinute)
    }
    @discardableResult func updateCycle(title: String, start: String, end: String, target: Double) -> Bool {
        change { doc in
            let old = doc.cycle
            let next = Cycle(title: title, start: start, end: end, target: target)
            guard next != old else { return }
            doc.cycle = next
            for i in doc.goals.indices where doc.goals[i].latest.start == old.start && doc.goals[i].latest.end == old.end {
                if start != old.start || end != old.end { doc.goals[i].revise(GoalWindow(effectiveDay: today, start: start, end: end)) }
            }
        }
    }
    @discardableResult func saveRoutine(_ routine: RoutinePreferences) -> Bool { change { $0.routine = routine } }
    @discardableResult func saveObservation(_ observation: DailyObservation) -> Bool {
        refreshDay()
        guard observation.day <= today, engine.date(observation.day) != nil,
              observation.sleep.map({ $0.wakeTime <= Date() }) ?? true else { notice = "Daily check-ins and sleep windows must be in the past or present."; return false }
        var entry = observation; entry.note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = document.wellbeing.observation(on: entry.day)
        if existing == entry || (existing == nil && entry.isEmpty) { return true }
        let previous = document
        guard change({ $0.wellbeing.set(entry) }) else { return false }
        undoDocument = previous; undoLabel = "daily check-in"
        return true
    }
    @discardableResult func deleteObservation(_ day: String) -> Bool {
        guard document.wellbeing.observation(on: day) != nil else { return false }
        return protectedChange(label: "daily-check-in-deletion") { $0.wellbeing.daily.removeAll { $0.day == day } }
    }
    @discardableResult func saveCaffeine(_ entry: CaffeineEntry) -> Bool {
        guard entry.timestamp <= Date() else { notice = "Caffeine entries must be in the past or present."; return false }
        var entry = entry; entry.name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if document.wellbeing.caffeine.first(where: { $0.id == entry.id }) == entry { return true }
        let previous = document
        guard change({ $0.wellbeing.set(entry) }) else { return false }
        undoDocument = previous; undoLabel = "caffeine log"
        return true
    }
    @discardableResult func deleteCaffeine(_ id: UUID) -> Bool {
        guard document.wellbeing.caffeine.contains(where: { $0.id == id }) else { return false }
        return protectedChange(label: "caffeine-deletion") { $0.wellbeing.caffeine.removeAll { $0.id == id } }
    }
    @discardableResult func importHealth(_ snapshot: HealthSnapshot, requestID: String) -> Bool {
        do {
            let archive = try document.health.merging(snapshot, expectedRequestID: requestID)
            let today = today
            return protectedChange(label: "watch-sync") { $0.health = archive; $0.applyHealthReadings(today: today) }
        } catch { notice = error.localizedDescription; return false }
    }
    var mealsFolder: URL { storageURL.deletingLastPathComponent().appendingPathComponent("Meals", isDirectory: true) }
    func mealPhotoURL(_ meal: MealEntry) -> URL { mealsFolder.appendingPathComponent(meal.photo) }
    /// Copies a meal photo (resized, metadata removed) and adds it for estimating. Returns nil when that meal ID already exists.
    @discardableResult func addMeal(id: UUID = UUID(), photo source: URL, takenAt: Date, note: String, source kind: String) throws -> MealEntry? {
        refreshDay()
        guard !document.meals.entries.contains(where: { $0.id == id }) else { return nil }
        let when = min(takenAt, Date())
        let name = try ChatPhotos.store(source, in: mealsFolder)
        let entry = MealEntry(id: id, takenAt: when.timeIntervalSince1970, day: engine.key(when),
                              note: String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)), photo: name, source: kind)
        guard change({ $0.meals.entries.append(entry) }) else {
            try? FileManager.default.removeItem(at: mealsFolder.appendingPathComponent(name))
            throw ValidationError(message: saveError ?? notice ?? "The meal couldn’t be saved.")
        }
        return entry
    }
    func setMealEstimate(_ id: UUID, estimate: MealEstimate?, error: String?) {
        change { doc in
            guard let i = doc.meals.entries.firstIndex(where: { $0.id == id }) else { return }
            if let estimate { doc.meals.entries[i].estimate = estimate }
            doc.meals.entries[i].error = error.map { String($0.prefix(600)) }
        }
    }
    /// Confirming logs the meal and sets that day's Calorie and Protein check-ins to the confirmed totals.
    @discardableResult func confirmMeal(_ id: UUID, kcal: Double, protein: Double, carbs: Double, fat: Double, note: String) -> Bool {
        refreshDay()
        guard [kcal, protein, carbs, fat].allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 10_000 }) else { notice = "Enter nutrition values between 0 and 10,000."; return false }
        let previous = document, today = today
        guard change({ doc in
            guard let i = doc.meals.entries.firstIndex(where: { $0.id == id }) else { return }
            doc.meals.entries[i].kcal = kcal; doc.meals.entries[i].protein = protein; doc.meals.entries[i].carbs = carbs; doc.meals.entries[i].fat = fat
            doc.meals.entries[i].note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)); doc.meals.entries[i].confirmed = true
            doc.applyMealTotals(on: doc.meals.entries[i].day, today: today)
        }) else { return false }
        undoDocument = previous; undoLabel = "meal log"
        return true
    }
    func updateMealNote(_ id: UUID, _ note: String) {
        change { doc in
            guard let i = doc.meals.entries.firstIndex(where: { $0.id == id }) else { return }
            doc.meals.entries[i].note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        }
    }
    func reopenMeal(_ id: UUID) {
        let today = today
        change { doc in
            guard let i = doc.meals.entries.firstIndex(where: { $0.id == id }) else { return }
            doc.meals.entries[i].confirmed = false; doc.applyMealTotals(on: doc.meals.entries[i].day, today: today)
        }
    }
    func deleteMeal(_ id: UUID) {
        let today = today
        protectedChange(label: "meal-deletion") { doc in
            guard let i = doc.meals.entries.firstIndex(where: { $0.id == id }) else { return }
            let day = doc.meals.entries[i].day
            doc.meals.entries.remove(at: i); doc.applyMealTotals(on: day, today: today)
        }
    }
    // MARK: Notes
    /// Adds or updates a note.
    @discardableResult func saveNote(_ note: JournalNote) -> Bool {
        var note = note
        note.title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        note.body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        note.actions = note.actions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        note.updated = Date().timeIntervalSince1970
        return change { doc in
            if let i = doc.notes.notes.firstIndex(where: { $0.id == note.id }) { doc.notes.notes[i] = note } else { doc.notes.notes.append(note) }
        }
    }
    func deleteNote(_ id: UUID) { protectedChange(label: "note-deletion") { $0.notes.notes.removeAll { $0.id == id } } }

    // MARK: Medicines
    var medsFolder: URL { storageURL.deletingLastPathComponent().appendingPathComponent("Meds", isDirectory: true) }
    func medPhotoURL(_ name: String) -> URL { medsFolder.appendingPathComponent(name) }
    private var medFiles: Set<String> { Set(document.meds.medicines.flatMap(\.photos) + document.meds.inbox.map(\.photo)) }
    /// Copies a photo (resized, metadata removed) as `<id>.jpg|png` so a resend of the same photo is recognised.
    private func storeMedPhoto(_ source: URL, id: UUID) throws -> String {
        let stored = try ChatPhotos.store(source, in: medsFolder)
        let name = "\(id.uuidString.lowercased()).\((stored as NSString).pathExtension)"
        try? FileManager.default.removeItem(at: medPhotoURL(name))
        try FileManager.default.moveItem(at: medPhotoURL(stored), to: medPhotoURL(name))
        return name
    }
    /// Adds one photo of a phone batch. Returns nil when it was already received, otherwise whether the batch is complete.
    func addPhoneMedPhoto(id: UUID, batch: UUID, batchSize: Int, takenAt: Date, file: URL) throws -> Bool? {
        refreshDay()
        guard !medFiles.contains(where: { $0.hasPrefix(id.uuidString.lowercased()) }) else { return nil }
        let name = try storeMedPhoto(file, id: id)
        guard change({ doc in
            if !doc.meds.batches.contains(where: { $0.id == batch }) { doc.meds.batches.append(MedBatch(id: batch, expected: batchSize, source: "phone")) }
            doc.meds.inbox.append(MedPhoto(photo: name, takenAt: min(takenAt, Date()).timeIntervalSince1970, batch: batch))
        }) else {
            try? FileManager.default.removeItem(at: medPhotoURL(name))
            throw ValidationError(message: saveError ?? notice ?? "The medicine photo couldn’t be saved.")
        }
        return document.meds.batches.first { $0.id == batch }.map(document.meds.ready) ?? false
    }
    /// Photos dropped or chosen on the Mac form one batch, sorted straight away.
    func addMedPhotos(_ urls: [URL]) -> UUID? {
        let batch = UUID()
        var names: [(String, Date)] = []
        for url in urls.prefix(ClaudeAssistant.maxMedPhotos) {
            do { names.append((try storeMedPhoto(url, id: UUID()), (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date())) }
            catch { notice = error.localizedDescription }
        }
        guard !names.isEmpty, change({ doc in
            doc.meds.batches.append(MedBatch(id: batch, expected: names.count, source: "mac"))
            for (name, date) in names { doc.meds.inbox.append(MedPhoto(photo: name, takenAt: min(date, Date()).timeIntervalSince1970, batch: batch)) }
        }) else { names.forEach { try? FileManager.default.removeItem(at: medPhotoURL($0.0)) }; return nil }
        return batch
    }
    /// Turns Claude's sorting into review cards. Photos it couldn't place go to the unsure tray.
    func applyMedSorting(batch: UUID, photos: [MedPhoto], sorting: MedSorting) {
        change { doc in
            for reading in sorting.medicines {
                var medicine = Medicine(photos: reading.photos.map { photos[$0 - 1].photo })
                medicine.apply(reading); doc.meds.medicines.append(medicine)
            }
            let unsure = Set(sorting.unsure.map { photos[$0 - 1].id }), sent = Set(photos.map(\.id))
            for i in doc.meds.inbox.indices where unsure.contains(doc.meds.inbox[i].id) { doc.meds.inbox[i].unsure = true }
            doc.meds.inbox.removeAll { sent.contains($0.id) && !unsure.contains($0.id) }
            if doc.meds.batchPhotos(batch).isEmpty { doc.meds.batches.removeAll { $0.id == batch } }
        }
    }
    func setMedBatchError(_ batch: UUID, _ error: String?) {
        change { doc in if let i = doc.meds.batches.firstIndex(where: { $0.id == batch }) { doc.meds.batches[i].error = error.map { String($0.prefix(600)) } } }
    }
    /// Sorts a batch with the photos received so far.
    func sortMedBatchNow(_ batch: UUID) {
        change { doc in
            guard let i = doc.meds.batches.firstIndex(where: { $0.id == batch }) else { return }
            doc.meds.batches[i].expected = max(1, doc.meds.batchPhotos(batch).count); doc.meds.batches[i].error = nil
        }
    }
    func setMedReading(_ id: UUID, reading: MedReading?, error: String?) {
        change { doc in
            guard let i = doc.meds.medicines.firstIndex(where: { $0.id == id }) else { return }
            if let reading { doc.meds.medicines[i].apply(reading) }
            doc.meds.medicines[i].error = error.map { String($0.prefix(600)) }
        }
    }
    @discardableResult func saveMedicine(_ medicine: Medicine) -> Bool {
        let today = today
        return change { doc in
            guard let i = doc.meds.medicines.firstIndex(where: { $0.id == medicine.id }) else { return }
            doc.meds.medicines[i] = medicine
            doc.applyMedDoses(on: today, today: today)
        }
    }
    func newMedicine(photo: String? = nil) -> UUID? {
        let medicine = Medicine(photos: photo.map { [$0] } ?? [])
        guard change({ doc in
            if let photo { doc.meds.inbox.removeAll { $0.photo == photo } }
            doc.meds.medicines.append(medicine)
        }) else { return nil }
        return medicine.id
    }
    func isMedPhoto(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL == medsFolder.standardizedFileURL && medFiles.contains(url.lastPathComponent)
    }
    /// Adds a photo from Finder as another side of an existing medicine.
    func addMedSide(_ url: URL, to medicine: UUID) {
        do {
            let name = try storeMedPhoto(url, id: UUID())
            guard change({ doc in if let i = doc.meds.medicines.firstIndex(where: { $0.id == medicine }) { doc.meds.medicines[i].photos.append(name) } }),
                  document.meds.medicines.contains(where: { $0.photos.contains(name) }) else { try? FileManager.default.removeItem(at: medPhotoURL(name)); return }
        } catch { notice = error.localizedDescription }
    }
    /// Moves a photo onto a medicine card, or back to the unsure tray when `to` is nil.
    func moveMedPhoto(_ photo: String, to target: UUID?) {
        guard medFiles.contains(photo) else { return }
        change { doc in
            let from = doc.meds.inbox.first { $0.photo == photo }
            doc.meds.inbox.removeAll { $0.photo == photo }
            for i in doc.meds.medicines.indices { doc.meds.medicines[i].photos.removeAll { $0 == photo } }
            if let target, let i = doc.meds.medicines.firstIndex(where: { $0.id == target }) { doc.meds.medicines[i].photos.append(photo) }
            else { var p = MedPhoto(photo: photo, takenAt: from?.takenAt ?? Date().timeIntervalSince1970, batch: from?.batch ?? UUID()); p.unsure = true; doc.meds.inbox.append(p) }
        }
    }
    func removeMedPhoto(_ photo: String) {
        protectedChange(label: "medicine-photo") { doc in
            doc.meds.inbox.removeAll { $0.photo == photo }
            for i in doc.meds.medicines.indices { doc.meds.medicines[i].photos.removeAll { $0 == photo } }
        }
    }
    func deleteMedicine(_ id: UUID) {
        let today = today
        protectedChange(label: "medicine-deletion") { doc in
            doc.meds.medicines.removeAll { $0.id == id }; doc.meds.doses.removeAll { $0.medID == id }
            doc.applyMedDoses(on: today, today: today)
        }
    }
    /// Marks a scheduled dose taken or not. Returns false with a notice when it isn't scheduled.
    @discardableResult func setDose(_ medID: UUID, day: String, minute: Int, taken: Bool, at: Date = Date(), source: String) -> Bool {
        refreshDay()
        let today = today
        var failure: String?
        let saved = change { doc in
            do { try doc.setDose(medID, day: day, minute: minute, taken: taken, at: at, source: source, today: today) }
            catch { failure = error.localizedDescription }
        }
        if let failure { notice = failure; return false }
        return saved
    }
    /// A tick, number or clear sent from the phone's checklist.
    @discardableResult func applyPhoneCheckIn(_ checkIn: PhoneCheckIn) -> Bool {
        refreshDay()
        let today = today
        var failure: String?
        let saved = change { doc in
            do { try doc.applyPhoneCheckIn(checkIn, today: today) }
            catch { failure = error.localizedDescription }
        }
        if let failure { notice = failure; return false }
        return saved
    }
    private func removeOrphanMedPhotos() {
        let used = medFiles
        for name in (try? FileManager.default.contentsOfDirectory(atPath: medsFolder.path)) ?? [] where !used.contains(name) {
            try? FileManager.default.removeItem(at: medsFolder.appendingPathComponent(name))
        }
    }
    /// Deleted meals keep their photo until the next launch so Undo can restore them.
    private func removeOrphanMealPhotos() {
        let used = Set(document.meals.entries.map(\.photo))
        for name in (try? FileManager.default.contentsOfDirectory(atPath: mealsFolder.path)) ?? [] where !used.contains(name) {
            try? FileManager.default.removeItem(at: mealsFolder.appendingPathComponent(name))
        }
    }
    @discardableResult func recordUrge(now: Date = Date()) -> UUID? {
        if let id = lastUrgeID, let existing = document.urgeLogs.first(where: { $0.id == id }),
           (0..<2).contains(now.timeIntervalSince(existing.timestamp)) { return id }
        let urge = UrgeLog(timestamp: now)
        let previous = document
        guard change({ $0.urgeLogs.append(urge) }) else { return nil }
        undoDocument = previous; undoLabel = "urge log"; lastUrgeID = urge.id
        return urge.id
    }
    /// Adds an urge logged on the phone. Returns nil when that ID was already received.
    func addPhoneUrge(_ urge: UrgeLog) -> Bool? {
        refreshDay()
        guard !document.urgeLogs.contains(where: { $0.id == urge.id }) else { return nil }
        return change { $0.urgeLogs.append(urge) }
    }
    var urgeTally: UrgeTally { engine.urgeTally(today: today) }
    @discardableResult func updateUrge(id: UUID, intensity: Int?, trigger: UrgeTrigger?, outcome: UrgeOutcome, note: String, category: String?, customTrigger: String? = nil) -> Bool {
        guard let i = document.urgeLogs.firstIndex(where: { $0.id == id }) else { notice = "This urge log no longer exists."; return false }
        return change { doc in
            doc.urgeLogs[i].intensity = intensity; doc.urgeLogs[i].trigger = trigger
            let custom = customTrigger?.trimmingCharacters(in: .whitespacesAndNewlines)
            doc.urgeLogs[i].customTrigger = trigger == .other && custom?.isEmpty == false ? custom : nil
            let label = category?.trimmingCharacters(in: .whitespacesAndNewlines)
            doc.urgeLogs[i].category = label?.isEmpty == false ? label : nil
            doc.urgeLogs[i].outcome = outcome; doc.urgeLogs[i].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    @discardableResult func deleteUrge(_ id: UUID) -> Bool {
        guard document.urgeLogs.contains(where: { $0.id == id }) else { return false }
        let previous = document
        guard change({ $0.urgeLogs.removeAll { $0.id == id } }) else { return false }
        undoDocument = previous; undoLabel = "urge deletion"
        if lastUrgeID == id { lastUrgeID = nil }
        return true
    }
    @discardableResult func applyProposal(_ proposal: PreparedProposal) -> Bool {
        refreshDay()
        do {
            let candidate = try proposal.resolve(current: document, today: today)
            return protectedChange(label: "assistant-edit") { $0 = candidate }
        } catch { notice = error.localizedDescription; return false }
    }
    func finish(_ value: String) { change { $0.avatarFinish = value } }
    func exportBackup() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Ascend-backup-\(today).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: url, options: .atomic)
            notice = "Backup exported."
        } catch { notice = "Export failed: \(error.localizedDescription)" }
    }
    func importBackup() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let incoming = try Self.read(url)
            let alert = NSAlert(); alert.messageText = "Restore this backup?"
            alert.informativeText = "This replaces the current plan and check-ins. A copy of your current data will be saved first."
            alert.addButton(withTitle: "Restore"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let archive = storageURL.deletingLastPathComponent().appendingPathComponent("before-restore-\(Int(Date().timeIntervalSince1970)).json")
            if FileManager.default.fileExists(atPath: storageURL.path) {
                try Data(contentsOf: storageURL).write(to: archive, options: .atomic)
            } else {
                let encoder = JSONEncoder(); try encoder.encode(document).write(to: archive, options: .atomic)
            }
            undoDocument = nil; undoLabel = nil
            document = incoming; recoveryLocked = false; saveError = nil; today = engine.key(Date()); save()
            notice = saveError ?? "Backup restored."
        } catch { notice = "Backup was not restored: \(error.localizedDescription)" }
    }
    func revealData() { NSWorkspace.shared.activateFileViewerSelecting([storageURL]) }
}
