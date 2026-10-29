import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import AscendCore

private struct LinkFailure: Error { let message: String }
/// Takes a plain value so call sites can use `try`/`await` inside the condition.
private func expect(_ test: Bool, _ message: String = "Assertion failed") throws {
    if !test { throw LinkFailure(message: message) }
}
private func refuses(_ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw LinkFailure(message: "Expected rejection")
}
/// Collects hub events; the pairing handler accepts or declines from a detached task, like a click on the Mac.
private final class Recorder: @unchecked Sendable {
    let lock = NSLock()
    var hub: PhoneLinkHub?
    var accept = true
    var pairing: PairingRequest?
    var finished: [Bool] = []
    var snapshots: [HealthSnapshot] = []
    var meals: [PhoneMeal] = []
    var urges: [PhoneUrge] = []
    var medPhotos: [PhoneMedPhoto] = []
    var doses: [PhoneDose] = []
    var checkIns: [PhoneCheckIn] = []
    func deliver(_ event: PhoneLinkEvent) async -> PhoneLinkResult {
        switch event {
        case .pairingRequested(let request):
            lock.withLock { pairing = request }
            let hub = hub, accept = accept
            Task { await hub?.respond(to: request.phoneID, accept: accept) }
            return PhoneLinkResult(ok: true, message: "")
        case .pairingFinished(_, let accepted): lock.withLock { finished.append(accepted) }; return PhoneLinkResult(ok: accepted, message: "")
        case .hello: return PhoneLinkResult(ok: true, message: "hello")
        case .snapshot(let snapshot, _):
            do { try snapshot.validate(expectedRequestID: snapshot.requestID) } catch { return PhoneLinkResult(ok: false, message: "invalid snapshot") }
            lock.withLock { snapshots.append(snapshot) }; return PhoneLinkResult(ok: true, message: "snapshot ok")
        case .meal(let meal, _):
            do { _ = try meal.validated() } catch { return PhoneLinkResult(ok: false, message: "invalid meal") }
            lock.withLock { meals.append(meal) }; return PhoneLinkResult(ok: true, message: "meal ok")
        case .urge(let urge, _):
            do { _ = try urge.validated() } catch { return PhoneLinkResult(ok: false, message: "invalid urge") }
            lock.withLock { urges.append(urge) }; return PhoneLinkResult(ok: true, message: "urge ok", urges: ["todayPassed": 1])
        case .medPhoto(let photo, _):
            do { _ = try photo.validated() } catch { return PhoneLinkResult(ok: false, message: "invalid med photo") }
            lock.withLock { medPhotos.append(photo) }
            return PhoneLinkResult(ok: true, message: "med photo ok", meds: [PhoneMedDose(medID: UUID().uuidString, name: "Finasteride", detail: "1 mg", day: "2026-10-20", minute: 540, at: 1_792_468_800, taken: false)], today: TrackerDocument.seeded(today: "2026-10-18").phoneToday(today: "2026-10-20"))
        case .dose(let dose, _):
            lock.withLock { doses.append(dose) }; return PhoneLinkResult(ok: true, message: "dose ok")
        case .checkIn(let checkIn, _):
            lock.withLock { checkIns.append(checkIn) }; return PhoneLinkResult(ok: true, message: "checkin ok")
        }
    }
}
/// A phone written in Swift, used to drive the hub without the network.
private struct SwiftPhone {
    let id = UUID().uuidString.lowercased()
    let privateKey = Curve25519.KeyAgreement.PrivateKey()
    var key: SymmetricKey?
    func startBody() -> Data {
        try! JSONSerialization.data(withJSONObject: ["phoneID": id, "phoneName": "Test Pixel", "phoneKey": PhoneLinkCrypto.encode(privateKey.publicKey)])
    }
    /// Mirrors the Android derivation (mac key ‖ phone key) to show both ends agree.
    mutating func finish(_ response: LinkResponse) throws -> String {
        let json = try JSONSerialization.jsonObject(with: response.body) as! [String: Any]
        let mac = try PhoneLinkCrypto.decodePublicKey(json["macKey"] as! String)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: mac)
        key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("ascend-link-v1".utf8), sharedInfo: mac.rawRepresentation + privateKey.publicKey.rawRepresentation, outputByteCount: 32)
        return PhoneLinkCrypto.pairingCode(mac: mac, phone: privateKey.publicKey)
    }
    func request(_ path: String, _ envelope: LinkEnvelope, key override: SymmetricKey? = nil) throws -> LinkRequest {
        LinkRequest(method: "POST", path: path, headers: ["X-Ascend-Phone": id], body: try PhoneLinkCrypto.seal(try JSONEncoder().encode(envelope), key: override ?? key!))
    }
    func reply(_ response: LinkResponse) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: try PhoneLinkCrypto.open(response.body, key: key!)) as! [String: Any]
    }
}
private func snapshot(now: Date = Date()) -> HealthSnapshot {
    let t = now.timeIntervalSince1970.rounded(.down)
    return HealthSnapshot(requestID: UUID().uuidString, generatedAt: t, rangeStart: t - 86400, rangeEnd: t,
        permissions: Dictionary(uniqueKeysWithValues: HealthMetric.allCases.map { ($0.rawValue, true) }),
        records: [HealthRecord(id: "hr-1:0", metric: .heartRate, start: t - 600, end: t - 600, value: 70)])
}
private func jpegBase64() -> String {
    let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
    let data = NSMutableData()
    let writer = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(writer, context.makeImage()!, nil); CGImageDestinationFinalize(writer)
    return (data as Data).base64EncodedString()
}

func runLinkChecks() async -> (count: Int, failures: Int) {
    var count = 0, failures = 0
    func check(_ name: String, _ body: () throws -> Void) {
        count += 1
        do { try body(); print("PASS: \(name)") } catch { failures += 1; print("FAIL: \(name): \(error)") }
    }
    func checkAsync(_ name: String, _ body: () async throws -> Void) async {
        count += 1
        do { try await body(); print("PASS: \(name)") } catch { failures += 1; print("FAIL: \(name): \(error)") }
    }
    let day = "2026-10-19"
    let original = TrackerDocument.seeded(today: day)

    check("link crypto: X.509 key encoding, matching session keys and pairing codes, sealed round trip") {
        let mac = Curve25519.KeyAgreement.PrivateKey(), phone = Curve25519.KeyAgreement.PrivateKey()
        let encoded = PhoneLinkCrypto.encode(phone.publicKey)
        try expect(Data(base64Encoded: encoded)!.count == 44)
        try expect(try PhoneLinkCrypto.decodePublicKey(encoded).rawRepresentation == phone.publicKey.rawRepresentation)
        try expect(try PhoneLinkCrypto.decodePublicKey(phone.publicKey.rawRepresentation.base64EncodedString()).rawRepresentation == phone.publicKey.rawRepresentation)
        try refuses { _ = try PhoneLinkCrypto.decodePublicKey("bm90IGEga2V5") }
        let key = try PhoneLinkCrypto.sessionKey(mac, phone: phone.publicKey)
        let code = PhoneLinkCrypto.pairingCode(mac: mac.publicKey, phone: phone.publicKey)
        try expect(code.count == 6 && code.allSatisfy(\.isNumber))
        let sealed = try PhoneLinkCrypto.seal(Data("hello".utf8), key: key)
        try expect(sealed.count == 12 + 5 + 16 && (try PhoneLinkCrypto.open(sealed, key: key)) == Data("hello".utf8))
        try refuses { _ = try PhoneLinkCrypto.open(sealed, key: SymmetricKey(size: .bits256)) }
        var tampered = sealed; tampered[14] ^= 1
        try refuses { _ = try PhoneLinkCrypto.open(tampered, key: key) }
    }
    await checkAsync("link pairing needs the Mac to open pairing and confirm the code; declined phones get no key") {
        let recorder = Recorder(), keys = MemoryPhoneKeyStore()
        let hub = PhoneLinkHub(macName: "Test Mac", keyStore: keys) { await recorder.deliver($0) }
        recorder.hub = hub
        var phone = SwiftPhone()
        let closed = await hub.handle(LinkRequest(method: "POST", path: "/pair/start", body: phone.startBody()))
        try expect(closed.status == 403 && String(decoding: closed.body, as: UTF8.self).contains("Pair phone"))
        await hub.openPairing()
        let started = await hub.handle(LinkRequest(method: "POST", path: "/pair/start", body: phone.startBody()))
        try expect(started.status == 200)
        let code = try phone.finish(started)
        try expect(recorder.lock.withLock { recorder.pairing?.code } == code, "Mac and phone codes differ")
        var confirmed: LinkResponse?
        for _ in 0..<50 {
            let response = await hub.handle(try phone.request("/pair/confirm", LinkEnvelope(kind: "pair")))
            if response.status == 200 { confirmed = response; break }
            try expect(response.status == 202); try await Task.sleep(for: .milliseconds(20))
        }
        try expect(confirmed != nil && (try phone.reply(confirmed!))["message"] as? String == "Paired with Test Mac")
        try expect(keys.key(for: phone.id) == phone.key!.withUnsafeBytes { Data($0) })
        let pairingOpen = await hub.pairingOpen
        try expect(!pairingOpen, "Pairing should close after a phone is accepted")

        recorder.accept = false; await hub.openPairing()
        var rejected = SwiftPhone()
        _ = try rejected.finish(await hub.handle(LinkRequest(method: "POST", path: "/pair/start", body: rejected.startBody())))
        var status = 0
        for _ in 0..<50 { status = await hub.handle(try rejected.request("/pair/confirm", LinkEnvelope(kind: "pair"))).status; if status != 202 { break }; try await Task.sleep(for: .milliseconds(20)) }
        try expect(status == 403 && keys.key(for: rejected.id) == nil)
        let bad = await hub.handle(LinkRequest(method: "POST", path: "/pair/start", body: Data(#"{"phoneID":"x","phoneName":"","phoneKey":"zz"}"#.utf8)))
        try expect(bad.status >= 400)
    }
    await checkAsync("paired phones send encrypted health and meals; replays, stale, wrong-key and unpaired requests are refused") {
        let recorder = Recorder(), keys = MemoryPhoneKeyStore()
        let hub = PhoneLinkHub(macName: "Test Mac", keyStore: keys) { await recorder.deliver($0) }
        recorder.hub = hub; await hub.openPairing()
        var phone = SwiftPhone()
        _ = try phone.finish(await hub.handle(LinkRequest(method: "POST", path: "/pair/start", body: phone.startBody())))
        for _ in 0..<50 { if await hub.handle(try phone.request("/pair/confirm", LinkEnvelope(kind: "pair"))).status == 200 { break }; try await Task.sleep(for: .milliseconds(20)) }

        let sync = try phone.reply(await hub.handle(try phone.request("/v1/sync", LinkEnvelope(kind: "sync", snapshot: snapshot()))))
        try expect(sync["ok"] as? Bool == true && recorder.snapshots.count == 1)
        let meal = LinkEnvelope(kind: "meal", meal: PhoneMeal(id: UUID().uuidString, takenAt: Date().timeIntervalSince1970 - 60, note: "dal", image: jpegBase64()))
        let mealRequest = try phone.request("/v1/meal", meal)
        try expect((try phone.reply(await hub.handle(mealRequest)))["message"] as? String == "meal ok" && recorder.meals.first?.note == "dal")
        let replay = try phone.reply(await hub.handle(mealRequest))
        try expect(replay["duplicate"] as? Bool == true && recorder.meals.count == 1, "Replays must not be delivered twice")
        let stale = try phone.reply(await hub.handle(try phone.request("/v1/sync", LinkEnvelope(sentAt: Date().timeIntervalSince1970 - 3600, kind: "sync", snapshot: snapshot()))))
        try expect(stale["ok"] as? Bool == false && recorder.snapshots.count == 1)
        let wrongKind = try phone.reply(await hub.handle(try phone.request("/v1/sync", LinkEnvelope(kind: "meal", meal: meal.meal))))
        try expect(wrongKind["ok"] as? Bool == false)
        let forged = await hub.handle(try phone.request("/v1/sync", LinkEnvelope(kind: "sync", snapshot: snapshot()), key: SymmetricKey(size: .bits256)))
        try expect(forged.status == 401)
        let stranger = SwiftPhone()
        let unpaired = await hub.handle(try stranger.request("/v1/sync", LinkEnvelope(kind: "sync", snapshot: snapshot()), key: SymmetricKey(size: .bits256)))
        try expect(unpaired.status == 401 && String(decoding: unpaired.body, as: UTF8.self).contains("isn’t paired"))
        let badMeal = try phone.reply(await hub.handle(try phone.request("/v1/meal", LinkEnvelope(kind: "meal", meal: PhoneMeal(id: "nope", takenAt: 0, image: "")))))
        try expect(badMeal["ok"] as? Bool == false)
        try refuses { _ = try PhoneMeal(id: UUID().uuidString, takenAt: Date().timeIntervalSince1970 + 3600, image: jpegBase64()).validated() }
        try refuses { _ = try PhoneMeal(id: UUID().uuidString, takenAt: 1_800_000_000, mediaType: "image/gif", image: jpegBase64()).validated(now: Date(timeIntervalSince1970: 1_800_000_000)) }
        let plate = UUID(), now = Date().timeIntervalSince1970 - 60
        let step = try PhoneMeal(id: UUID().uuidString, takenAt: now, image: jpegBase64(), group: plate.uuidString, part: 2, parts: 3).validated()
        try expect(step.group?.meal == plate && step.group?.part == 2 && step.group?.parts == 3, "Multi-photo meals keep their group and part")
        try refuses { _ = try PhoneMeal(id: UUID().uuidString, takenAt: now, image: jpegBase64(), group: plate.uuidString, part: 3, parts: 3).validated() }
        try refuses { _ = try PhoneMeal(id: UUID().uuidString, takenAt: now, image: jpegBase64(), group: plate.uuidString, part: 0, parts: MealLog.maxPhotos + 1).validated() }
        try refuses { _ = try PhoneMeal(id: UUID().uuidString, takenAt: now, image: jpegBase64(), part: 0, parts: 2).validated() }
        let urge = PhoneUrge(id: UUID().uuidString, takenAt: Date().timeIntervalSince1970 - 30, outcome: "Let it pass", intensity: 4, trigger: "Boredom", note: " bathroom ")
        let urgeReply = try phone.reply(await hub.handle(try phone.request("/v1/urge", LinkEnvelope(kind: "urge", urge: urge))))
        try expect(urgeReply["message"] as? String == "urge ok" && (urgeReply["urges"] as? [String: Int])?["todayPassed"] == 1 && recorder.urges == [urge], "Urges arrive with counts in the reply")
        let medPhoto = PhoneMedPhoto(id: UUID().uuidString, batch: UUID().uuidString, batchSize: 3, takenAt: Date().timeIntervalSince1970 - 20, image: jpegBase64())
        let medReply = try phone.reply(await hub.handle(try phone.request("/v1/medphoto", LinkEnvelope(kind: "medphoto", medPhoto: medPhoto))))
        try expect(medReply["message"] as? String == "med photo ok" && ((medReply["meds"] as? [[String: Any]])?.first?["name"] as? String) == "Finasteride", "Replies carry upcoming doses")
        try expect((medReply["today"] as? [String: Any])?["dayNumber"] as? Int == 3, "Replies carry today's summary")
        let dose = PhoneDose(id: UUID().uuidString, medID: UUID().uuidString, day: "2026-10-20", minute: 540, takenAt: Date().timeIntervalSince1970, taken: true)
        let doseReply = try phone.reply(await hub.handle(try phone.request("/v1/dose", LinkEnvelope(kind: "dose", dose: dose))))
        try expect(doseReply["message"] as? String == "dose ok" && recorder.doses == [dose] && recorder.medPhotos == [medPhoto])
        try expect((try phone.reply(await hub.handle(try phone.request("/v1/dose", LinkEnvelope(kind: "dose")))))["ok"] as? Bool == false)
        let tick = PhoneCheckIn(id: UUID().uuidString, habitID: UUID().uuidString, day: "2026-10-20", completed: true)
        let tickReply = try phone.reply(await hub.handle(try phone.request("/v1/checkin", LinkEnvelope(kind: "checkin", checkIn: tick))))
        try expect(tickReply["message"] as? String == "checkin ok" && recorder.checkIns == [tick], "Check-ins reach the Mac")
        let noUrge = try phone.reply(await hub.handle(try phone.request("/v1/urge", LinkEnvelope(kind: "urge"))))
        try expect(noUrge["ok"] as? Bool == false && recorder.urges.count == 1)
        let log = try urge.validated()
        try expect(log.outcome == .passed && log.trigger == .boredom && log.intensity == 4 && log.note == "bathroom" && log.id.uuidString == urge.id)
        try refuses { _ = try PhoneUrge(id: UUID().uuidString, takenAt: Date().timeIntervalSince1970, outcome: "Maybe").validated() }
        try refuses { _ = try PhoneUrge(id: UUID().uuidString, takenAt: Date().timeIntervalSince1970, outcome: "Acted on it", intensity: 9).validated() }
        try refuses { _ = try PhoneUrge(id: UUID().uuidString, takenAt: Date().timeIntervalSince1970, outcome: "Acted on it", trigger: "Rain").validated() }
        try refuses { _ = try PhoneUrge(id: "x", takenAt: Date().timeIntervalSince1970, outcome: "Acted on it").validated() }
    }
    check("urge tally counts let pass and acted on per period and days since last acted on") {
        var doc = original
        let engine = TrackerEngine(document: doc)
        func at(_ day: String, _ hour: Int) -> Date { engine.time(on: day, minute: hour * 60)! }
        let start = doc.cycle.start, today = engine.adding(9, to: start)
        doc.urgeLogs = [UrgeLog(timestamp: at(start, 15), outcome: .acted), UrgeLog(timestamp: at(engine.adding(4, to: start), 14), outcome: .acted),
                        UrgeLog(timestamp: at(engine.adding(5, to: start), 16), outcome: .passed), UrgeLog(timestamp: at(today, 9), outcome: .passed),
                        UrgeLog(timestamp: at(today, 13)), UrgeLog(timestamp: at(engine.adding(-3, to: start), 10), outcome: .acted),
                        UrgeLog(timestamp: at(engine.adding(1, to: today), 10), outcome: .acted)]
        let tally = TrackerEngine(document: doc).urgeTally(today: today)
        try expect(tally.today.passed == 1 && tally.today.unrecorded == 1 && tally.today.acted == 0 && tally.today.total == 2)
        try expect(tally.week.acted == 1 && tally.week.passed == 2, "Week covers the last seven days")
        try expect(tally.cycle.acted == 2 && tally.cycle.passed == 2, "Earlier cycles and future logs are excluded")
        try expect(tally.cleanDays == 5 && tally.lastActed == at(engine.adding(4, to: start), 14))
        try expect(tally.phoneSummary["cycleActed"] == 2 && tally.phoneSummary["cleanDays"] == 5)
        doc.urgeLogs = []
        try expect(TrackerEngine(document: doc).urgeTally(today: today).cleanDays == 9, "With none acted on, count from the cycle start")
    }
    await checkAsync("APK download is offered only while sharing is on") {
        let hub = PhoneLinkHub(macName: "Test Mac", keyStore: MemoryPhoneKeyStore()) { _ in PhoneLinkResult(ok: true, message: "") }
        try expect(await hub.handle(LinkRequest(method: "GET", path: "/bridge.apk")).status == 404)
        await hub.shareAPK(Data("apk".utf8))
        let shared = await hub.handle(LinkRequest(method: "GET", path: "/bridge.apk"))
        try expect(shared.status == 200 && shared.body == Data("apk".utf8) && shared.contentType == "application/vnd.android.package-archive")
        await hub.shareAPK(nil)
        try expect(await hub.handle(LinkRequest(method: "GET", path: "/bridge.apk")).status == 404)
        try expect(await hub.handle(LinkRequest(method: "GET", path: "/etc/passwd")).status == 404)
    }
    await checkAsync("link server speaks HTTP on loopback and limits peers to local addresses") {
        let server = try PhoneLinkServer(name: nil) { request in
            LinkResponse(status: 200, contentType: "text/plain", body: Data("\(request.method) \(request.path) \(request.headers["x-test"] ?? "") \(request.body.count)".utf8))
        }
        server.start(); defer { server.stop() }
        var port: UInt16?
        for _ in 0..<100 { port = server.port; if port != nil && port != 0 { break }; try await Task.sleep(for: .milliseconds(20)) }
        guard let port else { throw LinkFailure(message: "Server did not start") }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/hello")!)
        request.httpMethod = "POST"; request.httpBody = Data(repeating: 7, count: 300_000); request.setValue("yes", forHTTPHeaderField: "X-Test")
        let (data, response) = try await URLSession.shared.data(for: request)
        try expect((response as? HTTPURLResponse)?.statusCode == 200 && String(decoding: data, as: UTF8.self) == "POST /v1/hello yes 300000")
        try expect(PhoneLinkServer.isLocal(.hostPort(host: "192.168.1.20", port: 1)) && PhoneLinkServer.isLocal(.hostPort(host: "10.1.2.3", port: 1)))
        try expect(PhoneLinkServer.isLocal(.hostPort(host: "172.20.0.1", port: 1)) && PhoneLinkServer.isLocal(.hostPort(host: "fe80::1", port: 1)))
        try expect(!PhoneLinkServer.isLocal(.hostPort(host: "8.8.8.8", port: 1)) && !PhoneLinkServer.isLocal(.hostPort(host: "172.32.0.1", port: 1)))
        try expect(!PhoneLinkServer.isLocal(.hostPort(host: "2001:4860::8888", port: 1)))
    }
    if let java = ProcessInfo.processInfo.environment["ASCEND_JAVA_INTEROP"], let classpath = ProcessInfo.processInfo.environment["ASCEND_JAVA_CP"] {
        // Opt-in: runs the Android LinkCrypto/LinkClient code on the JDK against the real Mac server.
        await checkAsync("Android link code pairs, syncs and sends a meal to the real Mac server") {
            let recorder = Recorder()
            let hub = PhoneLinkHub(macName: "Interop Mac", keyStore: MemoryPhoneKeyStore()) { await recorder.deliver($0) }
            recorder.hub = hub; await hub.openPairing()
            let server = try PhoneLinkServer(name: nil) { await hub.handle($0) }
            server.start(); defer { server.stop() }
            var port: UInt16?
            for _ in 0..<100 { port = server.port; if port != nil && port != 0 { break }; try await Task.sleep(for: .milliseconds(20)) }
            let output = try await ProcessClaudeLauncher(timeout: 90).run(ClaudeInvocation(executable: URL(fileURLWithPath: java),
                arguments: ["-cp", classpath, "com.abdul.ascend.bridge.InteropMain", "127.0.0.1", "\(port!)"], environment: ["PATH": "/usr/bin:/bin"],
                directory: FileManager.default.temporaryDirectory, input: ""))
            let lines = String(decoding: output.stdout, as: UTF8.self).split(separator: "\n").map(String.init)
            func line(_ prefix: String) -> String { lines.first { $0.hasPrefix(prefix + " ") } ?? "" }
            print("  java: " + lines.joined(separator: " | ").prefix(400))
            try expect(output.status == 0, "Java exited \(output.status): \(String(decoding: output.stderr.prefix(800), as: UTF8.self))")
            try expect(line("CODE") == "CODE \(recorder.lock.withLock { recorder.pairing?.code ?? "?" })", "Pairing codes differ between Java and Swift")
            try expect(line("PAIRED").contains("Paired with Interop Mac"))
            try expect(line("SYNC").contains("snapshot ok") && recorder.snapshots.first?.records.first?.value == 72)
            try expect(line("MEAL").contains("meal ok") && recorder.meals.first?.note == "2 rotis, dal")
            try expect(line("REPLAY").contains("duplicate") && recorder.meals.count == 1)
            try expect(line("URGE").contains("urge ok") && line("URGE").contains("todayPassed") && recorder.urges.first?.intensity == 3 && recorder.urges.first?.trigger == "Stress")
            try expect(line("MEDPHOTO").contains("med photo ok") && line("MEDPHOTO").contains("Finasteride") && recorder.medPhotos.first?.batchSize == 2)
            try expect(line("DOSE").contains("dose ok") && recorder.doses.first?.minute == 540 && recorder.doses.first?.taken == true)
            try expect(line("BADKEY") == "BADKEY 401")
        }
    }

    check("growing copies of one night count once; naps stay separate") {
        // Real 19 Oct 2026 import: Mi Fitness wrote the same night five times as the watch synced, and the nap twice.
        func iso(_ s: String) -> Double { ISO8601DateFormatter().date(from: s)!.timeIntervalSince1970 }
        let rows: [(String, String, String, Double, String)] = [
            ("a", "2026-10-18T21:12:00Z", "2026-10-19T00:00:00Z", 2.8, "Session window"), ("b", "2026-10-18T21:12:00Z", "2026-10-19T02:53:00Z", 5.67, "Asleep stages"),
            ("c", "2026-10-18T21:12:00Z", "2026-10-19T03:48:00Z", 6.57, "Asleep stages"), ("d", "2026-10-18T21:12:00Z", "2026-10-19T05:27:00Z", 8.2, "Asleep stages"),
            ("e", "2026-10-18T21:12:00Z", "2026-10-19T06:12:00Z", 8.93, "Asleep stages"), ("f", "2026-10-19T08:30:00Z", "2026-10-19T08:52:00Z", 0.37, "Session window"),
            ("g", "2026-10-19T08:30:00Z", "2026-10-19T09:23:00Z", 0.88, "Session window")]
        var archive = HealthArchive()
        archive.records = rows.map { HealthRecord(id: $0.0, metric: .sleep, start: iso($0.1), end: iso($0.2), value: $0.3, detail: $0.4) }
        let sessions = archive.sleepSessions(on: day, engine: TrackerEngine(document: original))
        try expect(sessions.map(\.id) == ["e", "g"], "Got \(sessions.map(\.id))")
        try expect(sessions[0].value == 8.93 && sessions[1].value == 0.88)
        try expect(archive.records(.sleep, on: day, engine: TrackerEngine(document: original)).count == 7, "Stored records stay untouched")
        var doc = original; doc.health = archive
        try expect(PatternsEngine(document: doc, today: "2026-10-20").night(on: day)?.window.asleepHours == 8.93)
    }
    check("sleep stages arrive with the night, validate and add up per stage") {
        let t = 1_792_000_000.0
        let json = #"{"id":"night","metric":"sleep","start":\#(t),"end":\#(t + 8 * 3600),"value":7.5,"detail":"Asleep stages","device":"","stages":[{"start":\#(t),"end":\#(t + 1800),"kind":"light"},{"start":\#(t + 1800),"end":\#(t + 3600),"kind":"deep"},{"start":\#(t + 3000),"end":\#(t + 5400),"kind":"rem"},{"start":\#(t + 5400),"end":\#(t + 5700),"kind":"awake"},{"start":\#(t + 5700),"end":\#(t + 6000),"kind":"awakeInBed"}]}"#
        let record = try JSONDecoder().decode(HealthRecord.self, from: Data(json.utf8))
        try record.validate()
        let m = record.stageMinutes
        try expect(m[.light] == 30 && m[.deep] == 30 && m[.rem] == 30 && m[.awake] == 5 && m[.awakeInBed] == 5, "Overlapping REM must start where deep ended: \(m)")
        try expect(SleepStageKind.allCases.allSatisfy { (0...3).contains($0.depth) } && SleepStageKind.rem.isAsleep && !SleepStageKind.awake.isAsleep)
        var outside = record; outside.stages![0].start = t - 7200
        try refuses { try outside.validate() }
        var wrongMetric = record; wrongMetric.metric = .heartRate; wrongMetric.value = 60
        try refuses { try wrongMetric.validate() }
        let legacy = try JSONDecoder().decode(HealthRecord.self, from: Data(#"{"id":"x","metric":"sleep","start":\#(t),"end":\#(t + 60),"value":0,"detail":"","device":""}"#.utf8))
        try expect(legacy.stages == nil && legacy.stageMinutes.isEmpty)
        try expect(try JSONDecoder().decode(HealthRecord.self, from: JSONEncoder().encode(record)) == record)
    }
    check("meal estimates are validated and kept within sane bounds") {
        let e = try MealEstimate(name: "  ", items: Array(repeating: "x", count: 30), kcal: 600, kcalLow: 700, kcalHigh: 500, protein: 30, carbs: 70, fat: 20, confidence: "HIGH").validated()
        try expect(e.name == "Meal" && e.items.count == 20 && e.kcalLow == 600 && e.kcalHigh == 600 && e.confidence == "high")
        try refuses { _ = try MealEstimate(name: "x", kcal: -1, kcalLow: 0, kcalHigh: 0, protein: 0, carbs: 0, fat: 0).validated() }
        try refuses { _ = try MealEstimate(name: "x", kcal: .nan, kcalLow: 0, kcalHigh: 0, protein: 0, carbs: 0, fat: 0).validated() }
        try refuses { _ = try MealEstimate(name: "x", kcal: 50_000, kcalLow: 0, kcalHigh: 0, protein: 0, carbs: 0, fat: 0).validated() }
    }
    check("confirmed meals fill Calorie and Protein check-ins; removing them clears only meal-written values") {
        var doc = original
        let habits = doc.mealHabits
        try expect(habits.calories?.latest.title == "Calorie target" && habits.protein?.latest.title == "Protein target")
        let at = TrackerEngine(document: doc).date(day)!.timeIntervalSince1970 + 13 * 3600
        var lunch = MealEntry(takenAt: at, day: day, photo: "a.jpg", source: "phone"); lunch.estimate = MealEstimate(name: "Dal rice", kcal: 650, kcalLow: 550, kcalHigh: 800, protein: 22, carbs: 100, fat: 15)
        var dinner = MealEntry(takenAt: at + 6 * 3600, day: day, photo: "b.jpg", source: "mac"); dinner.estimate = MealEstimate(name: "Chicken", kcal: 500, kcalLow: 400, kcalHigh: 600, protein: 45, carbs: 10, fat: 25)
        doc.meals.entries = [lunch, dinner]
        doc.applyMealTotals(on: day, today: day)
        try expect(doc.checkIns.isEmpty, "Unconfirmed estimates must not log anything")
        doc.meals.entries[0].confirmed = true; doc.meals.entries[0].kcal = 700
        doc.applyMealTotals(on: day, today: day)
        let e = TrackerEngine(document: doc)
        try expect(e.entry(for: habits.calories!, day: day)?.value == 700 && e.entry(for: habits.protein!, day: day)?.value == 22)
        doc.meals.entries[1].confirmed = true; doc.applyMealTotals(on: day, today: day)
        try expect(TrackerEngine(document: doc).entry(for: habits.calories!, day: day)?.value == 1200 && doc.meals.totals(day).protein == 67)
        try doc.validate()
        let restored = try JSONDecoder().decode(TrackerDocument.self, from: JSONEncoder().encode(doc))
        try expect(restored.meals == doc.meals)
        doc.meals.entries.removeAll(); doc.applyMealTotals(on: day, today: day)
        try expect(TrackerEngine(document: doc).entry(for: habits.calories!, day: day) == nil && doc.meals.filledDays.isEmpty)
        var manual = original
        manual.setEntry(CheckIn(habitID: habits.calories!.id, day: day, value: 1500))
        manual.applyMealTotals(on: day, today: day)
        try expect(TrackerEngine(document: manual).entry(for: habits.calories!, day: day)?.value == 1500, "Typed values must survive")
        var future = doc; future.meals.entries = [lunch]; future.meals.entries[0].confirmed = true
        future.applyMealTotals(on: "2026-10-25", today: day); try expect(future.checkIns.isEmpty)
        var rest = doc; rest.restDays.insert(day); rest.meals.entries = [lunch]; rest.meals.entries[0].confirmed = true
        rest.applyMealTotals(on: day, today: day); try expect(rest.checkIns.isEmpty)
    }
    check("watch sleep and steps fill their habits; typed and changed values are kept") {
        var doc = original
        let engine = TrackerEngine(document: doc)
        let habits = doc.healthHabits
        try expect(habits.sleep?.latest.title == "Sleep" && habits.steps?.latest.title == "Walk 10,000 steps")
        let noon = engine.date(day)!.timeIntervalSince1970 + 12 * 3600
        let yesterday = engine.adding(-1, to: day)
        doc.health.records = [
            HealthRecord(id: "s1", metric: .sleep, start: noon - 9 * 3600, end: noon - 3600, value: 7.46, detail: "Asleep stages"),
            HealthRecord(id: "st1", metric: .steps, start: noon - 12 * 3600, end: noon, value: 8421, detail: "Health Connect daily aggregate"),
            HealthRecord(id: "st0", metric: .steps, start: noon - 36 * 3600, end: noon - 24 * 3600, value: 12000)]
        doc.applyHealthReadings(today: day)
        var e = TrackerEngine(document: doc)
        try expect(e.entry(for: habits.sleep!, day: day)?.value == 7.5 && e.entry(for: habits.steps!, day: day)?.value == 8421)
        if yesterday >= doc.cycle.start { try expect(e.entry(for: habits.steps!, day: yesterday)?.value == 12000) }
        try doc.validate()
        try expect(try JSONDecoder().decode(TrackerDocument.self, from: JSONEncoder().encode(doc)).health == doc.health)
        // A later sync updates values Ascend wrote...
        doc.health.records[1].value = 9100; doc.applyHealthReadings(today: day)
        e = TrackerEngine(document: doc); try expect(e.entry(for: habits.steps!, day: day)?.value == 9100)
        // ...but never one changed by hand, or one typed before any sync.
        doc.setEntry(CheckIn(habitID: habits.steps!.id, day: day, value: 11000))
        doc.health.records[1].value = 9500; doc.applyHealthReadings(today: day)
        try expect(TrackerEngine(document: doc).entry(for: habits.steps!, day: day)?.value == 11000)
        var manual = original
        manual.setEntry(CheckIn(habitID: habits.sleep!.id, day: day, value: 6))
        manual.health.records = doc.health.records; manual.applyHealthReadings(today: day)
        try expect(TrackerEngine(document: manual).entry(for: habits.sleep!, day: day)?.value == 6)
        // Records that disappear take their written value with them; rest days are skipped.
        var cleared = doc; cleared.health.records.removeAll { $0.metric == .sleep }; cleared.applyHealthReadings(today: day)
        try expect(TrackerEngine(document: cleared).entry(for: habits.sleep!, day: day) == nil)
        var rest = original; rest.restDays.insert(day); rest.health.records = doc.health.records; rest.applyHealthReadings(today: day)
        try expect(TrackerEngine(document: rest).entry(for: habits.sleep!, day: day) == nil)
    }
    check("night vitals, routine drift and step distance are worked out from imported readings") {
        var doc = original
        let engine = TrackerEngine(document: doc)
        let start = engine.time(on: day, minute: 2 * 60 + 42)!.timeIntervalSince1970
        let night = HealthRecord(id: "n", metric: .sleep, start: start, end: start + 9 * 3600, value: 8.9, detail: "Asleep stages")
        doc.health.records = [night,
            HealthRecord(id: "h1", metric: .heartRate, start: start + 3600, end: start + 3600, value: 58),
            HealthRecord(id: "h2", metric: .heartRate, start: start + 7200, end: start + 7200, value: 52),
            HealthRecord(id: "h3", metric: .heartRate, start: start + 11 * 3600, end: start + 11 * 3600, value: 90),
            HealthRecord(id: "o1", metric: .oxygen, start: start + 3600, end: start + 3600, value: 97),
            HealthRecord(id: "o2", metric: .oxygen, start: start + 7200, end: start + 7200, value: 93),
            HealthRecord(id: "st", metric: .steps, start: start, end: start + 3600, value: 4000)]
        let v = doc.health.nightVitals(night)
        try expect(v.restingHeartRate == 52 && v.averageHeartRate == 55 && v.heartSamples == 2, "Daytime samples must be excluded")
        try expect(v.averageOxygen == 95 && v.lowestOxygen == 93, "oxygen")
        try expect(doc.health.estimatedDistance(on: day, engine: engine) == 3000, "distance"); try expect(doc.health.latest(.heartRate)?.id == "h3", "latest")
        try expect(!doc.health.hasWorkouts)
        doc.routine.configured = true; doc.routine.bedMinute = 22 * 60; doc.routine.wakeMinute = 6 * 60
        try expect(TrackerEngine(document: doc).drift(night) == RoutineDrift(bedtime: 4 * 60 + 42, wake: 5 * 60 + 42), "drift \(String(describing: TrackerEngine(document: doc).drift(night)))")
        try expect(RoutineDrift.offset(21 * 60 + 30, from: 22 * 60) == -30 && RoutineDrift.offset(30, from: 23 * 60 + 30) == 60)
        doc.routine.configured = false; try expect(TrackerEngine(document: doc).drift(night) == nil)
    }
    check("meal log validation and older tracker files without meals") {
        var doc = original
        doc.meals.entries = [MealEntry(takenAt: 1_790_000_000, day: day, photo: "../escape.jpg", source: "phone")]
        try refuses { try doc.validate() }
        doc.meals.entries = [MealEntry(takenAt: 1_790_000_000, day: day, photo: "ok.jpg", source: "web")]
        try refuses { try doc.validate() }
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        json["meals"] = nil
        let legacy = try JSONDecoder().decode(TrackerDocument.self, from: JSONSerialization.data(withJSONObject: json))
        try expect(legacy.meals.entries.isEmpty)
    }
    check("a meal with several photos keeps them in order, waits for missing ones and sends them all to Claude") {
        let id = UUID()
        var meal = MealEntry(id: id, takenAt: 1_790_000_000, day: day, photo: MealLog.photoName(meal: id, part: 1, ext: "jpg"), source: "phone")
        meal.morePhotos = [MealLog.photoName(meal: id, part: 2, ext: "jpg"), MealLog.photoName(meal: id, part: 0, ext: "jpg")]
        meal.expectedPhotos = 4
        try expect(meal.photos.map { String($0.suffix(6)) } == ["00.jpg", "01.jpg", "02.jpg"] && meal.missingPhotos == 1, "\(meal.photos)")
        var doc = original; doc.meals.entries = [meal]
        try doc.validate()
        doc.meals.entries[0].morePhotos = (0..<MealLog.maxPhotos).map { "p\($0).jpg" }
        try refuses { try doc.validate() }
        doc.meals.entries[0].morePhotos = ["../escape.jpg"]
        try refuses { try doc.validate() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ascend-meal-steps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: folder) }
        let urls = try (0..<3).map { i -> URL in let u = folder.appendingPathComponent("\(i).jpg"); try Data(base64Encoded: jpegBase64())!.write(to: u); return u }
        let line = try ClaudeAssistant.mealInput(photos: urls, note: "rice then dal", takenAt: Date(), timeZone: "Asia/Kolkata")
        try expect(line.components(separatedBy: "\"type\":\"image\"").count == 4 && line.contains("3 photos are steps of the same meal"), "All steps go in one request")
        try expect(ClaudeAssistant.mealSystemPrompt.contains("tared"), "The prompt explains scale readings")
    }
    check("chat context lists confirmed meals only when sharing history") {
        var doc = original
        let at = TrackerEngine(document: doc).date(day)!.timeIntervalSince1970 + 13 * 3600
        var meal = MealEntry(takenAt: at, day: day, photo: "a.jpg", source: "phone"); meal.estimate = MealEstimate(name: "MEAL_SENTINEL", kcal: 640, kcalLow: 500, kcalHigh: 800, protein: 31, carbs: 80, fat: 20)
        meal.confirmed = true; doc.meals.entries = [meal]
        try expect(String(decoding: try ClaudeAssistant.contextData(document: doc, today: day, shareHistory: true), as: UTF8.self).contains("MEAL_SENTINEL"))
        try expect(!String(decoding: try ClaudeAssistant.contextData(document: doc, today: day, shareHistory: false), as: UTF8.self).contains("MEAL_SENTINEL"))
    }
    check("meal estimates run without tools or a saved session and decode the meal schema") {
        let args = ClaudeAssistant.mealArguments(model: .haiku, effort: .medium)
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).map { args[$0 + 1] } }
        try expect(args.contains("--no-session-persistence") && value("--tools") == "" && value("--model") == "claude-haiku-5-5" && value("--effort") == "medium")
        let schema = try JSONSerialization.jsonObject(with: Data(value("--json-schema")!.utf8)) as! [String: Any]
        try expect((schema["required"] as! [String]).contains("protein"))
        let structured: [String: Any] = ["name": "Poha", "items": ["poha", "peanuts"], "kcal": 350, "kcalLow": 280, "kcalHigh": 450, "protein": 8, "carbs": 55, "fat": 11, "confidence": "medium", "notes": "Oil varies."]
        let line = String(data: try JSONSerialization.data(withJSONObject: ["type": "result", "is_error": false, "structured_output": structured]), encoding: .utf8)!
        let estimate = try ClaudeAssistant.decodeMeal(ClaudeProcessOutput(status: 0, stdout: Data(line.utf8)))
        try expect(estimate.name == "Poha" && estimate.kcal == 350 && estimate.items == ["poha", "peanuts"])
        let broken = String(data: try JSONSerialization.data(withJSONObject: ["type": "result", "is_error": false, "structured_output": ["name": "x"]]), encoding: .utf8)!
        try refuses { _ = try ClaudeAssistant.decodeMeal(ClaudeProcessOutput(status: 0, stdout: Data(broken.utf8))) }
    }
    if ProcessInfo.processInfo.environment["ASCEND_LIVE_CLAUDE"] == "1" {
        // Opt-in: a real meal-estimate run through the personal profile; nothing is saved.
        await checkAsync("live Claude returns a valid meal estimate for a photo") {
            guard let executable = ClaudeAssistant.locateExecutable(override: "") else { throw LinkFailure(message: "Claude Code not found") }
            let photo = FileManager.default.temporaryDirectory.appendingPathComponent("ascend-meal-\(UUID().uuidString).jpg")
            try Data(base64Encoded: jpegBase64())!.write(to: photo); defer { try? FileManager.default.removeItem(at: photo) }
            let output = try await ProcessClaudeLauncher(timeout: 180).run(ClaudeInvocation(executable: executable,
                arguments: ClaudeAssistant.mealArguments(model: .haiku, effort: .medium),
                environment: ClaudeAssistant.environment(base: ProcessInfo.processInfo.environment, configDirectory: ClaudeAssistant.defaultConfigDirectory),
                directory: FileManager.default.temporaryDirectory,
                input: try ClaudeAssistant.mealInput(photos: [photo], note: "a plain red test card, not food", takenAt: Date(), timeZone: "Asia/Kolkata")))
            let estimate = try ClaudeAssistant.decodeMeal(output)
            print("  live meal: \(estimate.name) · \(Int(estimate.kcal)) kcal · \(estimate.confidence)")
            try expect(estimate.kcal < 200, "A test card should not be estimated as a meal")
        }
    }
    return (count, failures)
}
