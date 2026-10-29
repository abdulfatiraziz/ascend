import SwiftUI
import AppKit
import Security
import CoreImage.CIFilterBuiltins
import AscendCore

struct PairedPhone: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var paired: Date
    var lastSync: Date?
}
/// Link keys live in the Keychain, never in tracker backups.
private struct KeychainPhoneKeyStore: PhoneKeyStore {
    let service: String
    private func query(_ phoneID: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: phoneID, kSecAttrSynchronizable as String: false]
    }
    func key(for phoneID: String) -> Data? {
        var q = query(phoneID); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
    }
    func save(_ key: Data, for phoneID: String) throws {
        SecItemDelete(query(phoneID) as CFDictionary)
        var q = query(phoneID); q[kSecValueData as String] = key; q[kSecAttrLabel as String] = "Ascend · phone link"
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw ValidationError(message: "The phone key couldn’t be saved in the Keychain (\(status)).") }
    }
    func delete(_ phoneID: String) { SecItemDelete(query(phoneID) as CFDictionary) }
}

/// Listens on the local Wi-Fi for Ascend Bridge. Runs while Ascend is open.
@MainActor final class PhoneLinkService: ObservableObject {
    @Published private(set) var status = "Not started"
    @Published private(set) var listening = false
    /// True once Bonjour confirms the phone can discover this Mac.
    @Published private(set) var advertised = false
    @Published private(set) var port: UInt16?
    @Published private(set) var phones: [PairedPhone] = []
    @Published private(set) var pairing: PairingRequest?
    @Published private(set) var pairingOpen = false
    @Published private(set) var sharingAPK = false
    @Published private(set) var activity: String?
    weak var store: TrackerStore?
    let macName: String
    private let defaults: UserDefaults
    private let keys: KeychainPhoneKeyStore
    private var hub: PhoneLinkHub!
    private var server: PhoneLinkServer?

    init(enabled: Bool) {
        let isolated = ProcessInfo.processInfo.environment["ASCEND_DATA_DIR"] != nil
        defaults = isolated ? UserDefaults(suiteName: "com.abdul.ascend.qa")! : .standard
        keys = KeychainPhoneKeyStore(service: isolated ? "com.abdul.ascend.phone-link.qa" : "com.abdul.ascend.phone-link")
        macName = Host.current().localizedName ?? "Mac"
        phones = (defaults.data(forKey: "phoneLink.phones").flatMap { try? JSONDecoder().decode([PairedPhone].self, from: $0) }) ?? []
        hub = PhoneLinkHub(macName: macName, keyStore: keys) { [weak self] event in
            await self?.receive(event) ?? PhoneLinkResult(ok: false, message: "Ascend is closing.")
        }
        if enabled { start() }
    }
    func start() {
        guard server == nil else { return }
        do {
            let hub = hub!
            let server = try PhoneLinkServer(name: macName) { request in await hub.handle(request) }
            server.onState = { [weak self] state in Task { @MainActor in self?.update(state) } }
            server.start(); self.server = server; status = "Starting…"
        } catch { status = "Wi-Fi link unavailable: \(error.localizedDescription)" }
    }
    private func update(_ state: String) {
        FileHandle.standardError.write(Data("Ascend phone link: \(state)\n".utf8))
        switch state {
        case "ready":
            listening = true; port = server?.port
            if !advertised { status = "Listening on port \(port ?? 0); waiting to appear on Wi-Fi…" }
        case "advertised":
            advertised = true; status = "Ready on Wi-Fi as “\(macName)”"
        default:
            listening = false; advertised = false
            status = "Wi-Fi link unavailable (\(state)). Check Local Network access for Ascend in System Settings → Privacy & Security."
        }
    }
    func openPairing() { pairingOpen = true; pairing = nil; Task { await hub.openPairing() } }
    func cancelPairing() {
        if let pairing { respond(accept: false, to: pairing) }
        pairingOpen = false; pairing = nil; Task { await hub.closePairing() }
    }
    func respond(accept: Bool, to request: PairingRequest) { Task { await hub.respond(to: request.phoneID, accept: accept) } }
    func forget(_ phone: PairedPhone) {
        keys.delete(phone.id); phones.removeAll { $0.id == phone.id }; persist()
    }
    /// Offers the bundled Ascend Bridge APK for 15 minutes at `downloadURL` on this Wi-Fi.
    func shareAPK() {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Android/AscendBridge.apk"), let data = try? Data(contentsOf: url) else {
            activity = "The phone app isn’t included in this build."; return
        }
        sharingAPK = true; Task { await hub.shareAPK(data) }
    }
    func stopSharingAPK() { sharingAPK = false; Task { await hub.shareAPK(nil) } }
    var downloadURL: URL? {
        guard let port, let address = Self.localIPv4() else { return nil }
        return URL(string: "http://\(address):\(port)/bridge.apk")
    }
    func qrCode(for url: URL) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(url.absoluteString.utf8); filter.correctionLevel = "M"
        guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: image); let result = NSImage(size: rep.size); result.addRepresentation(rep)
        return result
    }

    /// Every reply to a paired phone carries the latest urge counts for its Urges card.
    private func receive(_ event: PhoneLinkEvent) async -> PhoneLinkResult {
        var result = await handle(event)
        if case .pairingRequested = event { return result }
        if result.urges == nil, let store { result.urges = store.urgeTally.phoneSummary }
        if let store { result.meds = store.document.phoneMedDoses(today: store.today); result.today = store.document.phoneToday(today: store.today) }
        return result
    }
    private func handle(_ event: PhoneLinkEvent) async -> PhoneLinkResult {
        switch event {
        case .pairingRequested(let request):
            pairing = request; NSApp.requestUserAttention(.informationalRequest)
            return PhoneLinkResult(ok: true, message: "Waiting for confirmation")
        case .pairingFinished(let request, let accepted):
            pairing = nil; pairingOpen = false
            if accepted {
                phones.removeAll { $0.id == request.phoneID }
                phones.append(PairedPhone(id: request.phoneID, name: request.phoneName, paired: Date())); persist()
                activity = "Paired with \(request.phoneName)."
            } else { activity = "Pairing with \(request.phoneName) was declined." }
            return PhoneLinkResult(ok: accepted, message: accepted ? "Paired" : "Declined")
        case .hello(let phoneID):
            touch(phoneID); return PhoneLinkResult(ok: true, message: "Connected to \(macName)")
        case .snapshot(let snapshot, let phoneID):
            guard let store else { return PhoneLinkResult(ok: false, message: "Ascend isn’t ready.") }
            if store.importHealth(snapshot, requestID: snapshot.requestID) {
                touch(phoneID)
                let count = snapshot.records.filter { snapshot.errors[$0.metric.rawValue] == nil }.count
                activity = "Synced \(count) Mi Fitness records from \(name(phoneID))."
                return PhoneLinkResult(ok: true, message: "Synced \(count) health records\(snapshot.errors.isEmpty ? "" : "; some types kept earlier data").")
            }
            let reason = store.notice ?? store.saveError ?? "The Mac couldn’t save this health data."
            store.notice = nil
            return PhoneLinkResult(ok: false, message: reason)
        case .meal(let meal, let phoneID):
            guard let store else { return PhoneLinkResult(ok: false, message: "Ascend isn’t ready.") }
            do {
                let (id, data, group) = try meal.validated()
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("ascend-meal-\(id.uuidString).\(meal.mediaType == "image/png" ? "png" : "jpg")")
                try data.write(to: file); defer { try? FileManager.default.removeItem(at: file) }
                if let group {
                    guard let complete = try store.addPhoneMealPhoto(meal: group.meal, part: group.part, parts: group.parts, file: file,
                                                                     takenAt: Date(timeIntervalSince1970: meal.takenAt), note: meal.note) else {
                        return PhoneLinkResult(ok: true, message: "Already received")
                    }
                    touch(phoneID)
                    if complete { store.meals.enqueue(group.meal) }
                    activity = "Meal photo \(group.part + 1) of \(group.parts) received from \(name(phoneID))."
                    return PhoneLinkResult(ok: true, message: "Meal received")
                }
                guard let entry = try store.addMeal(id: id, photos: [file], takenAt: Date(timeIntervalSince1970: meal.takenAt), note: meal.note, source: "phone") else {
                    return PhoneLinkResult(ok: true, message: "Already received")
                }
                touch(phoneID); store.meals.enqueue(entry.id)
                activity = "Meal photo received from \(name(phoneID))."
                return PhoneLinkResult(ok: true, message: "Meal received")
            } catch { return PhoneLinkResult(ok: false, message: error.localizedDescription) }
        case .urge(let urge, let phoneID):
            guard let store else { return PhoneLinkResult(ok: false, message: "Ascend isn’t ready.") }
            do {
                let log = try urge.validated()
                guard let saved = store.addPhoneUrge(log) else { return PhoneLinkResult(ok: true, message: "Already received") }
                guard saved else { return PhoneLinkResult(ok: false, message: store.saveError ?? "The Mac couldn’t save this urge.") }
                touch(phoneID); activity = "Urge logged from \(name(phoneID))."
                return PhoneLinkResult(ok: true, message: "Urge logged")
            } catch { return PhoneLinkResult(ok: false, message: error.localizedDescription) }
        case .medPhoto(let photo, let phoneID):
            guard let store else { return PhoneLinkResult(ok: false, message: "Ascend isn’t ready.") }
            do {
                let (id, batch, data) = try photo.validated()
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("ascend-med-\(id.uuidString).\(photo.mediaType == "image/png" ? "png" : "jpg")")
                try data.write(to: file); defer { try? FileManager.default.removeItem(at: file) }
                guard let complete = try store.addPhoneMedPhoto(id: id, batch: batch, batchSize: photo.batchSize, takenAt: Date(timeIntervalSince1970: photo.takenAt), file: file) else {
                    return PhoneLinkResult(ok: true, message: "Already received")
                }
                touch(phoneID)
                if complete { store.medsReader.enqueue(.batch(batch)); activity = "Medicine photos received from \(name(phoneID)). Sorting with Claude…" }
                return PhoneLinkResult(ok: true, message: "Medicine photo received")
            } catch { return PhoneLinkResult(ok: false, message: error.localizedDescription) }
        case .dose(let dose, let phoneID):
            guard let store else { return PhoneLinkResult(ok: false, message: "Ascend isn’t ready.") }
            guard let medID = UUID(uuidString: dose.medID), store.engine.date(dose.day) != nil, (0..<1440).contains(dose.minute), dose.takenAt.isFinite else {
                return PhoneLinkResult(ok: false, message: "The phone sent an invalid dose.")
            }
            let at = Date(timeIntervalSince1970: min(dose.takenAt, Date().timeIntervalSince1970))
            guard store.setDose(medID, day: dose.day, minute: dose.minute, taken: dose.taken, at: at, source: "phone") else {
                let reason = store.notice ?? store.saveError ?? "The Mac couldn’t save this dose."
                store.notice = nil
                return PhoneLinkResult(ok: false, message: reason)
            }
            touch(phoneID)
            return PhoneLinkResult(ok: true, message: dose.taken ? "Dose logged" : "Dose cleared")
        case .checkIn(let checkIn, let phoneID):
            guard let store else { return PhoneLinkResult(ok: false, message: "Ascend isn’t ready.") }
            guard store.applyPhoneCheckIn(checkIn) else {
                let reason = store.notice ?? store.saveError ?? "The Mac couldn’t save this check-in."
                store.notice = nil
                return PhoneLinkResult(ok: false, message: reason)
            }
            touch(phoneID)
            return PhoneLinkResult(ok: true, message: "Check-in saved")
        }
    }
    private func name(_ phoneID: String) -> String { phones.first { $0.id == phoneID }?.name ?? "your phone" }
    private func touch(_ phoneID: String) {
        guard let i = phones.firstIndex(where: { $0.id == phoneID }) else { return }
        phones[i].lastSync = Date(); persist()
    }
    private func persist() { defaults.set(try? JSONEncoder().encode(phones), forKey: "phoneLink.phones") }
    /// The Mac's private IPv4 address on Wi-Fi or Ethernet, for the download link.
    static func localIPv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var candidates: [(String, String)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET), entry.ifa_flags & UInt32(IFF_UP) != 0, entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host), parts = ip.split(separator: ".").compactMap { UInt8($0) }
            guard parts.count == 4, parts[0] == 10 || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 192 && parts[1] == 168) else { continue }
            candidates.append((String(cString: entry.ifa_name), ip))
        }
        return (candidates.first { $0.0 == "en0" } ?? candidates.first)?.1
    }
}
