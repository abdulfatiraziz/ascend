import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AscendCore

struct MedsView: View {
    @ObservedObject var store: TrackerStore
    @ObservedObject var reader: MedController
    @State private var showArchived = false
    init(store: TrackerStore) { self.store = store; reader = store.medsReader }
    private var cabinet: MedCabinet { store.document.meds }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Kicker("Photos → Claude sorts and reads → your review")
                        Text("Snap every side of your medicines in Ascend Bridge, in any order, or drop photos here. Add the schedule your doctor gave you; the phone reminds you and you tap Taken.").font(.system(size: 12)).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    Button("Add by name") { _ = store.newMedicine() }.font(.system(size: 12))
                    PrimaryButton(label: "Add photos…") { choose() }
                }
                todayPanel
                inbox
                let review = cabinet.medicines.filter { !$0.confirmed }
                if !review.isEmpty {
                    Kicker("To review · \(review.count)")
                    ForEach(review) { MedCard(store: store, reader: reader, medicine: $0) }
                }
                let active = cabinet.medicines.filter { $0.confirmed && !$0.archived }
                Kicker(active.isEmpty ? "Your medicines" : "Your medicines · \(active.count)")
                if active.isEmpty && review.isEmpty && cabinet.inbox.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No medicines yet.").font(.system(size: 18, weight: .semibold))
                        Text("On your phone: Ascend Bridge → Add medicines, photograph the front, back and strip of each one, tap Done. Claude groups the photos and reads the labels; you check each card and add the schedule.").font(.system(size: 12)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading).panel()
                }
                ForEach(active) { MedCard(store: store, reader: reader, medicine: $0) }
                let archived = cabinet.medicines.filter(\.archived)
                if !archived.isEmpty {
                    Button(showArchived ? "Hide stopped medicines" : "Show stopped medicines · \(archived.count)") { showArchived.toggle() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Ink.accent)
                    if showArchived { ForEach(archived) { MedCard(store: store, reader: reader, medicine: $0) } }
                }
                Text("Claude only reads what's printed on the packaging; categories and uses are general information, not medical advice. Schedules are what you enter from your doctor's instructions. Photos stay on this Mac; sorting sends them to Claude through your personal Claude profile.").font(.system(size: 11)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            }.padding(.bottom, 10)
        }
        .dropDestination(for: URL.self) { urls, _ in add(urls.filter { ChatPhotos.isImage($0) && !store.isMedPhoto($0) }); return true }
    }
    private var todayPanel: some View {
        let engine = store.engine
        let slots = cabinet.slots(on: store.today, engine: engine)
        let week = cabinet.adherence(today: store.today, days: 7, engine: engine)
        let cycleDays = max(0, engine.days(from: store.document.cycle.start, through: store.today).count - 1)
        let cycle = cabinet.adherence(today: store.today, days: cycleDays, engine: engine)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(slots.filter { $0.taken != nil }.count) of \(slots.count) taken").font(.system(size: 12)).foregroundStyle(Ink.muted)
            }
            if slots.isEmpty {
                Text("Nothing scheduled today. Confirm a medicine and add its schedule to see doses here.").font(.system(size: 12)).foregroundStyle(Ink.muted)
            }
            ForEach(slots) { slot in
                HStack(spacing: 14) {
                    Text(clockTime(slot.minute)).font(.system(size: 15, weight: .medium, design: .monospaced)).frame(width: 52, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slot.medicine.title).font(.system(size: 13))
                        Text([slot.medicine.schedule?.amount ?? "", slot.medicine.schedule.map { $0.food == .any ? "" : $0.food.label } ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    if let taken = slot.taken { Text("\(timeText(Date(timeIntervalSince1970: taken.takenAt), engine: engine)) · \(taken.source == "phone" ? "phone" : "Mac")").font(.system(size: 10)).foregroundStyle(Ink.muted) }
                    Button { store.setDose(slot.medicine.id, day: slot.day, minute: slot.minute, taken: slot.taken == nil, source: "mac") } label: {
                        Label(slot.taken == nil ? "Taken" : "Taken ✓", systemImage: slot.taken == nil ? "circle" : "checkmark.circle.fill")
                    }.buttonStyle(.plain).foregroundStyle(slot.taken == nil ? Color.primary : Ink.accent).font(.system(size: 12))
                }
            }
            Divider()
            HStack(spacing: 24) {
                Text("Last 7 days: \(week.taken) taken · \(week.missed) missed").font(.system(size: 11)).foregroundStyle(week.missed > 0 ? Color.orange : Ink.muted)
                Text("This cycle: \(cycle.taken) taken · \(cycle.missed) missed").font(.system(size: 11)).foregroundStyle(Ink.muted)
                Spacer()
                if let habit = store.document.medHabit { Text("Taking every dose ticks “\(habit.latest.title)”").font(.system(size: 11)).foregroundStyle(Ink.muted) }
            }
        }.panel(padding: 16)
    }
    @ViewBuilder private var inbox: some View {
        ForEach(cabinet.batches) { batch in
            let photos = cabinet.batchPhotos(batch.id)
            let sorting = reader.working.contains(.batch(batch.id))
            HStack(spacing: 12) {
                ForEach(photos.prefix(8)) { PhotoThumbnail(url: store.medPhotoURL($0.photo), size: 44) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(sorting ? "Sorting \(photos.count) photos with Claude…" : cabinet.ready(batch) ? "\(photos.count) photos waiting to sort" : "\(photos.count) of \(batch.expected) photos received from your \(batch.source == "phone" ? "phone" : "Mac")").font(.system(size: 12))
                    if let error = batch.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer()
                if sorting { ProgressView().controlSize(.small) }
                else { Button(batch.error == nil ? "Sort now" : "Retry") { reader.sortNow(batch.id) }.font(.system(size: 12)) }
            }.panel(padding: 14)
        }
        if !cabinet.unsure.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Not sure which medicine").font(.system(size: 13, weight: .medium))
                Text("Drag a photo onto the right card, or make it a new medicine.").font(.system(size: 11)).foregroundStyle(Ink.muted)
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(cabinet.unsure) { photo in
                            VStack(spacing: 6) {
                                PhotoThumbnail(url: store.medPhotoURL(photo.photo), size: 84).draggable(store.medPhotoURL(photo.photo))
                                HStack(spacing: 8) {
                                    Button("New") { if let id = store.newMedicine(photo: photo.photo) { reader.enqueue(.medicine(id)) } }.font(.system(size: 11))
                                    Button { store.removeMedPhoto(photo.photo) } label: { Image(systemName: "trash") }.buttonStyle(.plain).font(.system(size: 11)).accessibilityLabel("Remove photo")
                                }
                            }
                        }
                    }
                }
            }.panel(padding: 14)
                .dropDestination(for: URL.self) { urls, _ in urls.filter(store.isMedPhoto).forEach { store.moveMedPhoto($0.lastPathComponent, to: nil) }; return true }
        }
    }
    private func choose() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true; panel.message = "Choose photos of your medicines (all sides, any order)"
        if panel.runModal() == .OK { add(panel.urls) }
    }
    private func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if urls.count > ClaudeAssistant.maxMedPhotos { store.notice = "Add up to \(ClaudeAssistant.maxMedPhotos) photos at a time." }
        if let batch = store.addMedPhotos(urls) { reader.enqueue(.batch(batch)) }
    }
}

private struct MedCard: View {
    @ObservedObject var store: TrackerStore
    @ObservedObject var reader: MedController
    var medicine: Medicine
    @State private var draft = Medicine()
    @State private var ingredients = ""
    @State private var confirmDelete = false
    private var reading: Bool { reader.working.contains(.medicine(medicine.id)) }
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                ForEach(medicine.photos, id: \.self) { photo in
                    PhotoThumbnail(url: store.medPhotoURL(photo), size: 96).draggable(store.medPhotoURL(photo))
                        .contextMenu {
                            Button("Move to “Not sure”") { store.moveMedPhoto(photo, to: nil) }
                            Button("Remove photo", role: .destructive) { store.removeMedPhoto(photo) }
                        }
                }
                if medicine.photos.isEmpty { Image(systemName: "pills").font(.system(size: 28)).foregroundStyle(Ink.muted).frame(width: 96, height: 96).background(Ink.panel).clipShape(RoundedRectangle(cornerRadius: 7)) }
                Text("Drop more sides here").font(.system(size: 9)).foregroundStyle(Ink.muted)
            }.frame(width: 96)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(reading ? "Reading the label…" : medicine.title).font(.system(size: 15, weight: .semibold))
                    if medicine.archived { Text("Stopped").font(.system(size: 11)).foregroundStyle(Ink.muted) }
                    else if medicine.confirmed { Label("Active", systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Ink.accent) }
                    else { Text("Needs review").font(.system(size: 11)).foregroundStyle(.orange) }
                    Spacer()
                    if !medicine.confidence.isEmpty { Text("\(medicine.confidence) confidence").font(.system(size: 11)).foregroundStyle(Ink.muted) }
                }
                if reading { ProgressView().controlSize(.small) }
                if !medicine.reading.isEmpty { Text(medicine.reading).font(.system(size: 11)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true) }
                if let error = medicine.error {
                    HStack { Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true); Button("Retry") { reader.reRead(medicine.id) }.font(.system(size: 11)) }
                }
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow { field("Name", $draft.name); field("Strength", $draft.strength); field("Form", $draft.form) }
                    GridRow { field("Category", $draft.category); field("Active ingredients (comma-separated)", $ingredients).gridCellColumns(2) }
                    GridRow { field("What it's for", $draft.purpose).gridCellColumns(2); field("Notes", $draft.notes) }
                }
                MedScheduleEditor(engine: store.engine, today: store.today, schedule: $draft.schedule)
                HStack {
                    Button("Delete…") { confirmDelete = true }.font(.system(size: 11))
                    if !medicine.photos.isEmpty { Button("Re-read label") { reader.reRead(medicine.id) }.font(.system(size: 11)).disabled(reading) }
                    if medicine.confirmed { Button(medicine.archived ? "Restart" : "Stop taking") { var m = medicine; m.archived.toggle(); store.saveMedicine(m) }.font(.system(size: 11)) }
                    Spacer()
                    if changed { Button("Revert") { load() }.font(.system(size: 12)) }
                    PrimaryButton(label: medicine.confirmed ? "Save" : "Confirm medicine") { save() }.disabled((medicine.confirmed && !changed) || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }.panel(padding: 14)
            // Photos dragged from another card or the tray move here; photos from Finder join as extra sides.
            .dropDestination(for: URL.self) { urls, _ in
                for url in urls { if store.isMedPhoto(url) { store.moveMedPhoto(url.lastPathComponent, to: medicine.id) } else if ChatPhotos.isImage(url) { store.addMedSide(url, to: medicine.id) } }
                return true
            }
            .onAppear(perform: load)
            .onChange(of: medicine) { _, _ in load() }
            .confirmationDialog("Delete \(medicine.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete medicine", role: .destructive) { store.deleteMedicine(medicine.id) }; Button("Cancel", role: .cancel) {}
            } message: { Text("Its photos and dose history are removed. To keep the history, use Stop taking instead. Undo is available until your next edit.") }
    }
    private var edited: Medicine {
        var m = draft
        m.ingredients = ingredients.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for keyPath in [\Medicine.name, \.strength, \.form, \.category, \.purpose, \.notes] { m[keyPath: keyPath] = m[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines) }
        return m
    }
    private var changed: Bool { edited != medicine }
    private func field(_ label: String, _ value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10)).foregroundStyle(Ink.muted)
            TextField(label, text: value).textFieldStyle(.roundedBorder).font(.system(size: 12))
        }
    }
    private func load() { draft = medicine; ingredients = medicine.ingredients.joined(separator: ", ") }
    private func save() { var m = edited; m.confirmed = true; store.saveMedicine(m) }
}

/// The doctor's instructions: how often, times, amount, food and course dates.
private struct MedScheduleEditor: View {
    let engine: TrackerEngine
    let today: String
    @Binding var schedule: MedSchedule?
    private static let weekdayNames = ["S", "M", "T", "W", "T", "F", "S"]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let s = schedule {
                HStack {
                    Text("Schedule").font(.system(size: 12, weight: .medium))
                    Text(s.summary).font(.system(size: 11)).foregroundStyle(Ink.muted)
                    Spacer()
                    Button("Remove schedule") { schedule = nil }.font(.system(size: 11))
                }
                Picker("How often", selection: bind(\.frequency)) { ForEach(MedFrequency.allCases, id: \.self) { Text($0.label).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                if s.frequency == .weekdays {
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { day in
                            let on = s.weekdays.contains(day)
                            Button(Self.weekdayNames[day - 1]) {
                                var days = Set(s.weekdays); if on { days.remove(day) } else { days.insert(day) }
                                schedule?.weekdays = days.sorted()
                            }.buttonStyle(.plain).frame(width: 26, height: 26).background(on ? Ink.accent.opacity(0.35) : Ink.panel).clipShape(Circle())
                        }
                    }
                }
                if s.frequency == .everyNDays { Stepper("Every \(s.interval) days, counting from the start date", value: bind(\.interval), in: 2...60).font(.system(size: 12)) }
                if s.frequency != .asNeeded {
                    HStack(spacing: 10) {
                        Text("Times").font(.system(size: 11)).foregroundStyle(Ink.muted)
                        ForEach(s.times.indices, id: \.self) { i in
                            DatePicker("Dose \(i + 1)", selection: timeBinding(i), displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
                        }
                        if s.times.count < 4 { Button { schedule?.times.append(nextTime(s.times)) } label: { Image(systemName: "plus.circle") }.buttonStyle(.plain).accessibilityLabel("Add a dose time") }
                        if s.times.count > 1 { Button { schedule?.times.removeLast() } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).accessibilityLabel("Remove the last dose time") }
                    }
                }
                HStack(spacing: 12) {
                    TextField("Amount, e.g. 1 tablet", text: bind(\.amount)).textFieldStyle(.roundedBorder).frame(width: 170).font(.system(size: 12))
                    Picker("Food", selection: bind(\.food)) { ForEach(MedFood.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden().fixedSize()
                    DatePicker("From", selection: dayBinding(\.start), displayedComponents: .date).font(.system(size: 11)).fixedSize()
                    Toggle("Ends", isOn: Binding(get: { s.end != nil }, set: { schedule?.end = $0 ? engine.adding(29, to: s.start) : nil })).font(.system(size: 11))
                    if s.end != nil { DatePicker("Until", selection: Binding(get: { engine.date(s.end ?? s.start) ?? Date() }, set: { schedule?.end = engine.key($0) }), displayedComponents: .date).labelsHidden().fixedSize() }
                }
                if (try? s.validate(engine: engine)) == nil { Text("Pick at least one weekday, and an end date after the start.").font(.system(size: 11)).foregroundStyle(.orange) }
            } else {
                HStack {
                    Text("No schedule yet").font(.system(size: 12)).foregroundStyle(Ink.muted)
                    Button("Add the doctor's schedule") { schedule = MedSchedule(start: today) }.font(.system(size: 12))
                    Text("or tell Ask Ascend, e.g. “once daily after breakfast”").font(.system(size: 11)).foregroundStyle(Ink.muted)
                }
            }
        }.padding(10).background(Ink.panel.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 8))
    }
    private func bind<T>(_ keyPath: WritableKeyPath<MedSchedule, T>) -> Binding<T> {
        Binding(get: { schedule![keyPath: keyPath] }, set: { schedule?[keyPath: keyPath] = $0 })
    }
    private func dayBinding(_ keyPath: WritableKeyPath<MedSchedule, String>) -> Binding<Date> {
        Binding(get: { engine.date(schedule![keyPath: keyPath]) ?? Date() }, set: { schedule?[keyPath: keyPath] = engine.key($0) })
    }
    private func timeBinding(_ i: Int) -> Binding<Date> {
        Binding(get: { engine.time(on: today, minute: schedule?.times[safe: i] ?? 540) ?? Date() },
                set: { date in if schedule?.times.indices.contains(i) == true { schedule?.times[i] = engine.minute(date) } })
    }
    private func nextTime(_ times: [Int]) -> Int {
        var t = ((times.max() ?? 9 * 60) + 12 * 60) % 1440
        while times.contains(t) { t = (t + 60) % 1440 }
        return t
    }
}
private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
