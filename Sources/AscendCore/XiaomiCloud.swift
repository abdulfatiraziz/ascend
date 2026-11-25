import Foundation
import CryptoKit

/// Reads the watch's data from the Mi Fitness cloud, where Mi Fitness keeps everything it syncs from the watch.
/// Mi Fitness only passes workout heart rate on to Health Connect, so this is the way to all-day heart rate, stress
/// and resting heart rate. Unofficial: the protocol (signed, RC4-encrypted requests to `hlth.io.mi.com`, Xiaomi account
/// sign-in for the `miothealth` service) follows Jenwein/mifit and Mi-Fitness-Sync (both MIT).
/// Secrets (passToken, ssecurity, serviceToken) are never logged or put in error messages.
public struct XiaomiSession: Codable, Equatable, Sendable {
    public var userID: String
    public var cUserID: String
    public var passToken: String
    public var ssecurity: String
    public var serviceToken: String
    public var deviceID: String
    /// Server prefix such as "i2" (India), "sg", "de", "us"; "cn" has none. Empty until found.
    public var region: String
    public var created: Double
    public init(userID: String, cUserID: String, passToken: String, ssecurity: String, serviceToken: String, deviceID: String, region: String, created: Double) {
        self.userID = userID; self.cUserID = cUserID; self.passToken = passToken; self.ssecurity = ssecurity
        self.serviceToken = serviceToken; self.deviceID = deviceID; self.region = region; self.created = created
    }
}

public struct XiaomiLoginChallenge: Sendable {
    /// Opening this in a browser that's signed in to the Xiaomi account approves the sign-in.
    public var loginURL: URL
    var pollURL: URL
    var deviceID: String
}

public enum XiaomiCloudError: LocalizedError, Equatable {
    case signInExpired, notApproved, securityCheck(String), refused(String), network(String), unreadable
    public var errorDescription: String? {
        switch self {
        case .signInExpired: "The Mi Fitness sign-in has expired. Sign in again."
        case .notApproved: "The sign-in wasn’t approved in time. Try again."
        case .securityCheck: "Xiaomi wants you to confirm this sign-in. Open the page it showed, confirm, then sign in again."
        case .refused(let why): "Xiaomi refused the request: \(why)"
        case .network(let why): "Couldn’t reach Xiaomi: \(why)"
        case .unreadable: "Xiaomi sent a reply Cipher couldn’t read."
        }
    }
}

public enum XiaomiCloud {
    static let sid = "miothealth"
    static let accountHost = "https://account.xiaomi.com"
    /// Tried in order when the sign-in doesn't say which server holds the account.
    public static let regions = ["i2", "sg", "de", "us", "ru", "cn"]

    // MARK: Request signing

    /// RC4 that discards the first 1024 keystream bytes, with one continuous state per cipher.
    struct RC4 {
        private var s = [UInt8](0...255), i = 0, j = 0
        init(key: [UInt8]) {
            var j = 0
            for i in 0..<256 { j = (j + Int(s[i]) + Int(key[i % key.count])) & 255; s.swapAt(i, j) }
            _ = apply([UInt8](repeating: 0, count: 1024))
        }
        mutating func apply(_ data: [UInt8]) -> [UInt8] {
            data.map { byte in
                i = (i + 1) & 255; j = (j + Int(s[i])) & 255; s.swapAt(i, j)
                return byte ^ s[(Int(s[i]) + Int(s[j])) & 255]
            }
        }
    }
    /// 8 random bytes then the minutes since 1970 as a big-endian Int32, base64.
    static func nonce(now: Date = Date(), random: [UInt8] = (0..<8).map { _ in UInt8.random(in: 0...255) }) -> String {
        let minutes = Int32(truncatingIfNeeded: Int(now.timeIntervalSince1970 * 1000) / 60_000).bigEndian
        return Data(random + withUnsafeBytes(of: minutes) { Array($0) }).base64EncodedString()
    }
    /// base64(SHA256(ssecurity bytes + nonce bytes)); the RC4 key and the last part of every signature.
    public static func signedNonce(ssecurity: String, nonce: String) throws -> String {
        guard let a = Data(base64Encoded: ssecurity), let b = Data(base64Encoded: nonce) else { throw XiaomiCloudError.unreadable }
        return Data(SHA256.hash(data: a + b)).base64EncodedString()
    }
    /// base64(SHA1("GET&<path>&k=v… (sorted)&<signed nonce>")).
    static func signature(method: String = "GET", path: String, params: [String: String], signedNonce: String) -> String {
        let parts = [method, path] + params.keys.sorted().map { "\($0)=\(params[$0]!)" } + [signedNonce]
        return Data(Insecure.SHA1.hash(data: Data(parts.joined(separator: "&").utf8))).base64EncodedString()
    }
    /// The query for one request: the plain `data` JSON plus `rc4_hash__`, each RC4-encrypted in key order with one cipher,
    /// then `signature` over the encrypted values and the `_nonce`.
    public static func encryptedQuery(path: String, data: String, nonce: String, ssecurity: String) throws -> [String: String] {
        let key = try signedNonce(ssecurity: ssecurity, nonce: nonce)
        var plain = ["data": data]
        plain["rc4_hash__"] = signature(path: path, params: plain, signedNonce: key)
        var cipher = RC4(key: [UInt8](Data(base64Encoded: key)!))
        var query: [String: String] = [:]
        for name in plain.keys.sorted() { query[name] = Data(cipher.apply([UInt8](plain[name]!.utf8))).base64EncodedString() }
        query["signature"] = signature(path: path, params: query, signedNonce: key)
        query["_nonce"] = nonce
        return query
    }
    public static func decrypt(_ body: Data, nonce: String, ssecurity: String) throws -> [String: Any] {
        let key = try signedNonce(ssecurity: ssecurity, nonce: nonce)
        let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encrypted = Data(base64Encoded: text) else { throw XiaomiCloudError.unreadable }
        var cipher = RC4(key: [UInt8](Data(base64Encoded: key)!))
        guard let object = try? JSONSerialization.jsonObject(with: Data(cipher.apply([UInt8](encrypted)))) as? [String: Any] else { throw XiaomiCloudError.unreadable }
        return object
    }
    static func queryString(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        return params.keys.sorted().map { "\($0)=\(params[$0]!.addingPercentEncoding(withAllowedCharacters: allowed)!)" }.joined(separator: "&")
    }

    // MARK: Network

    final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    static let http: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCache = nil
        return URLSession(configuration: config)
    }()
    static func get(_ url: URL, cookies: [String: String] = [:], headers: [String: String] = [:], timeout: TimeInterval = 30,
                    followRedirects: Bool = true) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        if !cookies.isEmpty { request.setValue(cookies.keys.sorted().map { "\($0)=\(cookies[$0]!)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        do {
            let (data, response) = try await http.data(for: request, delegate: followRedirects ? nil : NoRedirect())
            guard let response = response as? HTTPURLResponse else { throw XiaomiCloudError.unreadable }
            return (data, response)
        } catch let error as XiaomiCloudError { throw error
        } catch { throw XiaomiCloudError.network(error.localizedDescription) }
    }
    static func cookies(_ response: HTTPURLResponse) -> [String: String] {
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { if let k = $1.key as? String, let v = $1.value as? String { $0[k] = v } }
        return HTTPCookie.cookies(withResponseHeaderFields: fields, for: response.url ?? URL(string: accountHost)!)
            .reduce(into: [:]) { $0[$1.name] = $1.value }
    }
    /// Account replies start with "&&&START&&&".
    static func accountJSON(_ data: Data) throws -> [String: Any] {
        var text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("&&&START&&&") { text.removeFirst("&&&START&&&".count) }
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw XiaomiCloudError.unreadable }
        return object
    }
    static func text(_ value: Any?) -> String {
        switch value { case let s as String: s; case let n as NSNumber: n.stringValue; default: "" }
    }

    // MARK: Sign-in

    /// Starts a sign-in. Open `loginURL` in the browser; `finishSignIn` then waits for the approval.
    public static func startSignIn() async throws -> XiaomiLoginChallenge {
        let device = (0..<8).map { _ in String(format: "%02X", UInt8.random(in: 0...255)) }.joined()
        let (data, response) = try await get(URL(string: "\(accountHost)/longPolling/loginUrl?sid=\(sid)&_json=true")!, cookies: ["deviceId": device])
        let json = try accountJSON(data)
        guard response.statusCode == 200, text(json["code"]) == "0", let login = URL(string: text(json["loginUrl"]).replacingOccurrences(of: "_json=true", with: "_json=false")),
              let poll = URL(string: text(json["lp"])), poll.scheme == "https" else { throw XiaomiCloudError.refused(text(json["desc"]).isEmpty ? "sign-in" : text(json["desc"])) }
        return XiaomiLoginChallenge(loginURL: login, pollURL: poll, deviceID: device)
    }
    /// Waits up to about 10 minutes for the sign-in to be approved, then trades it for a Mi Fitness session.
    public static func finishSignIn(_ challenge: XiaomiLoginChallenge) async throws -> XiaomiSession {
        for _ in 0..<10 {
            try Task.checkCancellation()
            guard let (data, response) = try? await get(challenge.pollURL, cookies: ["deviceId": challenge.deviceID], timeout: 65), response.statusCode == 200 else { continue }
            let login = try loginContent(data, response: response, known: [:])
            var session = try await exchange(login, deviceID: challenge.deviceID)
            session.region = try await findRegion(session)
            return session
        }
        throw XiaomiCloudError.notApproved
    }
    struct LoginContent { var userID, cUserID, passToken, ssecurity, nonce, location: String }
    static func loginContent(_ data: Data, response: HTTPURLResponse, known: [String: String]) throws -> LoginContent {
        let json = try accountJSON(data), jar = cookies(response)
        guard text(json["code"]) == "0" else { throw XiaomiCloudError.signInExpired }
        if text(json["securityStatus"]) != "0" && !text(json["securityStatus"]).isEmpty { throw XiaomiCloudError.securityCheck(text(json["notificationUrl"])) }
        var pragma: [String: Any] = [:]
        if let raw = response.value(forHTTPHeaderField: "Extension-Pragma"), let p = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] { pragma = p }
        func field(_ name: String) -> String { [text(json[name]), jar[name] ?? "", known[name] ?? "", text(pragma[name])].first { !$0.isEmpty } ?? "" }
        let content = LoginContent(userID: field("userId"), cUserID: field("cUserId"), passToken: field("passToken"),
                                   ssecurity: field("ssecurity"), nonce: field("nonce"), location: text(json["location"]))
        guard ![content.userID, content.cUserID, content.passToken, content.ssecurity, content.nonce, content.location].contains(where: \.isEmpty) else {
            throw XiaomiCloudError.unreadable
        }
        return content
    }
    /// Trades a login for the `miothealth` service token (read from the first response's cookies, not following redirects).
    static func exchange(_ login: LoginContent, deviceID: String) async throws -> XiaomiSession {
        guard var parts = URLComponents(string: login.location), parts.scheme == "https" else { throw XiaomiCloudError.unreadable }
        let sign = Data(Insecure.SHA1.hash(data: Data("nonce=\(login.nonce)&\(login.ssecurity)".utf8))).base64EncodedString()
        parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name: "clientSign", value: sign), URLQueryItem(name: "_userIdNeedEncrypt", value: "true")]
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = parts.url else { throw XiaomiCloudError.unreadable }
        let (_, response) = try await get(url, followRedirects: false)
        let jar = cookies(response)
        guard let token = jar["\(sid)_serviceToken"] ?? jar["serviceToken"] else { throw XiaomiCloudError.signInExpired }
        return XiaomiSession(userID: login.userID, cUserID: login.cUserID, passToken: login.passToken, ssecurity: login.ssecurity,
                             serviceToken: token, deviceID: deviceID, region: "", created: Date().timeIntervalSince1970)
    }
    /// Gets a fresh service token with the stored passToken, as Mi Fitness does when its token is refused.
    public static func renew(_ session: XiaomiSession) async throws -> XiaomiSession {
        let (data, response) = try await get(URL(string: "\(accountHost)/pass/serviceLogin?sid=\(sid)&_json=true")!,
                                             cookies: ["userId": session.userID, "passToken": session.passToken, "deviceId": session.deviceID], followRedirects: false)
        guard response.statusCode == 200 else { throw XiaomiCloudError.signInExpired }
        let login = try loginContent(data, response: response, known: ["userId": session.userID, "passToken": session.passToken, "cUserId": session.cUserID])
        var renewed = try await exchange(login, deviceID: session.deviceID)
        renewed.region = session.region; renewed.created = session.created
        return renewed
    }
    static func findRegion(_ session: XiaomiSession) async throws -> String {
        let now = Date().timeIntervalSince1970
        for region in regions {
            var probe = session; probe.region = region
            if let reply = try? await call(probe, "data/get_fitness_data_by_time", ["key": "heart_rate", "end_time": Int(now), "reverse": true]),
               let result = reply["result"] as? [String: Any], !((result["data_list"] as? [Any]) ?? []).isEmpty { return region }
        }
        return regions[0]
    }

    // MARK: Health API

    /// One signed call under `app/v1/`. HTTP 401 means the service token needs renewing.
    static func call(_ session: XiaomiSession, _ endpoint: String, _ body: [String: Any]) async throws -> [String: Any] {
        let path = "/app/v1/" + endpoint
        let host = session.region == "cn" || session.region.isEmpty ? "hlth.io.mi.com" : "\(session.region).hlth.io.mi.com"
        let json = String(decoding: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        let nonce = nonce()
        let query = try encryptedQuery(path: path, data: json, nonce: nonce, ssecurity: session.ssecurity)
        let (data, response) = try await get(URL(string: "https://\(host)\(path)?\(queryString(query))")!,
            cookies: ["serviceToken": session.serviceToken, "cUserId": session.cUserID, "userId": session.userID], headers: ["region_tag": session.region])
        if response.statusCode == 401 { throw XiaomiCloudError.signInExpired }
        guard response.statusCode == 200 else { throw XiaomiCloudError.refused("HTTP \(response.statusCode)") }
        let reply = try decrypt(data, nonce: nonce, ssecurity: session.ssecurity)
        guard text(reply["code"]) == "0" else { throw XiaomiCloudError.refused(text(reply["message"]).isEmpty ? "code \(text(reply["code"]))" : text(reply["message"])) }
        return reply
    }
    /// Every row of a paged read, following `next_key` (at most 60 pages).
    static func rows(_ session: XiaomiSession, _ endpoint: String, _ body: [String: Any]) async throws -> [[String: Any]] {
        var rows: [[String: Any]] = [], request = body
        for _ in 0..<60 {
            let reply = try await call(session, endpoint, request)
            let result = reply["result"] as? [String: Any] ?? reply
            rows += result["data_list"] as? [[String: Any]] ?? []
            let next = text(result["next_key"])
            guard (result["has_more"] as? Bool) == true, !next.isEmpty, next != text(request["next_key"]) else { break }
            request["next_key"] = next
            try await Task.sleep(for: .milliseconds(300))
        }
        return rows
    }
    /// Raw readings of `key` between `start` and `end`. The service drops readings near a window's start, so the
    /// request starts a day early and the extra rows are filtered out here.
    public static func raw(_ session: XiaomiSession, key: String, start: Double, end: Double) async throws -> [[String: Any]] {
        try await rows(session, "data/get_fitness_data_by_time", ["key": key, "start_time": Int(start) - 86_400, "end_time": Int(end), "reverse": true])
    }
    public static func daily(_ session: XiaomiSession, key: String, start: Double, end: Double) async throws -> [[String: Any]] {
        try await rows(session, "data/get_aggregated_fitness_data_by_time",
                       ["tag": "daily_report", "key": key, "start_time": Int(start) - 86_400, "end_time": Int(end), "reverse": true, "limit": 50])
    }

    // MARK: Records

    static func value(_ row: [String: Any]) -> [String: Any]? {
        guard let raw = row["value"] as? String else { return row["value"] as? [String: Any] }
        return try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
    }
    static func number(_ any: Any?) -> Double? {
        switch any { case let n as NSNumber: n.doubleValue; case let s as String: Double(s); default: nil }
    }
    /// Turns raw heart-rate, SpO2 and stress rows into records within `range`; rows with missing or impossible values are skipped.
    public static func records(heart: [[String: Any]], oxygen: [[String: Any]], stress: [[String: Any]], range: ClosedRange<Double>) -> [HealthRecord] {
        var out: [String: HealthRecord] = [:]
        func add(_ rows: [[String: Any]], _ metric: HealthMetric, field: String, prefix: String) {
            for row in rows {
                guard let v = value(row), let time = number(v["time"]), let reading = number(v[field]), range.contains(time),
                      reading > 0, metric.bounds.contains(reading) else { continue }
                let record = HealthRecord(id: "xm-\(prefix)-\(Int(time))", metric: metric, start: time, end: time, value: reading, device: "Mi Fitness cloud")
                out[record.identity] = record
            }
        }
        add(heart, .heartRate, field: "bpm", prefix: "hr")
        add(oxygen, .oxygen, field: "spo2", prefix: "spo2")
        add(stress, .stress, field: "stress", prefix: "stress")
        return out.values.sorted { $0.start < $1.start }
    }
    /// Daily resting heart rate from the daily heart-rate reports. A report's `time` is that local date's midnight written as
    /// UTC, so the date is read in UTC and the record spans that day in `timeZone`.
    public static func restingRecords(_ rows: [[String: Any]], timeZone: TimeZone, range: ClosedRange<Double>) -> [HealthRecord] {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        var local = Calendar(identifier: .gregorian); local.timeZone = timeZone
        var out: [String: HealthRecord] = [:]
        for row in rows {
            guard let stamp = number(row["time"]), let v = value(row), let rest = number(v["avg_rhr"]), rest > 0, rest <= 400 else { continue }
            let parts = utc.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: stamp))
            guard let start = local.date(from: parts)?.timeIntervalSince1970, range.contains(start) || range.contains(start + 86_399) else { continue }
            let day = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
            out[day] = HealthRecord(id: "xm-rhr-\(day)", metric: .restingHeartRate, start: start, end: start + 86_399, value: rest, device: "Mi Fitness cloud")
        }
        return out.values.sorted { $0.start < $1.start }
    }
    /// Reads `days` days up to `now` (raw reads in 3-day windows) and returns records ready for `mergingCloud`.
    public static func fetch(_ session: XiaomiSession, days: Int, timeZone: TimeZone, now: Date = Date()) async throws -> (records: [HealthRecord], range: ClosedRange<Double>) {
        let end = now.timeIntervalSince1970, start = end - Double(days) * 86_400
        var heart: [[String: Any]] = [], oxygen: [[String: Any]] = [], stress: [[String: Any]] = []
        var windowEnd = end
        while windowEnd > start {
            let windowStart = max(start, windowEnd - 3 * 86_400)
            heart += try await raw(session, key: "heart_rate", start: windowStart, end: windowEnd)
            oxygen += try await raw(session, key: "spo2", start: windowStart, end: windowEnd)
            stress += try await raw(session, key: "stress", start: windowStart, end: windowEnd)
            windowEnd = windowStart
        }
        let resting = try await daily(session, key: "heart_rate", start: start, end: end)
        let range = start...end
        return (records(heart: heart, oxygen: oxygen, stress: stress, range: range) + restingRecords(resting, timeZone: timeZone, range: range), range)
    }
}
