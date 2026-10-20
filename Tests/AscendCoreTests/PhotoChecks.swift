import Foundation
import ImageIO
import UniformTypeIdentifiers
import AscendCore

private struct PhotoFailure: Error { let message: String }
private func expect(_ test: Bool, _ message: String = "Assertion failed") throws { if !test { throw PhotoFailure(message: message) } }
private func refuses(_ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw PhotoFailure(message: "Expected rejection")
}
/// A small JPEG with optional EXIF capture time/offset and GPS, like a phone camera writes.
private func cameraJPEG(at url: URL, taken: String?, offset: String? = nil) throws {
    let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0.6, green: 0.4, blue: 0.3, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
    let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    var exif: [CFString: Any] = [:]
    if let taken { exif[kCGImagePropertyExifDateTimeOriginal] = taken }
    if let offset { exif[kCGImagePropertyExifOffsetTimeOriginal] = offset }
    let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 12.97, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 77.59, kCGImagePropertyGPSLongitudeRef: "E"]
    CGImageDestinationAddImage(writer, context.makeImage()!, [kCGImagePropertyExifDictionary: exif, kCGImagePropertyGPSDictionary: gps] as CFDictionary)
    try expect(CGImageDestinationFinalize(writer), "Test JPEG written")
}

func runPhotoChecks() async -> (count: Int, failures: Int) {
    var count = 0, failures = 0
    func check(_ name: String, _ body: () throws -> Void) {
        count += 1
        do { try body(); print("PASS: \(name)") } catch { failures += 1; print("FAIL: \(name): \(error)") }
    }
    let original = TrackerDocument.seeded(today: "2026-10-01")
    let engine = TrackerEngine(document: original)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ascend-photo-checks-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    func photo(_ day: String, _ area: PhotoArea, _ angle: PhotoAngle, hour: Int = 9, note: String = "") -> ProgressPhoto {
        let at = engine.date(day)!.addingTimeInterval(Double(hour - 12) * 3600)
        return ProgressPhoto(takenAt: at.timeIntervalSince1970, day: day, area: area, angle: angle, photo: "\(UUID().uuidString.lowercased()).jpg", note: note)
    }

    check("the album sorts by date, lists used angles in the area's order and survives a save") {
        var doc = original
        let late = photo("2026-10-20", .hair, .top), early = photo("2026-10-02", .hair, .top), back = photo("2026-10-05", .hair, .back), face = photo("2026-10-03", .face, .front)
        doc.photos.photos = [late, back, face, early]
        doc.photos.reviews = [PhotoReview(before: early.id, after: late.id, comparison: PhotoComparison(trend: "better", summary: "Less scalp at the crown."))]
        try doc.validate()
        try expect(doc.photos.photos(.hair, angle: .top).map(\.id) == [early.id, late.id])
        try expect(doc.photos.photos(.hair).map(\.id) == [early.id, back.id, late.id])
        try expect(doc.photos.angles(.hair) == [.top, .back] && doc.photos.angles(.body).isEmpty)
        let decoded = try JSONDecoder().decode(TrackerDocument.self, from: try JSONEncoder().encode(doc))
        try expect(decoded.photos == doc.photos && decoded.photos.review(before: early.id, after: late.id)?.comparison.trend == "better")
        doc.photos.remove(early.id)
        try expect(doc.photos.photos.count == 3 && doc.photos.reviews.isEmpty, "Deleting a photo drops its comparisons")
    }
    check("older tracker files without photos still load, and broken photo records are rejected") {
        var json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(original)) as! [String: Any]
        json.removeValue(forKey: "photos")
        let decoded = try JSONDecoder().decode(TrackerDocument.self, from: try JSONSerialization.data(withJSONObject: json))
        try expect(decoded.photos.photos.isEmpty)
        for broken in [{ (p: inout ProgressPhoto) in p.photo = "../tracker.json" }, { $0.day = "not-a-day" }, { $0.takenAt = .nan }, { $0.note = String(repeating: "x", count: 501) }] {
            var doc = original, p = photo("2026-10-02", .body, .front)
            broken(&p); doc.photos.photos = [p]
            try refuses { try doc.validate() }
        }
        var doc = original, p = photo("2026-10-02", .body, .front)
        doc.photos.photos = [p, p]
        try refuses { try doc.validate() }
        p = photo("2026-10-03", .body, .front)
        doc.photos.photos = [p]
        doc.photos.reviews = [PhotoReview(before: p.id, after: p.id, comparison: PhotoComparison(trend: "AMAZING", summary: "x"))]
        try refuses { try doc.validate() }
    }
    check("the capture date comes from the camera's EXIF time, read in the tracker's time zone or the photo's own offset") {
        let zone = TimeZone(identifier: "Asia/Kolkata")!
        let plain = folder.appendingPathComponent("plain.jpg"), offset = folder.appendingPathComponent("offset.jpg"), none = folder.appendingPathComponent("none.jpg")
        try cameraJPEG(at: plain, taken: "2026:10:18 08:30:00")
        try cameraJPEG(at: offset, taken: "2026:10:18 08:30:00", offset: "+01:00")
        try cameraJPEG(at: none, taken: nil)
        let f = ISO8601DateFormatter()
        try expect(PhotoAlbum.captureDate(of: plain, timeZone: zone) == f.date(from: "2026-10-18T03:00:00Z"), "08:30 IST")
        try expect(PhotoAlbum.captureDate(of: offset, timeZone: zone) == f.date(from: "2026-10-18T07:30:00Z"), "08:30 +01:00")
        let created = try none.resourceValues(forKeys: [.creationDateKey]).creationDate
        try expect(created != nil && PhotoAlbum.captureDate(of: none, timeZone: zone) == created, "No EXIF falls back to the file date")
    }
    check("stored copies keep up to 2048 px but lose the camera's date and location") {
        let source = folder.appendingPathComponent("camera.jpg")
        try cameraJPEG(at: source, taken: "2026:10:18 08:30:00")
        let stored = folder.appendingPathComponent("store", isDirectory: true)
        let name = try ChatPhotos.store(source, in: stored, maxPixel: PhotoAlbum.maxPixelSize)
        let reader = CGImageSourceCreateWithURL(stored.appendingPathComponent(name) as CFURL, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(reader, 0, nil) as! [CFString: Any]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        try expect(exif?[kCGImagePropertyExifDateTimeOriginal] == nil && properties[kCGImagePropertyGPSDictionary] == nil, "Metadata stripped")
        try expect(PhotoAlbum.maxPixelSize > ChatPhotos.maxPixelSize)
    }
    check("Claude's comparison is normalised, and the compare run sends exactly the two photos with no tools or saved session") {
        let messy = PhotoComparison(trend: "Better", summary: "  ", changes: (0..<12).map { "Change \($0)" } + ["  "], conditions: String(repeating: "c", count: 900), confidence: "certain").validated()
        try expect(messy.trend == "better" && messy.summary == "No clear difference described." && messy.changes.count == 8 && messy.conditions.count == 400 && messy.confidence == "medium")
        try expect(PhotoComparison(trend: "glowing", summary: "x").validated().trend == "unclear")
        let args = ClaudeAssistant.photoArguments(model: .sonnet)
        try expect(args.contains("--no-session-persistence") && args[args.firstIndex(of: "--tools")! + 1] == "" && args.contains("--json-schema"))
        let a = folder.appendingPathComponent("a.jpg"), b = folder.appendingPathComponent("b.jpg")
        try cameraJPEG(at: a, taken: nil); try cameraJPEG(at: b, taken: nil)
        var before = photo("2026-10-02", .hairline, .front, note: "hair dry"), after = photo("2026-10-23", .hairline, .front)
        let input = try ClaudeAssistant.photoInput(before: before, after: after, beforeFile: a, afterFile: b)
        let message = try JSONSerialization.jsonObject(with: Data(input.utf8)) as! [String: Any]
        let content = (message["message"] as! [String: Any])["content"] as! [[String: Any]]
        try expect(content.filter { $0["type"] as? String == "image" }.count == 2)
        let text = content.last!["text"] as! String
        try expect(text.contains("Hairline") && text.contains("2026-10-02") && text.contains("21 days later") && text.contains("hair dry") && !text.contains("angles differ"))
        after.angle = .left
        try expect((try ClaudeAssistant.photoInput(before: before, after: after, beforeFile: a, afterFile: b)).contains("angles differ"))
        before.area = .face
        try refuses { _ = try ClaudeAssistant.photoInput(before: before, after: after, beforeFile: a, afterFile: b) }
        let structured: [String: Any] = ["trend": "same", "summary": "No visible change at the temples.", "changes": ["Temples: same position"], "conditions": "Second photo is warmer light.", "confidence": "low"]
        let line = String(data: try JSONSerialization.data(withJSONObject: ["type": "result", "is_error": false, "structured_output": structured]), encoding: .utf8)!
        let decoded = try ClaudeAssistant.decodePhotoComparison(ClaudeProcessOutput(status: 0, stdout: Data(line.utf8)))
        try expect(decoded.trend == "same" && decoded.changes == ["Temples: same position"] && decoded.confidence == "low")
    }
    check("Ask Ascend sees which areas, angles and dates the album has, never notes, reviews or file names; cycle days count from the cycle start") {
        var doc = original
        let p = photo("2026-10-02", .body, .front, note: "PHOTO_NOTE_SENTINEL")
        let again = photo("2026-10-02", .body, .front, hour: 18), later = photo("2026-10-04", .body, .front), crown = photo("2026-10-03", .hair, .top)
        doc.photos.photos = [later, p, crown, again]
        doc.photos.reviews = [PhotoReview(before: p.id, after: p.id, comparison: PhotoComparison(trend: "same", summary: "REVIEW_SENTINEL"))]
        let context = String(decoding: try ClaudeAssistant.contextData(document: doc, today: "2026-10-05"), as: UTF8.self)
        try expect(!context.contains("PHOTO_NOTE_SENTINEL") && !context.contains("REVIEW_SENTINEL") && !context.contains(p.photo))
        try expect(doc.photos.summary == [
            PhotoAlbumSummary(area: "hair", angle: "top", count: 1, first: "2026-10-03", latest: "2026-10-03", dates: ["2026-10-03"]),
            PhotoAlbumSummary(area: "body", angle: "front", count: 3, first: "2026-10-02", latest: "2026-10-04", dates: ["2026-10-02", "2026-10-04"])])
        try expect(context.contains("photoAlbum") && context.contains("2026-10-04"))
        try expect(doc.cycleDay(doc.cycle.start) == 1 && doc.cycleDay(engine.adding(9, to: doc.cycle.start)) == 10)
        try expect(doc.cycleDay(engine.adding(-1, to: doc.cycle.start)) == nil && doc.cycleDay(engine.adding(1, to: doc.cycle.end)) == nil)
    }
    if ProcessInfo.processInfo.environment["ASCEND_LIVE_CLAUDE"] == "1" {
        // Opt-in: a real compare run on two drawn "scalp" images, sparse then dense. Nothing is saved.
        count += 1
        do {
            guard let executable = ClaudeAssistant.locateExecutable(override: "") else { throw PhotoFailure(message: "Claude Code not found") }
            func scalp(_ url: URL, strands: Int) throws {
                let size = 512
                let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
                context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.88, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: size, height: size))
                context.setFillColor(CGColor(red: 0.85, green: 0.68, blue: 0.56, alpha: 1)); context.fillEllipse(in: CGRect(x: 56, y: 56, width: 400, height: 400))
                var seed: UInt64 = 7
                func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
                context.setStrokeColor(CGColor(red: 0.12, green: 0.09, blue: 0.07, alpha: 1)); context.setLineWidth(2)
                for _ in 0..<strands {
                    let angle = next() * 2 * .pi, radius = sqrt(next()) * 190
                    let x = 256 + cos(angle) * radius, y = 256 + sin(angle) * radius
                    context.move(to: CGPoint(x: x, y: y)); context.addLine(to: CGPoint(x: x + (next() - 0.5) * 30, y: y + 16 + next() * 14))
                }
                context.strokePath()
                let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
                CGImageDestinationAddImage(writer, context.makeImage()!, nil)
                try expect(CGImageDestinationFinalize(writer))
            }
            let a = folder.appendingPathComponent("live-before.jpg"), b = folder.appendingPathComponent("live-after.jpg")
            try scalp(a, strands: 250); try scalp(b, strands: 2500)
            let before = photo("2026-10-02", .hair, .top), after = photo("2026-12-20", .hair, .top)
            let output = try await ProcessClaudeLauncher(timeout: 240).run(ClaudeInvocation(executable: executable,
                arguments: ClaudeAssistant.photoArguments(model: .sonnet, effort: .medium),
                environment: ClaudeAssistant.environment(base: ProcessInfo.processInfo.environment, configDirectory: ClaudeAssistant.defaultConfigDirectory),
                directory: FileManager.default.temporaryDirectory, input: try ClaudeAssistant.photoInput(before: before, after: after, beforeFile: a, afterFile: b)))
            let c = try ClaudeAssistant.decodePhotoComparison(output)
            print("  live compare: \(c.trend) · \(c.confidence) · \(c.summary)")
            for change in c.changes { print("    - \(change)") }
            if !c.conditions.isEmpty { print("    conditions: \(c.conditions)") }
            try expect(PhotoComparison.trends.contains(c.trend) && c.trend != "worse", "Denser hair shouldn't read as worse")
            print("PASS: live Claude compares two progress photos")
        } catch { failures += 1; print("FAIL: live Claude compares two progress photos: \(error)") }
        // Asked to "check the photos in the app" with none attached, Ask Ascend should say which to attach and how, not claim to see them.
        count += 1
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("ascend-live-\(UUID().uuidString)")
        let session = UUID()
        do {
            guard let executable = ClaudeAssistant.locateExecutable(override: "") else { throw PhotoFailure(message: "Claude Code not found") }
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            var doc = original
            doc.photos.photos = [photo("2026-10-02", .hair, .top), photo("2026-10-16", .hair, .top), photo("2026-10-16", .hairline, .front), photo("2026-10-16", .hair, .back)]
            let output = try await ProcessClaudeLauncher(timeout: 240).run(ClaudeInvocation(executable: executable,
                arguments: ClaudeAssistant.arguments(model: .sonnet, session: session, resume: false),
                environment: ClaudeAssistant.environment(base: ProcessInfo.processInfo.environment, configDirectory: ClaudeAssistant.defaultConfigDirectory),
                directory: workspace, input: try ClaudeAssistant.inputLine(ClaudeAssistant.prompt("its in the photos database in the app, pls check my norwood", document: doc, today: "2026-10-20", shareHistory: false))))
            let reply = try ClaudeAssistant.decode(output).message
            print("  live album reply: \(reply.replacingOccurrences(of: "\n", with: " ").prefix(500))")
            try expect(reply.localizedCaseInsensitiveContains("progress photos") && reply.contains("2"), "Should point to Photo ▾ → From progress photos and name dates")
            print("PASS: live Claude asks for specific album photos when none are attached")
        } catch { failures += 1; print("FAIL: live Claude asks for specific album photos when none are attached: \(error)") }
        try? FileManager.default.removeItem(at: ClaudeAssistant.transcriptURL(session: session, workspace: workspace, configDirectory: ClaudeAssistant.defaultConfigDirectory).deletingLastPathComponent())
        try? FileManager.default.removeItem(at: workspace)
    }
    check("attached album photos are captioned in attachment order so Claude knows which image is which") {
        var doc = original
        doc.cycle.start = "2026-10-01"
        let crown = photo("2026-10-03", .hair, .top, note: "hair damp")
        try expect(doc.caption(crown) == "Hair · top · 2026-10-03 (cycle day 3) · note: hair damp")
        try expect(ClaudeAssistant.captioned("how is it?", captions: [nil, nil]) == "how is it?")
        let text = ClaudeAssistant.captioned("check my crown", captions: [nil, doc.caption(crown), "Face · front · 2026-10-04"])
        try expect(text == "check my crown\n\n[Attached from my Photos album]\n2. Hair · top · 2026-10-03 (cycle day 3) · note: hair damp\n3. Face · front · 2026-10-04")
        try expect(ClaudeAssistant.captioned("", captions: ["Body · back · 2026-10-02"]) == "[Attached from my Photos album]\n1. Body · back · 2026-10-02")
        try expect(ClaudeAssistant.systemPrompt.contains("From progress photos"))
    }
    return (count, failures)
}
