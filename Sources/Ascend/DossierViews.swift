import SwiftUI
import AscendCore

/// The Dossier: clearance ladder with rewards, M's last debrief, and the lifestyle file
/// (wardrobe, Q Branch, garage, places, skills). Everything is editable in place and saved to lifestyle.json.
struct DossierView: View {
    @ObservedObject var store: TrackerStore
    @ObservedObject var lifestyle: LifestyleStore
    @State private var editing: DossierItem?
    @State private var editingReward: ClearanceLevel?

    var body: some View {
        let facts = WeekFacts(store: store)
        let status = facts.status
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = lifestyle.saveError { Text(error).font(.bt(size: 12)).foregroundStyle(Ink.offTrack) }
                ClearanceLadder(status: status, thisWeek: facts.thisWeek, rewards: lifestyle.lifestyle.rewards) { editingReward = $0 }
                if let m = facts.debriefMonday { DebriefCard(store: store, monday: m, memo: Debrief.compose(facts.debriefWeek(m))) }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(DossierSection.allCases, id: \.self) { section in
                        SectionPanel(section: section, items: lifestyle.lifestyle.items(in: section),
                                     fit: section == .wardrobe ? lifestyle.lifestyle.tonightsFit(dayOfYear: store.engine.calendar.ordinality(of: .day, in: .year, for: Date()) ?? 1) : [],
                                     edit: { editing = $0 },
                                     add: { editing = DossierItem(section: section, title: "", tag: section.tags[0], progress: section == .skills ? 0 : nil) })
                    }
                }
                Text("Placeholders are marked. Click any line to make it yours; the Dossier stays on this Mac and Q can read it.")
                    .font(.bt(size: 11)).foregroundStyle(Ink.muted)
            }
        }
        .scrollIndicators(.never)
        .sheet(item: $editing) { item in
            DossierItemEditor(item: item, isNew: !lifestyle.lifestyle.items.contains { $0.id == item.id },
                              save: { lifestyle.upsert($0); editing = nil }, delete: { lifestyle.delete(item.id); editing = nil }, cancel: { editing = nil })
                .preferredColorScheme(.dark)
        }
        .sheet(item: $editingReward) { level in
            RewardEditor(level: level, text: lifestyle.lifestyle.rewards[level.mark] ?? "",
                         save: { lifestyle.setReward(level.mark, $0); editingReward = nil }, cancel: { editingReward = nil })
                .preferredColorScheme(.dark)
        }
    }
}

extension ClearanceLevel: Identifiable { public var id: Int { rawValue } }

// MARK: - Clearance

/// The five levels as a row of engraved plates; the current one is lit.
struct ClearanceLadder: View {
    let status: ClearanceStatus
    let thisWeek: ClearanceWeek
    let rewards: [String: String]
    let editReward: (ClearanceLevel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CLEARANCE · \(status.level.rank.uppercased())").font(.bt(size: 10, design: .monospaced)).tracking(1.6).foregroundStyle(Ink.accent)
                    Text(status.level == .doubleO ? "Double-O. Licensed." : "You hold \(status.level.title).").font(.bt(size: 28)).foregroundStyle(Ink.ivory)
                    Text(status.level.next.map { _ in "Next: \(status.level.nextRule) · streak \(status.streak)/\(status.level.weeksToNext)" } ?? status.level.nextRule)
                        .font(.bt(size: 12)).foregroundStyle(Ink.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Kicker("This week so far")
                    Text("Gym \(thisWeek.gym)/3 · check-ins \(Int((thisWeek.checkIns * 100).rounded()))% · by 1 am \(thisWeek.nightsByOne)/\(max(thisWeek.nightsKnown, 0))")
                        .font(.bt(size: 11, design: .monospaced)).foregroundStyle(Ink.ivory)
                }
            }
            HStack(spacing: 10) {
                ForEach(ClearanceLevel.allCases, id: \.self) { level in plate(level) }
            }
            HStack(spacing: 16) {
                Text(Clearance.cleanRule); Text(Clearance.slackRule)
            }.font(.bt(size: 10, design: .monospaced)).foregroundStyle(Ink.goldDim)
        }
        .padding(22)
        .background(LitFelt().clipShape(RoundedRectangle(cornerRadius: 14)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.accent.opacity(0.28)))
    }

    private func plate(_ level: ClearanceLevel) -> some View {
        let current = level == status.level, earned = level <= status.level
        return Button { editReward(level) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(level.mark).font(.bt(size: 30, weight: .semibold, design: .serif)).foregroundStyle(earned ? Ink.lamp : Ink.goldDim)
                    Spacer()
                    Image(systemName: earned ? "checkmark.seal.fill" : "lock").font(.bt(size: 12)).foregroundStyle(earned ? Ink.accent : Ink.muted)
                }
                Text(level.rank.uppercased()).font(.bt(size: 9, design: .monospaced)).tracking(1.4).foregroundStyle(current ? Ink.accent : Ink.muted)
                Text(rewards[level.mark] ?? "Set a reward").font(.bt(size: 11)).foregroundStyle(earned ? Ink.ivory : Ink.muted)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(current ? Ink.panel2 : Ink.night.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(current ? Ink.lamp.opacity(0.8) : Ink.line, lineWidth: current ? 1.5 : 1))
            .shadow(color: current ? Ink.lamp.opacity(0.25) : .clear, radius: 10)
        }
        .buttonStyle(.plain).help("Edit the reward for \(level.title)")
    }
}

/// One-time card on the Brief when a new level is reached.
struct LevelUpCard: View {
    let level: ClearanceLevel
    let reward: String
    let accept: () -> Void
    var body: some View {
        HStack(spacing: 18) {
            Text(level.mark).font(.bt(size: 46, weight: .semibold, design: .serif)).foregroundStyle(Ink.lamp)
                .frame(width: 74, height: 74).overlay(Circle().stroke(Ink.accent, lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 5) {
                Text("PROMOTION · FILE 0075").font(.bt(size: 10, design: .monospaced)).tracking(1.6).foregroundStyle(Ink.accent)
                Text("\(level.title) granted. \(level.rank).").font(.bt(size: 24)).foregroundStyle(Ink.ivory)
                Text("Reward: \(reward)").font(.bt(size: 12)).foregroundStyle(Ink.muted)
            }
            Spacer()
            PrimaryButton(label: "Accept", action: accept)
        }
        .padding(18).background(Ink.panel2, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.lamp.opacity(0.7), lineWidth: 1.5))
    }
}

// MARK: - M's debrief

/// The weekly memo on cream paper. Filed as a Note the first time it's shown. Urges are never in it.
struct DebriefCard: View {
    @ObservedObject var store: TrackerStore
    let monday: String
    let memo: DebriefMemo
    private let paper = Color(hex: 0xF1E8D4), ink = Color(hex: 0x1D2A24), red = Color(hex: 0x9E2B33)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("MEMORANDUM · FROM M").font(.bt(size: 10, weight: .semibold, design: .monospaced)).tracking(2)
                Spacer()
                Text("Week of \(dateText(monday, engine: store.engine, pattern: "d MMM"))").font(.bt(size: 10, design: .monospaced))
            }.foregroundStyle(ink.opacity(0.7))
            Rectangle().fill(ink.opacity(0.25)).frame(height: 1)
            HStack(alignment: .top, spacing: 26) {
                column("Wins", memo.wins)
                column("Misses", memo.misses)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("ORDER").font(.bt(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(red)
                Text(memo.order).font(.bt(size: 19, weight: .semibold, design: .serif)).foregroundStyle(ink)
            }
            HStack {
                Text("Filed in Notes · urge details stay in the Urges tab").font(.bt(size: 10)).foregroundStyle(ink.opacity(0.55))
                Spacer()
                Text("— M").font(.custom(Typeface.serif, fixedSize: 18).italic()).foregroundStyle(ink.opacity(0.8))
            }
        }
        .padding(22).background(paper, in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .onAppear(perform: file)
    }

    private func column(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.bt(size: 10, weight: .bold, design: .monospaced)).tracking(1.6).foregroundStyle(ink.opacity(0.6))
            ForEach(lines, id: \.self) { line in
                Text("· " + line).font(.bt(size: 12)).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Saves the memo as an insight note once per week.
    private func file() {
        guard store.lifestyle.lifestyle.debriefFiled != monday else { return }
        let title = "M's debrief · week of \(dateText(monday, engine: store.engine, pattern: "d MMM"))"
        guard !store.document.notes.notes.contains(where: { $0.title == title }) else { store.lifestyle.update { $0.debriefFiled = monday }; return }
        if store.saveNote(JournalNote(kind: .insight, title: title, body: memo.text, day: store.today)) {
            store.lifestyle.update { $0.debriefFiled = monday }
        }
    }
}

// MARK: - Sections

struct SectionPanel: View {
    let section: DossierSection
    let items: [DossierItem]
    let fit: [DossierItem]
    let edit: (DossierItem) -> Void
    let add: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol).font(.bt(size: 14)).foregroundStyle(Ink.accent)
                Text(section.title).font(.bt(size: 22)).foregroundStyle(Ink.ivory)
                Spacer()
                Button(action: add) { Label("Add", systemImage: "plus").font(.bt(size: 11)).padding(.horizontal, 9).padding(.vertical, 5) }
                    .buttonStyle(.plain).background(Ink.panel2, in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(Ink.accent)
            }
            Text(section.blurb).font(.bt(size: 11)).foregroundStyle(Ink.muted)
            if !fit.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("Tonight's fit")
                    Text(fit.map(\.title).joined(separator: " · ")).font(.bt(size: 13, weight: .medium)).foregroundStyle(Ink.lamp)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Ink.night.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }
            if items.isEmpty { Text("Nothing here yet.").font(.bt(size: 12)).foregroundStyle(Ink.muted) }
            ForEach(items) { item in row(item) }
        }
        .panel(padding: 18)
    }

    private func row(_ item: DossierItem) -> some View {
        Button { edit(item) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title).font(.bt(size: 13, weight: .medium)).foregroundStyle(Ink.ivory)
                    if item.placeholder { Text("PLACEHOLDER").font(.bt(size: 8, design: .monospaced)).tracking(1).foregroundStyle(Ink.goldDim) }
                    Spacer()
                    if section != .skills { tag(item.tag) }
                    else if let p = item.progress { Text("\(Int((p * 100).rounded()))%").font(.bt(size: 11, design: .monospaced)).foregroundStyle(Ink.accent) }
                }
                if !item.detail.isEmpty { Text(item.detail).font(.bt(size: 11)).foregroundStyle(Ink.muted).lineLimit(2) }
                if section == .skills, let p = item.progress { ProgressTrack(ratio: p, target: 1) }
            }
            .padding(.vertical, 7).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help("Edit")
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.line).frame(height: 1) }
    }

    private func tag(_ text: String) -> some View {
        let color = text == "Owned" || text == "Nearby" ? Ink.onTrack : text == "Dream" ? Ink.lamp : text == "After the cut" ? Ink.watch : Ink.accent
        return Text(text.uppercased()).font(.bt(size: 9, design: .monospaced)).tracking(1).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3).overlay(Capsule().stroke(color.opacity(0.6)))
    }
}

// MARK: - Editors

struct DossierItemEditor: View {
    @State var item: DossierItem
    let isNew: Bool
    let save: (DossierItem) -> Void
    let delete: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker("\(item.section.title) · \(isNew ? "new" : "edit")")
            Text(isNew ? "Add to the file." : "Edit the file.").font(.bt(size: 26)).foregroundStyle(Ink.ivory)
            TextField("Title", text: $item.title).textFieldStyle(.roundedBorder)
            TextField("Detail (optional)", text: $item.detail).textFieldStyle(.roundedBorder)
            if item.section == .skills {
                HStack { Text("Progress").font(.bt(size: 12)); Slider(value: Binding(get: { item.progress ?? 0 }, set: { item.progress = $0 }), in: 0...1, step: 0.05); Text("\(Int(((item.progress ?? 0) * 100).rounded()))%").font(.bt(size: 11, design: .monospaced)).frame(width: 40) }
            } else {
                Picker("Status", selection: $item.tag) { ForEach(item.section.tags, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
            }
            HStack {
                if !isNew { Button("Delete", role: .destructive, action: delete).foregroundStyle(Ink.offTrack) }
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                PrimaryButton(label: "Save") {
                    var done = item
                    done.title = done.title.trimmingCharacters(in: .whitespacesAndNewlines); done.detail = done.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                    done.placeholder = false
                    save(done)
                }.disabled(item.title.trimmingCharacters(in: .whitespaces).isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .padding(26).frame(width: 460).background(Ink.background).foregroundStyle(Ink.ivory)
    }
}

struct RewardEditor: View {
    let level: ClearanceLevel
    @State var text: String
    let save: (String) -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker("\(level.title) · \(level.rank)")
            Text("Set the reward.").font(.bt(size: 26)).foregroundStyle(Ink.ivory)
            Text(level.previous.map { "Earned by: \($0.nextRule)." } ?? "Your starting level.").font(.bt(size: 12)).foregroundStyle(Ink.muted)
            TextField("A fragrance, a tailored shirt, the watch…", text: $text).textFieldStyle(.roundedBorder)
            HStack { Spacer(); Button("Cancel", action: cancel).keyboardShortcut(.cancelAction); PrimaryButton(label: "Save") { save(text) }.keyboardShortcut(.defaultAction) }
        }
        .padding(26).frame(width: 460).background(Ink.background).foregroundStyle(Ink.ivory)
    }
}
