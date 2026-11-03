import Foundation

public enum DrTrustError: LocalizedError, Equatable {
    case phone, code, expired, refused, network, unreadable, incomplete, profile, keychain
    public var errorDescription: String? {
        switch self {
        case .phone: return "Enter your Dr Trust phone number with country code, for example +91 followed by your number."
        case .code: return "The code was not accepted. Check the code or request a new one."
        case .expired: return "Your Dr Trust sign-in expired. Sign in again to resume automatic sync."
        case .refused: return "Dr Trust could not complete the request. Try again later."
        case .network: return "Couldn’t reach Dr Trust. Your stored readings are unchanged."
        case .unreadable: return "Dr Trust returned an unreadable response. Your stored readings are unchanged."
        case .incomplete: return "Dr Trust returned incomplete history. Your stored readings are unchanged."
        case .profile: return "This Dr Trust account does not match your stored body readings. No data was changed."
        case .keychain: return "The Dr Trust sign-in could not be saved in Keychain."
        }
    }
}

/// Credentials are kept only in Keychain by the Mac service, never in body/tracker backups.
public struct DrTrustSession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Double
    public var userID: String
    public var groupID: String
    public init(accessToken: String, refreshToken: String, expiresAt: Double, userID: String, groupID: String) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt
        self.userID = userID; self.groupID = groupID
    }
    public func validate() throws {
        for value in [accessToken, refreshToken, userID, groupID] {
            guard !value.isEmpty, value.count <= 50_000, !value.contains("\r"), !value.contains("\n") else { throw DrTrustError.unreadable }
        }
        guard expiresAt.isFinite, expiresAt > 0 else { throw DrTrustError.unreadable }
    }
}
public struct DrTrustChallenge: Sendable {
    public let phone: String
    public let session: String
    public let expiresAt: Date
}

/// Read-only account/history client. Only the two OTP endpoints and token renewal send POST requests.
public struct DrTrustCloud: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport
    public init(transport: @escaping Transport = DrTrustCloud.send) { self.transport = transport }
    private static let base = URL(string: "https://api.drtrust360.com/")!
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private static let http: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil; c.httpShouldSetCookies = false; c.urlCache = nil
        return URLSession(configuration: c)
    }()
    public static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await http.data(for: request, delegate: NoRedirect())
            guard let http = response as? HTTPURLResponse else { throw DrTrustError.unreadable }
            return (data, http)
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as DrTrustError { throw error }
        catch { throw DrTrustError.network }
    }
    private func request(_ path: String, body: [String: BodyValue]? = nil, session: DrTrustSession? = nil,
                         token: String? = nil, query: [URLQueryItem] = []) async throws -> (Data, Int) {
        try Task.checkCancellation()
        var components = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token = token ?? session?.accessToken {
            guard !token.isEmpty, token.count <= 50_000, !token.contains("\r"), !token.contains("\n") else { throw DrTrustError.unreadable }
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        if let session {
            try session.validate()
            request.setValue(session.userID, forHTTPHeaderField: "userId")
            request.setValue(session.groupID, forHTTPHeaderField: "groupId")
        }
        request.setValue("7.4.9", forHTTPHeaderField: "appVersion")
        request.setValue("190", forHTTPHeaderField: "appVersionCode")
        request.setValue("android", forHTTPHeaderField: "osType")
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard data.count <= 8_000_000 else { throw DrTrustError.unreadable }
        return (data, response.statusCode)
    }
    private func accepted(_ status: Int, authentication: Bool = false) throws {
        if status == 401 || status == 403 { throw DrTrustError.expired }
        if authentication && status == 400 { throw DrTrustError.code }
        guard status == 200 else { throw DrTrustError.refused }
    }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw DrTrustError.unreadable }
    }
    private struct Authentication: Decodable {
        var accessToken: String
        var refreshToken: String?
        var expiresIn: Int
    }
    private struct Login: Decodable {
        var challengeName: String?
        var session: String?
        var authenticationResult: Authentication?
    }
    public func beginSignIn(phone: String, now: Date = Date()) async throws -> DrTrustChallenge {
        let phone = phone.filter { !$0.isWhitespace && $0 != "-" && $0 != "(" && $0 != ")" }
        guard phone.first == "+", (8...16).contains(phone.count), phone.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber }) else { throw DrTrustError.phone }
        let (data, status) = try await request("public/login", body: ["userName": .text(phone), "loginType": .text("otp"), "shortOtp": .bool(true)])
        try accepted(status, authentication: true)
        let result = try decode(Login.self, data)
        guard result.challengeName == "CUSTOM_CHALLENGE", let session = result.session, !session.isEmpty, session.count < 50_000 else { throw DrTrustError.unreadable }
        return DrTrustChallenge(phone: phone, session: session, expiresAt: now.addingTimeInterval(300))
    }
    public func verify(_ challenge: DrTrustChallenge, code: String, now: Date = Date()) async throws -> DrTrustSession {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (4...8).contains(code.count), code.allSatisfy({ $0.isASCII && $0.isNumber }), challenge.expiresAt > now else { throw DrTrustError.code }
        let (data, status) = try await request("public/login/otp", body: ["userName": .text(challenge.phone), "session": .text(challenge.session), "otp": .text(code), "shortOtp": .bool(true)])
        try accepted(status, authentication: true)
        guard let auth = try decode(Login.self, data).authenticationResult, let refresh = auth.refreshToken, !refresh.isEmpty else { throw DrTrustError.unreadable }
        let (profileData, profileStatus) = try await request("user", token: auth.accessToken)
        try accepted(profileStatus)
        struct Profile: Decodable {
            struct Info: Decodable { var userId: String; var groupId: String }
            var userPersonalInfo: Info
        }
        let profile = try decode(Profile.self, profileData).userPersonalInfo
        guard (1...604800).contains(auth.expiresIn) else { throw DrTrustError.unreadable }
        let session = DrTrustSession(accessToken: auth.accessToken, refreshToken: refresh, expiresAt: now.timeIntervalSince1970 + Double(auth.expiresIn), userID: profile.userId, groupID: profile.groupId)
        try session.validate()
        return session
    }
    public func renew(_ previous: DrTrustSession, now: Date = Date()) async throws -> DrTrustSession {
        try previous.validate()
        let (data, status) = try await request("public/refresh-token", body: ["refreshToken": .text(previous.refreshToken)])
        if [400, 401, 403].contains(status) { throw DrTrustError.expired }
        try accepted(status)
        guard let auth = try decode(Login.self, data).authenticationResult, (1...604800).contains(auth.expiresIn), !auth.accessToken.isEmpty else { throw DrTrustError.unreadable }
        var result = previous
        result.accessToken = auth.accessToken
        if let refresh = auth.refreshToken, !refresh.isEmpty { result.refreshToken = refresh }
        result.expiresAt = now.timeIntervalSince1970 + Double(auth.expiresIn)
        try result.validate()
        return result
    }
    /// Persist rotated credentials before fetching. A rejected access token triggers at most one renewal.
    public func synchronize(_ stored: DrTrustSession, now: Date = Date(),
                            saveSession: @escaping @Sendable (DrTrustSession) async throws -> Void) async throws -> (session: DrTrustSession, records: [BodyMeasurement]) {
        var session = stored
        var renewed = false
        if session.expiresAt <= now.timeIntervalSince1970 + 60 {
            session = try await renew(session, now: now)
            try Task.checkCancellation()
            try await saveSession(session)
            renewed = true
        }
        do { return (session, try await fetch(session)) }
        catch DrTrustError.expired where !renewed {
            session = try await renew(session, now: now)
            try Task.checkCancellation()
            try await saveSession(session)
            return (session, try await fetch(session))
        }
    }
    public func fetch(_ session: DrTrustSession) async throws -> [BodyMeasurement] {
        try session.validate()
        struct Page: Decodable {
            var content: [[String: BodyValue]]
            var totalElements: Int; var totalPages: Int; var number: Int; var last: Bool
        }
        var records: [BodyMeasurement] = [], total: Int?, pages: Int?
        for pageNumber in 0..<1000 {
            let query = [URLQueryItem(name: "pageNumber", value: String(pageNumber)), URLQueryItem(name: "pageSize", value: "100"),
                         URLQueryItem(name: "type", value: "FAT_SCALE_DATA"), URLQueryItem(name: "userId", value: session.userID)]
            let (data, status) = try await request("scale/reading/list", session: session, query: query)
            try accepted(status)
            let page = try decode(Page.self, data)
            if total == nil { total = page.totalElements; pages = page.totalPages }
            // Spring may represent an empty result as either zero or one page.
            let expectedPages = max(1, page.totalPages)
            guard (0...100_000).contains(page.totalElements), (0...1000).contains(page.totalPages),
                  page.number == pageNumber, page.totalElements == total, page.totalPages == pages,
                  page.last == (pageNumber == expectedPages - 1), page.content.count <= 100 else { throw DrTrustError.incomplete }
            let incoming = page.content.map { BodyMeasurement(fields: $0) }
            for record in incoming {
                guard record.userID == session.userID else { throw DrTrustError.profile }
                try record.validate()
            }
            records += incoming
            guard records.count <= 100_000 else { throw DrTrustError.incomplete }
            if page.last {
                guard records.count == total, Set(records.map(\.id)).count == records.count else { throw DrTrustError.incomplete }
                return records
            }
        }
        throw DrTrustError.incomplete
    }
}

/// A launch/activation/wake may catch up an overdue sync, but repeated failures are not polled on every focus change.
public enum DrTrustSyncSchedule {
    public static func isDue(lastSync: Date?, lastAttempt: Date?, now: Date = Date()) -> Bool {
        let overdue = lastSync.map { now.timeIntervalSince($0) >= 3600 } ?? true
        let retryAllowed = lastAttempt.map { now.timeIntervalSince($0) >= 900 } ?? true
        return overdue && retryAllowed
    }
}
