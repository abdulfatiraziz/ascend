import Foundation
import CryptoKit
import Network

/// Wi-Fi link between Ascend Bridge (Android) and this Mac. No Android debugging is involved.
///
/// Pairing: the phone sends its X25519 public key to `POST /pair/start` while pairing is open on the Mac.
/// Both sides derive the same AES-256 key (HKDF-SHA256) and the same 6-digit code; the user confirms the
/// code on the Mac, which defeats a machine-in-the-middle. Afterwards every request body is AES-GCM sealed
/// (nonce ‖ ciphertext ‖ tag) with that key, carries a fresh ID and timestamp, and is accepted only from
/// local-network addresses. The Android implementation mirrors `PhoneLinkCrypto` byte for byte.
public enum PhoneLinkCrypto {
    /// X.509 SubjectPublicKeyInfo prefix for a raw X25519 key, as Java's `PublicKey.getEncoded()` produces.
    static let x509Prefix = Data([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x03, 0x21, 0x00])
    public static func encode(_ key: Curve25519.KeyAgreement.PublicKey) -> String { (x509Prefix + key.rawRepresentation).base64EncodedString() }
    public static func decodePublicKey(_ text: String) throws -> Curve25519.KeyAgreement.PublicKey {
        guard let data = Data(base64Encoded: text) else { throw ValidationError(message: "Invalid phone key.") }
        if data.count == 44 && data.prefix(12) == x509Prefix { return try .init(rawRepresentation: data.suffix(32)) }
        if data.count == 32 { return try .init(rawRepresentation: data) }
        throw ValidationError(message: "Invalid phone key.")
    }
    public static func sessionKey(_ privateKey: Curve25519.KeyAgreement.PrivateKey, phone: Curve25519.KeyAgreement.PublicKey) throws -> SymmetricKey {
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: phone)
        return shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("ascend-link-v1".utf8),
            sharedInfo: privateKey.publicKey.rawRepresentation + phone.rawRepresentation, outputByteCount: 32)
    }
    public static func pairingCode(mac: Curve25519.KeyAgreement.PublicKey, phone: Curve25519.KeyAgreement.PublicKey) -> String {
        let digest = Array(SHA256.hash(data: Data("ascend-code-v1".utf8) + mac.rawRepresentation + phone.rawRepresentation))
        let number = (UInt32(digest[0]) << 24 | UInt32(digest[1]) << 16 | UInt32(digest[2]) << 8 | UInt32(digest[3])) % 1_000_000
        return String(format: "%06u", number)
    }
    public static func seal(_ data: Data, key: SymmetricKey) throws -> Data { try AES.GCM.seal(data, using: key).combined! }
    public static func open(_ data: Data, key: SymmetricKey) throws -> Data { try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key) }
}

/// A meal photo queued on the phone. A meal with several photos sends each one separately with the same `group`
/// (the meal's ID), its position `part` and the photo count `parts`, so each request stays small.
public struct PhoneMeal: Codable, Equatable, Sendable {
    public var id: String
    public var takenAt: Double
    public var note: String
    public var mediaType: String
    public var image: String
    public var group: String?
    public var part: Int?
    public var parts: Int?
    public init(id: String, takenAt: Double, note: String = "", mediaType: String = "image/jpeg", image: String, group: String? = nil, part: Int? = nil, parts: Int? = nil) {
        self.id = id; self.takenAt = takenAt; self.note = note; self.mediaType = mediaType; self.image = image
        self.group = group; self.part = part; self.parts = parts
    }
    public func validated(now: Date = Date()) throws -> (id: UUID, data: Data, group: (meal: UUID, part: Int, parts: Int)?) {
        guard let uuid = UUID(uuidString: id), takenAt.isFinite, takenAt >= 946684800, takenAt <= now.timeIntervalSince1970 + 300,
              note.count <= 500, ["image/jpeg", "image/png"].contains(mediaType),
              let data = Data(base64Encoded: image), !data.isEmpty, data.count <= 8_000_000 else {
            throw ValidationError(message: "The phone sent an invalid meal photo.")
        }
        guard let group else {
            guard part == nil, parts == nil else { throw ValidationError(message: "The phone sent an invalid meal photo.") }
            return (uuid, data, nil)
        }
        guard let meal = UUID(uuidString: group), let part, let parts, (2...MealLog.maxPhotos).contains(parts), (0..<parts).contains(part) else {
            throw ValidationError(message: "The phone sent an invalid meal photo.")
        }
        return (uuid, data, (meal, part, parts))
    }
}
/// An urge logged on the phone. The ID is stable across retries, so a resend is not logged twice.
public struct PhoneUrge: Codable, Equatable, Sendable {
    public var id: String
    public var takenAt: Double
    public var outcome: String
    public var intensity: Int?
    public var trigger: String?
    public var note: String
    public init(id: String, takenAt: Double, outcome: String, intensity: Int? = nil, trigger: String? = nil, note: String = "") {
        self.id = id; self.takenAt = takenAt; self.outcome = outcome; self.intensity = intensity; self.trigger = trigger; self.note = note
    }
    public func validated(now: Date = Date()) throws -> UrgeLog {
        guard let uuid = UUID(uuidString: id), takenAt.isFinite, takenAt >= 946684800, takenAt <= now.timeIntervalSince1970 + 300,
              let outcome = UrgeOutcome(rawValue: outcome), intensity.map({ (1...5).contains($0) }) ?? true,
              trigger.map({ UrgeTrigger(rawValue: $0) != nil }) ?? true, note.count <= 500 else {
            throw ValidationError(message: "The phone sent an invalid urge log.")
        }
        return UrgeLog(id: uuid, timestamp: Date(timeIntervalSince1970: min(takenAt, now.timeIntervalSince1970)), intensity: intensity,
                       trigger: trigger.flatMap(UrgeTrigger.init(rawValue:)), outcome: outcome, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
public struct LinkEnvelope: Codable, Sendable {
    public var id: String
    public var sentAt: Double
    public var kind: String
    public var snapshot: HealthSnapshot?
    public var meal: PhoneMeal?
    public var urge: PhoneUrge?
    public var medPhoto: PhoneMedPhoto?
    public var dose: PhoneDose?
    public var checkIn: PhoneCheckIn?
    public init(id: String = UUID().uuidString, sentAt: Double = Date().timeIntervalSince1970, kind: String, snapshot: HealthSnapshot? = nil, meal: PhoneMeal? = nil,
                urge: PhoneUrge? = nil, medPhoto: PhoneMedPhoto? = nil, dose: PhoneDose? = nil, checkIn: PhoneCheckIn? = nil) {
        self.id = id; self.sentAt = sentAt; self.kind = kind; self.snapshot = snapshot; self.meal = meal; self.urge = urge; self.medPhoto = medPhoto; self.dose = dose
        self.checkIn = checkIn
    }
}
public struct PairingRequest: Sendable, Equatable, Identifiable {
    public var id: String { phoneID }
    public var phoneID: String
    public var phoneName: String
    public var code: String
    public var created: Date
}
public enum PhoneLinkEvent: Sendable {
    case pairingRequested(PairingRequest)
    case pairingFinished(PairingRequest, accepted: Bool)
    case hello(phoneID: String)
    case snapshot(HealthSnapshot, phoneID: String)
    case meal(PhoneMeal, phoneID: String)
    case urge(PhoneUrge, phoneID: String)
    case medPhoto(PhoneMedPhoto, phoneID: String)
    case dose(PhoneDose, phoneID: String)
    case checkIn(PhoneCheckIn, phoneID: String)
}
public struct PhoneLinkResult: Sendable, Equatable {
    public var ok: Bool
    public var message: String
    /// Urge counts for the phone to show, from `UrgeTally.phoneSummary`.
    public var urges: [String: Int]?
    /// Upcoming doses for the phone's medicine list and reminders.
    public var meds: [PhoneMedDose]?
    /// Today's progress for the phone's Today screen.
    public var today: PhoneToday?
    public init(ok: Bool, message: String, urges: [String: Int]? = nil, meds: [PhoneMedDose]? = nil, today: PhoneToday? = nil) {
        self.ok = ok; self.message = message; self.urges = urges; self.meds = meds; self.today = today
    }
}
/// Secret per-phone link keys. The app stores them in the Keychain.
public protocol PhoneKeyStore: Sendable {
    func key(for phoneID: String) -> Data?
    func save(_ key: Data, for phoneID: String) throws
    func delete(_ phoneID: String)
}
public final class MemoryPhoneKeyStore: PhoneKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String: Data] = [:]
    public init() {}
    public func key(for phoneID: String) -> Data? { lock.withLock { keys[phoneID] } }
    public func save(_ key: Data, for phoneID: String) throws { lock.withLock { keys[phoneID] = key } }
    public func delete(_ phoneID: String) { lock.withLock { keys[phoneID] = nil } }
}

public struct LinkRequest: Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data
    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method; self.path = path; self.headers = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) }); self.body = body
    }
}
public struct LinkResponse: Sendable, Equatable {
    public var status: Int
    public var contentType: String
    public var body: Data
    public init(status: Int, contentType: String = "application/json", body: Data = Data()) { self.status = status; self.contentType = contentType; self.body = body }
    static func json(_ status: Int, _ object: [String: Any]) -> LinkResponse {
        LinkResponse(status: status, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
    }
    static func error(_ status: Int, _ message: String) -> LinkResponse { json(status, ["error": message]) }
}

public actor PhoneLinkHub {
    public static let serviceType = "_ascend-sync._tcp"
    public static let maxBody = 12_000_000
    private struct Pending { var request: PairingRequest; var key: SymmetricKey; var state = 0 } // 0 waiting, 1 accepted, 2 rejected
    public let macName: String
    private let keyStore: any PhoneKeyStore
    private let deliver: @Sendable (PhoneLinkEvent) async -> PhoneLinkResult
    private let clock: @Sendable () -> Date
    private var pairingUntil: Date?
    private var pending: [String: Pending] = [:]
    private var seen: [String: Date] = [:]
    private var apk: (data: Data, until: Date)?

    public init(macName: String, keyStore: any PhoneKeyStore, clock: @escaping @Sendable () -> Date = Date.init,
                deliver: @escaping @Sendable (PhoneLinkEvent) async -> PhoneLinkResult) {
        self.macName = macName; self.keyStore = keyStore; self.clock = clock; self.deliver = deliver
    }
    public func openPairing(minutes: Double = 5) { pairingUntil = clock().addingTimeInterval(minutes * 60) }
    public func closePairing() { pairingUntil = nil; pending = pending.filter { $0.value.state != 0 } }
    public var pairingOpen: Bool { pairingUntil.map { $0 > clock() } ?? false }
    /// Accepting stores the link key immediately; the phone learns the result on its next poll.
    public func respond(to phoneID: String, accept: Bool) async {
        guard var entry = pending[phoneID], entry.state == 0 else { return }
        if accept {
            do { try keyStore.save(entry.key.withUnsafeBytes { Data($0) }, for: phoneID) } catch { return }
        }
        entry.state = accept ? 1 : 2; pending[phoneID] = entry
        if accept { pairingUntil = nil }
        _ = await deliver(.pairingFinished(entry.request, accepted: accept))
    }
    public func shareAPK(_ data: Data?, minutes: Double = 15) { apk = data.map { ($0, clock().addingTimeInterval(minutes * 60)) } }
    public var sharingAPK: Bool { apk.map { $0.until > clock() } ?? false }

    public func handle(_ request: LinkRequest) async -> LinkResponse {
        switch (request.method, request.path) {
        case ("GET", "/bridge.apk"):
            guard let apk, apk.until > clock() else { return LinkResponse(status: 404, contentType: "text/plain", body: Data("Open Ascend on your Mac → Health → Install phone app, then scan the code again.".utf8)) }
            return LinkResponse(status: 200, contentType: "application/vnd.android.package-archive", body: apk.data)
        case ("POST", "/pair/start"): return await pairStart(request)
        case ("POST", "/pair/confirm"): return pairConfirm(request)
        case ("POST", "/v1/hello"), ("POST", "/v1/sync"), ("POST", "/v1/meal"), ("POST", "/v1/urge"), ("POST", "/v1/medphoto"), ("POST", "/v1/dose"), ("POST", "/v1/checkin"): return await authenticated(request)
        default: return .error(404, "Unknown request.")
        }
    }
    private func pairStart(_ request: LinkRequest) async -> LinkResponse {
        guard pairingOpen else { return .error(403, "Pairing is off. On your Mac, open Ascend → Health → Pair phone, then try again.") }
        guard let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              let phoneID = json["phoneID"] as? String, UUID(uuidString: phoneID) != nil,
              let name = (json["phoneName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name.count <= 60,
              let keyText = json["phoneKey"] as? String, let phoneKey = try? PhoneLinkCrypto.decodePublicKey(keyText) else {
            return .error(400, "Invalid pairing request.")
        }
        let macKey = Curve25519.KeyAgreement.PrivateKey()
        guard let key = try? PhoneLinkCrypto.sessionKey(macKey, phone: phoneKey) else { return .error(400, "Invalid phone key.") }
        let pairing = PairingRequest(phoneID: phoneID.lowercased(), phoneName: name, code: PhoneLinkCrypto.pairingCode(mac: macKey.publicKey, phone: phoneKey), created: clock())
        pending[pairing.phoneID] = Pending(request: pairing, key: key)
        _ = await deliver(.pairingRequested(pairing))
        return .json(200, ["macName": macName, "macKey": PhoneLinkCrypto.encode(macKey.publicKey)])
    }
    private func pairConfirm(_ request: LinkRequest) -> LinkResponse {
        guard let phoneID = request.headers["x-ascend-phone"]?.lowercased(), let entry = pending[phoneID] else {
            return .error(404, "No pairing in progress. Start pairing again.")
        }
        guard clock().timeIntervalSince(entry.request.created) < 300 else { pending[phoneID] = nil; return .error(410, "Pairing timed out. Start again.") }
        guard let plain = try? PhoneLinkCrypto.open(request.body, key: entry.key),
              let envelope = try? JSONDecoder().decode(LinkEnvelope.self, from: plain), envelope.kind == "pair" else {
            return .error(401, "Pairing check failed. Start again.")
        }
        switch entry.state {
        case 0: return .json(202, ["status": "waiting"])
        case 1: pending[phoneID] = nil; return sealed(["ok": true, "message": "Paired with \(macName)"], key: entry.key)
        default: pending[phoneID] = nil; return .error(403, "Pairing was declined on the Mac.")
        }
    }
    private func authenticated(_ request: LinkRequest) async -> LinkResponse {
        guard let phoneID = request.headers["x-ascend-phone"]?.lowercased(), let raw = keyStore.key(for: phoneID) else {
            return .error(401, "This phone isn’t paired with \(macName). Pair again from Ascend Bridge.")
        }
        let key = SymmetricKey(data: raw)
        guard let plain = try? PhoneLinkCrypto.open(request.body, key: key) else { return .error(401, "The Mac couldn’t verify this phone. Pair again.") }
        let envelope: LinkEnvelope
        do { envelope = try JSONDecoder().decode(LinkEnvelope.self, from: plain) }
        catch { return sealed(["ok": false, "message": "The Mac couldn’t read this data. Update Ascend Bridge."], key: key) }
        let kind = String(request.path.dropFirst(4)), now = clock()
        guard envelope.kind == kind, UUID(uuidString: envelope.id) != nil, abs(now.timeIntervalSince1970 - envelope.sentAt) <= 600 else {
            return sealed(["ok": false, "message": "Request rejected. Check that the phone and Mac clocks are correct."], key: key)
        }
        seen = seen.filter { now.timeIntervalSince($0.value) < 1200 }
        guard seen[envelope.id] == nil else { return sealed(["ok": true, "message": "Already received.", "duplicate": true], key: key) }
        seen[envelope.id] = now
        let result: PhoneLinkResult
        switch kind {
        case "hello": result = await deliver(.hello(phoneID: phoneID))
        case "sync":
            guard let snapshot = envelope.snapshot else { return sealed(["ok": false, "message": "No health data was included."], key: key) }
            result = await deliver(.snapshot(snapshot, phoneID: phoneID))
        case "urge":
            guard let urge = envelope.urge else { return sealed(["ok": false, "message": "No urge was included."], key: key) }
            result = await deliver(.urge(urge, phoneID: phoneID))
        case "medphoto":
            guard let photo = envelope.medPhoto else { return sealed(["ok": false, "message": "No medicine photo was included."], key: key) }
            result = await deliver(.medPhoto(photo, phoneID: phoneID))
        case "dose":
            guard let dose = envelope.dose else { return sealed(["ok": false, "message": "No dose was included."], key: key) }
            result = await deliver(.dose(dose, phoneID: phoneID))
        case "checkin":
            guard let checkIn = envelope.checkIn else { return sealed(["ok": false, "message": "No check-in was included."], key: key) }
            result = await deliver(.checkIn(checkIn, phoneID: phoneID))
        default:
            guard let meal = envelope.meal else { return sealed(["ok": false, "message": "No meal was included."], key: key) }
            result = await deliver(.meal(meal, phoneID: phoneID))
        }
        var reply: [String: Any] = ["ok": result.ok, "message": result.message]
        if let urges = result.urges { reply["urges"] = urges }
        if let meds = result.meds, let data = try? JSONEncoder().encode(meds), let list = try? JSONSerialization.jsonObject(with: data) { reply["meds"] = list }
        if let today = result.today, let data = try? JSONEncoder().encode(today), let summary = try? JSONSerialization.jsonObject(with: data) { reply["today"] = summary }
        return sealed(reply, key: key)
    }
    private func sealed(_ object: [String: Any], key: SymmetricKey) -> LinkResponse {
        guard let data = try? JSONSerialization.data(withJSONObject: object), let body = try? PhoneLinkCrypto.seal(data, key: key) else { return .error(500, "Response failed.") }
        return LinkResponse(status: 200, contentType: "application/octet-stream", body: body)
    }
}

/// Minimal HTTP/1.1 server for the link: one request per connection, local-network peers only.
public final class PhoneLinkServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "ascend.phone-link")
    private let handler: @Sendable (LinkRequest) async -> LinkResponse
    public var onState: (@Sendable (String) -> Void)?
    public var port: UInt16? { listener.port?.rawValue }

    public init(name: String?, port: UInt16 = 0, handler: @escaping @Sendable (LinkRequest) async -> LinkResponse) throws {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        listener = try NWListener(using: parameters, on: port == 0 ? .any : NWEndpoint.Port(rawValue: port)!)
        if let name { listener.service = NWListener.Service(name: name, type: PhoneLinkHub.serviceType) }
        self.handler = handler
    }
    public func start() {
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.onState?("ready")
            case .failed(let error): self?.onState?("failed: \(error.localizedDescription)")
            default: break
            }
        }
        listener.serviceRegistrationUpdateHandler = { [weak self] change in
            if case .add = change { self?.onState?("advertised") }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            guard Self.isLocal(connection.endpoint) else { connection.cancel(); return }
            LinkConnection(connection: connection, queue: queue, handler: handler).start()
        }
        listener.start(queue: queue)
    }
    public func stop() { listener.cancel() }

    public static func isLocal(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return isLocalIPv4(Array(address.rawValue))
        case .ipv6(let address):
            let b = Array(address.rawValue)
            guard b.count == 16 else { return false }
            if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xff && b[11] == 0xff { return isLocalIPv4(Array(b[12...])) }
            return b == Array(repeating: 0, count: 15) + [1] || (b[0] == 0xfe && b[1] & 0xc0 == 0x80) || b[0] & 0xfe == 0xfc
        default: return false
        }
    }
    static func isLocalIPv4(_ b: [UInt8]) -> Bool {
        guard b.count == 4 else { return false }
        return b[0] == 10 || b[0] == 127 || (b[0] == 172 && (16...31).contains(b[1])) || (b[0] == 192 && b[1] == 168) || (b[0] == 169 && b[1] == 254)
    }
}
private final class LinkConnection: @unchecked Sendable {
    let connection: NWConnection
    let queue: DispatchQueue
    let handler: @Sendable (LinkRequest) async -> LinkResponse
    var buffer = Data()
    var finished = false
    init(connection: NWConnection, queue: DispatchQueue, handler: @escaping @Sendable (LinkRequest) async -> LinkResponse) {
        self.connection = connection; self.queue = queue; self.handler = handler
    }
    func start() {
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 60) { [self] in if !finished { finished = true; connection.cancel() } }
        receive()
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [self] data, _, complete, error in
            if let data { buffer.append(data) }
            if buffer.count > PhoneLinkHub.maxBody + 16_384 { reply(.error(413, "Too large.")); return }
            switch parse() {
            case .some(.success(let request)): Task { [self] in let response = await self.handler(request); self.queue.async { self.reply(response) } }
            case .some(.failure): reply(.error(400, "Bad request."))
            case .none: if complete || error != nil { finished = true; connection.cancel() } else { receive() }
            }
        }
    }
    private func parse() -> Result<LinkRequest, Error>? {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else { return buffer.count > 16_384 ? .failure(ValidationError(message: "header")) : nil }
        let lines = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count >= 2 else { return .failure(ValidationError(message: "request line")) }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard (0...PhoneLinkHub.maxBody).contains(length) else { return .failure(ValidationError(message: "length")) }
        guard buffer.count - end.upperBound >= length else { return nil }
        let body = buffer.subdata(in: end.upperBound..<(end.upperBound + length))
        return .success(LinkRequest(method: String(first[0]), path: String(first[1]), headers: headers, body: body))
    }
    private func reply(_ response: LinkResponse) {
        guard !finished else { return }
        finished = true
        let reasons = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 410: "Gone", 413: "Payload Too Large", 500: "Server Error"]
        var data = Data("HTTP/1.1 \(response.status) \(reasons[response.status] ?? "Status")\r\nContent-Type: \(response.contentType)\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\n\r\n".utf8)
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { [self] _ in connection.cancel() })
    }
}
