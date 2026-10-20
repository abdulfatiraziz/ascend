import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import AscendCore

/// Downscaled copies of progress photos, so the timeline grid doesn't decode full-size images on every redraw.
@MainActor enum PhotoCache {
    private static let cache = NSCache<NSString, NSImage>()
    static func image(_ url: URL, maxPixel: Int) -> NSImage? {
        let key = "\(url.path)#\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key)
        return image
    }
}
private struct AlbumImage: View {
    var url: URL
    var maxPixel = 2048
    var fill = false
    var body: some View {
        if let image = PhotoCache.image(url, maxPixel: maxPixel) {
            if fill { Image(nsImage: image).resizable().scaledToFill() } else { Image(nsImage: image).resizable().scaledToFit() }
        } else { Image(systemName: "photo").foregroundStyle(Ink.muted).frame(maxWidth: .infinity, maxHeight: .infinity) }
    }
}

struct PhotosView: View {
    @ObservedObject var store: TrackerStore
    @ObservedObject var reviews: PhotoReviewController
    @AppStorage("ascend.photos.area") private var areaValue = PhotoArea.hair.rawValue
    @State private var angle: PhotoAngle?
    @State private var beforeID: UUID?
    @State private var afterID: UUID?
    @State private var overlay = false
    @State private var blend = 0.5
    @State private var importing: [ImportItem] = []
    @State private var editing: ProgressPhoto?
    @State private var savedNotes: Set<UUID> = []
    init(store: TrackerStore) { self.store = store; reviews = store.photoReviews }
    private var area: PhotoArea { PhotoArea(rawValue: areaValue) ?? .hair }
    private var album: PhotoAlbum { store.document.photos }
    private var currentAngle: PhotoAngle? { let used = album.angles(area); return angle.flatMap { used.contains($0) ? $0 : nil } ?? used.first }

    var body: some View {
        ScrollView { content }
        .dropDestination(for: URL.self) { urls, _ in prepare(urls.filter(ChatPhotos.isImage)); return true }
        .sheet(isPresented: Binding(get: { !importing.isEmpty }, set: { if !$0 { importing = [] } })) {
            ImportSheet(store: store, items: $importing) { added in
                guard let last = added.max(by: { $0.takenAt < $1.takenAt }) else { return }
                areaValue = last.area.rawValue; angle = last.angle; afterID = last.id; beforeID = nil
            }
        }
        .sheet(item: $editing) { photo in
            PhotoEditor(store: store, photo: photo) { role, area, angle in
                areaValue = area.rawValue; self.angle = angle
                if role == .before { beforeID = photo.id } else { afterID = photo.id }
            }
        }
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker("Same angle, same light → see the change")
                    Text("Keep dated photos of your hair, hairline, face and body, compare any two from the same angle, and ask Claude what changed.").font(.system(size: 12)).foregroundStyle(Ink.muted)
                }
                Spacer()
                PrimaryButton(label: "Add photos…") { choose() }
            }
            areaTabs
            Label(area.tip, systemImage: "lightbulb").font(.system(size: 11)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            if album.photos(area).isEmpty { empty } else {
                angleChips
                if let currentAngle { compare(currentAngle) }
                timeline
            }
            Text("Photos stay on this Mac in Ascend’s Progress folder with their location data removed. Ask Ascend sees only which areas, angles and dates you have; an image reaches Claude only when you compare it or attach it to a chat, through your personal Claude profile.").font(.system(size: 11)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(.bottom, 10)
    }
    private var areaTabs: some View {
        HStack(spacing: 8) {
            ForEach(PhotoArea.allCases, id: \.self) { item in
                let count = album.photos(item).count
                Button { areaValue = item.rawValue; angle = nil; beforeID = nil; afterID = nil } label: {
                    HStack(spacing: 7) {
                        Image(systemName: item.symbol)
                        Text(item.label)
                        if count > 0 { Text("\(count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Ink.muted) }
                    }.font(.system(size: 12, weight: item == area ? .semibold : .regular)).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(item == area ? Ink.accent.opacity(0.14) : Ink.panel, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(item == area ? Ink.accent.opacity(0.5) : Ink.line))
                }.buttonStyle(.plain).foregroundStyle(item == area ? Ink.accent : .white)
            }
        }
    }
    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No \(area.label.lowercased()) photos yet.").font(.system(size: 18, weight: .semibold))
            Text("Choose Add photos… or drag photos onto this window. Ascend reads the date each photo was taken, and you pick the area and angle (\(area.angles.map { $0.label.lowercased() }.joined(separator: ", "))). Take the same angles every week or two to see real change.").font(.system(size: 12)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }
    private var angleChips: some View {
        HStack(spacing: 6) {
            Kicker("Angle")
            ForEach(album.angles(area), id: \.self) { item in
                Button { angle = item; beforeID = nil; afterID = nil } label: {
                    Text("\(item.label) · \(album.photos(area, angle: item).count)").font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(item == currentAngle ? Ink.accent.opacity(0.14) : .clear, in: Capsule())
                        .overlay(Capsule().stroke(item == currentAngle ? Ink.accent.opacity(0.5) : Ink.line))
                }.buttonStyle(.plain).foregroundStyle(item == currentAngle ? Ink.accent : Ink.muted)
            }
        }
    }
    private func label(_ photo: ProgressPhoto) -> String {
        let date = dateText(photo.day, engine: store.engine, pattern: "d MMM yyyy")
        return store.document.cycleDay(photo.day).map { "\(date) · Day \($0)" } ?? date
    }

    @ViewBuilder private func compare(_ angle: PhotoAngle) -> some View {
        let list = album.photos(area, angle: angle)
        if list.count < 2, let only = list.first {
            HStack(alignment: .top, spacing: 16) {
                AlbumImage(url: store.progressPhotoURL(only), maxPixel: 900).frame(width: 220, height: 280).clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 6) {
                    Text(label(only)).font(.system(size: 15, weight: .semibold))
                    Text("Your first \(angle.label.lowercased()) photo of your \(area.label.lowercased()). Add another from the same angle in a week or two to compare.").font(.system(size: 12)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    Button { store.askAscend(about: [only]) } label: { Label("Ask Ascend about it", systemImage: "sparkles").font(.system(size: 11)) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).panel(padding: 16)
        } else if let first = list.first, let last = list.last {
            let before = list.first { $0.id == beforeID } ?? first
            let after = list.first { $0.id == afterID } ?? last
            let days = Int(((after.takenAt - before.takenAt) / 86_400).rounded())
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    picker("Before", list: list, selection: before) { beforeID = $0 }
                    Image(systemName: "arrow.right").foregroundStyle(Ink.muted)
                    picker("After", list: list, selection: after) { afterID = $0 }
                    Text(days == 0 ? "Same day" : "\(abs(days)) day\(abs(days) == 1 ? "" : "s") \(days > 0 ? "apart" : "earlier")").font(.system(size: 11)).foregroundStyle(Ink.muted)
                    Spacer()
                    Button { store.askAscend(about: before.id == after.id ? [after] : [before, after]) } label: { Label("Ask Ascend", systemImage: "sparkles").font(.system(size: 11)) }
                        .help("Attach these photos to a chat message so you can discuss them with Claude")
                    Picker("View", selection: $overlay) { Text("Side by side").tag(false); Text("Overlay").tag(true) }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                if overlay {
                    ZStack {
                        AlbumImage(url: store.progressPhotoURL(before))
                        AlbumImage(url: store.progressPhotoURL(after)).opacity(blend)
                    }.frame(maxWidth: .infinity).frame(height: 480).clipShape(RoundedRectangle(cornerRadius: 9))
                    HStack { Text("Before").font(.system(size: 11)); Slider(value: $blend, in: 0...1).accessibilityLabel("Blend before and after"); Text("After").font(.system(size: 11)) }.foregroundStyle(Ink.muted)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        side("Before", before)
                        side("After", after)
                    }
                }
                Line()
                review(PhotoReviewController.Pair(before: before.id, after: after.id), same: before.id == after.id)
            }.panel(padding: 16)
        }
    }
    private func picker(_ title: String, list: [ProgressPhoto], selection: ProgressPhoto, set: @escaping (UUID) -> Void) -> some View {
        Picker(title, selection: Binding(get: { selection.id }, set: set)) {
            ForEach(list) { Text(label($0)).tag($0.id) }
        }.fixedSize()
    }
    private func side(_ title: String, _ photo: ProgressPhoto) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AlbumImage(url: store.progressPhotoURL(photo)).frame(maxWidth: .infinity).frame(height: 420).background(Color.black.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 9))
                .onTapGesture(count: 2) { NSWorkspace.shared.open(store.progressPhotoURL(photo)) }.help("Double-click to open full size")
            HStack { Kicker(title); Text(label(photo)).font(.system(size: 11)).foregroundStyle(Ink.muted) }
            if !photo.note.isEmpty { Text(photo.note).font(.system(size: 11)).foregroundStyle(Ink.muted).lineLimit(2) }
        }.frame(maxWidth: .infinity)
    }
    @ViewBuilder private func review(_ pair: PhotoReviewController.Pair, same: Bool) -> some View {
        let existing = album.review(before: pair.before, after: pair.after)
        let busy = reviews.working == pair
        VStack(alignment: .leading, spacing: 8) {
            if let existing {
                let c = existing.comparison
                HStack(spacing: 8) {
                    Text(c.trend.capitalized).font(.system(size: 11, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(trendColor(c.trend).opacity(0.18), in: Capsule()).foregroundStyle(trendColor(c.trend))
                    Text("Claude · \(c.confidence) confidence").font(.system(size: 11)).foregroundStyle(Ink.muted)
                    Spacer()
                    if savedNotes.contains(existing.id) { Label("Saved to Notes", systemImage: "checkmark").font(.system(size: 11)).foregroundStyle(Ink.accent) }
                    else { Button("Save as note") { if store.saveReviewAsNote(existing) { savedNotes.insert(existing.id) } }.font(.system(size: 11)) }
                    Button("Compare again") { reviews.compare(pair) }.font(.system(size: 11)).disabled(reviews.working != nil)
                }
                Text(c.summary).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                ForEach(c.changes, id: \.self) { Text("•  \($0)").font(.system(size: 12)).foregroundStyle(.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true) }
                if !c.conditions.isEmpty { Label(c.conditions, systemImage: "camera").font(.system(size: 11)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true) }
            } else if busy {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Claude is comparing the two photos…").font(.system(size: 12)).foregroundStyle(Ink.muted) }
            } else {
                HStack {
                    Text(same ? "Pick two different photos to compare." : "Claude can describe what changed: hairline, density, leanness, skin or shape, and whether the light or angle differs.").font(.system(size: 12)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    PrimaryButton(label: "Ask Claude to compare") { reviews.compare(pair) }.disabled(same || reviews.working != nil)
                }
            }
            if let error = reviews.errors[pair] { Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private func trendColor(_ trend: String) -> Color { trend == "better" ? .green : trend == "worse" ? .orange : Ink.muted }

    private var timeline: some View {
        let list = album.photos(area).reversed().map { $0 }
        return VStack(alignment: .leading, spacing: 10) {
            Kicker("All \(area.label.lowercased()) photos · \(list.count)")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(list) { photo in
                    Button { editing = photo } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            AlbumImage(url: store.progressPhotoURL(photo), maxPixel: 400, fill: true).frame(width: 132, height: 164).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(photo.angle == currentAngle ? Ink.accent.opacity(0.45) : Ink.line))
                            Text(dateText(photo.day, engine: store.engine, pattern: "d MMM yyyy")).font(.system(size: 11, weight: .medium))
                            Text(photo.angle.label + (store.document.cycleDay(photo.day).map { " · Day \($0)" } ?? "")).font(.system(size: 10)).foregroundStyle(Ink.muted)
                        }.frame(width: 132, alignment: .leading)
                    }.buttonStyle(.plain).help("Edit, or use in the comparison")
                        .contextMenu {
                            Button("Compare as before") { angle = photo.angle; beforeID = photo.id; if afterID.flatMap({ id in album.photos(area, angle: photo.angle).first { $0.id == id } }) == nil { afterID = nil } }
                            Button("Compare as after") { angle = photo.angle; afterID = photo.id; if beforeID.flatMap({ id in album.photos(area, angle: photo.angle).first { $0.id == id } }) == nil { beforeID = nil } }
                            Button("Ask Ascend about this photo") { store.askAscend(about: [photo]) }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.progressPhotoURL(photo)]) }
                        }
                }
            }
        }
    }
    private func choose() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true; panel.message = "Choose progress photos"
        if panel.runModal() == .OK { prepare(panel.urls) }
    }
    private func prepare(_ urls: [URL]) {
        let zone = store.engine.calendar.timeZone
        let angle = currentAngle ?? area.angles[0]
        importing = urls.prefix(ImportItem.limit).map { ImportItem(url: $0, date: min(PhotoAlbum.captureDate(of: $0, timeZone: zone) ?? Date(), Date()), area: area, angle: angle) }
        if urls.count > ImportItem.limit { store.notice = "Added the first \(ImportItem.limit) photos. Add the rest in another batch." }
    }
}

struct ImportItem: Identifiable {
    static let limit = 30
    let id = UUID()
    var url: URL
    var date: Date
    var area: PhotoArea
    var angle: PhotoAngle
    var note = ""
}
private struct ImportSheet: View {
    @ObservedObject var store: TrackerStore
    @Binding var items: [ImportItem]
    var done: ([ProgressPhoto]) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add \(items.count) photo\(items.count == 1 ? "" : "s")").font(.system(size: 20, weight: .semibold))
            Text("Dates come from when each photo was taken; fix any that are wrong. Pick what each photo shows.").font(.system(size: 12)).foregroundStyle(Ink.muted)
            if items.count > 1 {
                HStack(spacing: 10) {
                    Kicker("Set all")
                    Menu("Area") { ForEach(PhotoArea.allCases, id: \.self) { a in Button(a.label) { for i in items.indices { setArea(i, a) } } } }.fixedSize()
                    Menu("Angle") { ForEach(PhotoAngle.allCases, id: \.self) { a in Button(a.label) { for i in items.indices { items[i].angle = a } } } }.fixedSize()
                }
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach($items) { $item in
                        HStack(alignment: .top, spacing: 12) {
                            AlbumImage(url: item.url, maxPixel: 300, fill: true).frame(width: 76, height: 96).clipped().clipShape(RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    DatePicker("Taken", selection: $item.date, in: ...Date(), displayedComponents: [.date, .hourAndMinute]).labelsHidden().fixedSize()
                                    Picker("Area", selection: Binding(get: { item.area }, set: { a in if let i = items.firstIndex(where: { $0.id == item.id }) { setArea(i, a) } })) {
                                        ForEach(PhotoArea.allCases, id: \.self) { Text($0.label).tag($0) }
                                    }.labelsHidden().fixedSize()
                                    Picker("Angle", selection: $item.angle) { ForEach(PhotoAngle.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden().fixedSize()
                                    Spacer()
                                    Button { items.removeAll { $0.id == item.id } } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Ink.muted).accessibilityLabel("Skip this photo")
                                }
                                TextField("Note (optional, for example: hair still damp, new lighting)", text: $item.note).textFieldStyle(.roundedBorder).font(.system(size: 12))
                                Text(item.url.lastPathComponent).font(.system(size: 10)).foregroundStyle(Ink.muted).lineLimit(1)
                            }
                        }.padding(10).background(Ink.panel, in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }.frame(minHeight: 200, maxHeight: 460)
            HStack {
                Spacer()
                Button("Cancel") { items = []; dismiss() }.keyboardShortcut(.cancelAction)
                PrimaryButton(label: "Add \(items.count) photo\(items.count == 1 ? "" : "s")") { add() }.disabled(items.isEmpty).keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 720).background(Ink.background)
    }
    /// Switching area keeps the angle when it fits, otherwise picks the area's usual one.
    private func setArea(_ i: Int, _ area: PhotoArea) {
        items[i].area = area
        if !area.angles.contains(items[i].angle) { items[i].angle = area.angles[0] }
    }
    private func add() {
        var added: [ProgressPhoto] = [], failures: [String] = []
        for item in items {
            do { added.append(try store.addProgressPhoto(item.url, takenAt: item.date, area: item.area, angle: item.angle, note: item.note)) }
            catch { failures.append(error.localizedDescription) }
        }
        if !failures.isEmpty { store.notice = failures.joined(separator: "\n") }
        done(added); items = []; dismiss()
    }
}
private struct PhotoEditor: View {
    enum Role { case before, after }
    @ObservedObject var store: TrackerStore
    var photo: ProgressPhoto
    var use: (Role, PhotoArea, PhotoAngle) -> Void
    @State private var date = Date()
    @State private var area = PhotoArea.hair
    @State private var angle = PhotoAngle.front
    @State private var note = ""
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            AlbumImage(url: store.progressPhotoURL(photo), maxPixel: 1400).frame(width: 380, height: 500).background(Color.black.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 14) {
                Text("Progress photo").font(.system(size: 20, weight: .semibold))
                VStack(alignment: .leading, spacing: 5) { Kicker("Taken"); DatePicker("Taken", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute]).labelsHidden() }
                VStack(alignment: .leading, spacing: 5) {
                    Kicker("Shows")
                    HStack {
                        Picker("Area", selection: $area) { ForEach(PhotoArea.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden().fixedSize()
                        Picker("Angle", selection: $angle) { ForEach(PhotoAngle.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden().fixedSize()
                    }
                }
                VStack(alignment: .leading, spacing: 5) { Kicker("Note"); TextField("Note", text: $note, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder).font(.system(size: 12)) }
                HStack {
                    Button("Use as before") { save(); use(.before, area, angle); dismiss() }
                    Button("Use as after") { save(); use(.after, area, angle); dismiss() }
                }.font(.system(size: 12))
                Spacer()
                HStack {
                    Button("Delete…") { confirmDelete = true }.font(.system(size: 12))
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    PrimaryButton(label: "Save") { save(); dismiss() }.keyboardShortcut(.defaultAction)
                }
            }.frame(width: 300)
        }.padding(22).frame(height: 544).background(Ink.background)
            .onAppear { date = Date(timeIntervalSince1970: photo.takenAt); area = photo.area; angle = photo.angle; note = photo.note }
            .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete photo", role: .destructive) { store.deleteProgressPhoto(photo.id); dismiss() }; Button("Cancel", role: .cancel) {}
            } message: { Text("Its comparisons are removed too. Undo is available until your next edit.") }
    }
    private func save() {
        let changed = abs(date.timeIntervalSince1970 - photo.takenAt) >= 60 || area != photo.area || angle != photo.angle || note != photo.note
        if changed { store.updateProgressPhoto(photo.id, takenAt: date, area: area, angle: angle, note: note) }
    }
}

/// Picks album photos to attach to an Ask Ascend message.
struct ProgressPhotoPicker: View {
    @ObservedObject var store: TrackerStore
    var limit: Int
    var attach: ([ProgressPhoto]) -> Void
    @State private var area = PhotoArea.hair
    @State private var picked: [UUID] = []
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let album = store.document.photos
        VStack(alignment: .leading, spacing: 14) {
            Text("Attach progress photos").font(.system(size: 20, weight: .semibold))
            Text("Pick up to \(limit). Each one is labelled with its area, angle and date so Claude knows what it's looking at.").font(.system(size: 12)).foregroundStyle(Ink.muted)
            Picker("Area", selection: $area) { ForEach(PhotoArea.allCases, id: \.self) { Text("\($0.label) · \(album.photos($0).count)").tag($0) } }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                let list = album.photos(area).reversed().map { $0 }
                if list.isEmpty { Text("No \(area.label.lowercased()) photos yet. Add them on the Photos screen.").font(.system(size: 12)).foregroundStyle(Ink.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(list) { photo in
                        let index = picked.firstIndex(of: photo.id)
                        Button { toggle(photo.id) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                AlbumImage(url: store.progressPhotoURL(photo), maxPixel: 400, fill: true).frame(width: 108, height: 134).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(index == nil ? Ink.line : Ink.accent, lineWidth: index == nil ? 1 : 2))
                                    .overlay(alignment: .topTrailing) {
                                        if let index { Text("\(index + 1)").font(.system(size: 11, weight: .bold)).frame(width: 20, height: 20).background(Ink.accent, in: Circle()).foregroundStyle(Ink.background).padding(5) }
                                    }
                                Text(dateText(photo.day, engine: store.engine, pattern: "d MMM yyyy")).font(.system(size: 11, weight: .medium))
                                Text(photo.angle.label).font(.system(size: 10)).foregroundStyle(Ink.muted)
                            }.frame(width: 108, alignment: .leading)
                        }.buttonStyle(.plain).disabled(index == nil && picked.count >= limit)
                    }
                }
            }.frame(height: 380)
            HStack {
                Text(picked.isEmpty ? "Tip: pick the oldest and newest of the same angle." : "\(picked.count) of \(limit) picked").font(.system(size: 11)).foregroundStyle(Ink.muted)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                PrimaryButton(label: picked.count == 1 ? "Attach 1 photo" : "Attach \(picked.count) photos") {
                    attach(picked.compactMap { id in album.photos.first { $0.id == id } }); dismiss()
                }.disabled(picked.isEmpty).keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 640).background(Ink.background)
            .onAppear { if album.photos(area).isEmpty, let first = PhotoArea.allCases.first(where: { !album.photos($0).isEmpty }) { area = first } }
    }
    private func toggle(_ id: UUID) {
        if let i = picked.firstIndex(of: id) { picked.remove(at: i) } else if picked.count < limit { picked.append(id) }
    }
}
