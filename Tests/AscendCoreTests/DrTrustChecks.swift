import Foundation
import AscendCore

private struct DrTrustCheckFailure: Error { var message: String }
private actor DrTrustFixture {
    struct Reply: Sendable { var path: String; var status: Int; var data: Data }
    var replies: [Reply]
    var requests: [URLRequest] = []
    var saved: [DrTrustSession] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw DrTrustCheckFailure(message: "Unexpected request") }
        let r = replies.removeFirst()
        guard request.url?.path == r.path, request.url?.host == "api.drtrust360.com", request.url?.scheme == "https" else { throw DrTrustCheckFailure(message: "Unexpected endpoint") }
        return (r.data, HTTPURLResponse(url: request.url!, statusCode: r.status, httpVersion: nil, headerFields: nil)!)
    }
    func save(_ s: DrTrustSession) { saved.append(s) }
}

func runDrTrustChecks() async -> (count: Int, failures: Int) {
    var count = 0, failures = 0
    func expect(_ b: Bool, _ message: String = "Assertion failed") throws { if !b { throw DrTrustCheckFailure(message: message) } }
    func check(_ name: String, _ body: () async throws -> Void) async {
        count += 1
        do { try await body(); print("PASS: \(name)") } catch { failures += 1; print("FAIL: \(name): \(error)") }
    }
    func reply(_ path: String, _ object: [String: Any], status: Int = 200) throws -> DrTrustFixture.Reply {
        .init(path: path, status: status, data: try JSONSerialization.data(withJSONObject: object))
    }
    func row(_ id: String = "one", user: String = "owner") -> [String: Any] {
        ["id": id, "userId": user, "createdAt": 1785041707000, "measuredWeight": 78, "unknown": NSNull()]
    }
    func page(_ rows: [[String: Any]], number: Int = 0, total: Int = 1, pages: Int = 1, last: Bool = true) -> [String: Any] {
        ["content": rows, "totalElements": total, "totalPages": pages, "number": number, "last": last]
    }
    let now = Date(timeIntervalSince1970: 1_793_710_000)
    let session = DrTrustSession(accessToken: "old-access", refreshToken: "old-refresh", expiresAt: now.timeIntervalSince1970 + 3600, userID: "owner", groupID: "group")
    func renewed(_ refresh: Any = NSNull()) -> [String: Any] {
        ["authenticationResult": ["accessToken": "new-access", "refreshToken": refresh, "expiresIn": 3600]]
    }
    await check("Dr Trust OTP flow scopes history to the authenticated profile and sends no credentials to other hosts") {
        let fixture = try DrTrustFixture([
            reply("/public/login", ["challengeName": "CUSTOM_CHALLENGE", "session": "challenge"]),
            reply("/public/login/otp", ["authenticationResult": ["accessToken": "access", "refreshToken": "refresh", "expiresIn": 3600]]),
            reply("/user", ["userPersonalInfo": ["userId": "owner", "groupId": "group"]])
        ])
        let client = DrTrustCloud(transport: { try await fixture.send($0) })
        let challenge = try await client.beginSignIn(phone: "+91 90000 00000", now: now)
        let actual = try await client.verify(challenge, code: "1234", now: now)
        try expect(actual.userID == "owner" && actual.refreshToken == "refresh")
        let reqs = await fixture.requests
        let body = try JSONSerialization.jsonObject(with: reqs[0].httpBody!) as! [String: Any]
        try expect(body["userName"] as? String == "+919000000000" && body["loginType"] as? String == "otp")
        try expect(reqs[0].value(forHTTPHeaderField: "Authorization") == nil && reqs[2].value(forHTTPHeaderField: "Authorization") == "Bearer access")
    }
    await check("Dr Trust fetch validates every page, stable IDs, profile, headers and original fields") {
        let fixture = try DrTrustFixture([
            reply("/scale/reading/list", page([row()], number: 0, total: 2, pages: 2, last: false)),
            reply("/scale/reading/list", page([row("two")], number: 1, total: 2, pages: 2))
        ])
        let client = DrTrustCloud(transport: { try await fixture.send($0) })
        let records = try await client.fetch(session)
        try expect(records.count == 2 && records[0].fields["unknown"] == .null)
        let reqs = await fixture.requests
        for (index, r) in reqs.enumerated() {
            let q = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)!.queryItems!
            try expect(q.contains(URLQueryItem(name: "pageNumber", value: String(index))) && q.contains(URLQueryItem(name: "type", value: "FAT_SCALE_DATA")))
            try expect(r.value(forHTTPHeaderField: "userId") == "owner" && r.value(forHTTPHeaderField: "groupId") == "group")
        }
    }
    await check("expiring Dr Trust access renews once, retains an omitted refresh token and saves before reading") {
        let fixture = try DrTrustFixture([reply("/public/refresh-token", renewed()), reply("/scale/reading/list", page([row()]))])
        let client = DrTrustCloud(transport: { try await fixture.send($0) })
        var expired = session; expired.expiresAt = now.timeIntervalSince1970 - 1
        let result = try await client.synchronize(expired, now: now) { s in await fixture.save(s) }
        try expect(result.records.count == 1 && result.session.accessToken == "new-access" && result.session.refreshToken == "old-refresh")
        try expect(await fixture.saved == [result.session])
        let reqs = await fixture.requests
        try expect(reqs[1].value(forHTTPHeaderField: "Authorization") == "Bearer new-access")
    }
    await check("Dr Trust 401 triggers one refresh and retry, persisting rotated refresh credentials") {
        let fixture = try DrTrustFixture([reply("/scale/reading/list", [:], status: 401), reply("/public/refresh-token", renewed("new-refresh")), reply("/scale/reading/list", page([row()]))])
        let client = DrTrustCloud(transport: { try await fixture.send($0) })
        let result = try await client.synchronize(session, now: now) { s in await fixture.save(s) }
        try expect(result.session.refreshToken == "new-refresh" && result.records.count == 1)
        let requestCount = await fixture.requests.count, saveCount = await fixture.saved.count
        try expect(requestCount == 3 && saveCount == 1)
    }
    await check("Dr Trust permanent expiry and a second 401 stop without an infinite retry or deleting stored readings") {
        for replies in [try [reply("/public/refresh-token", [:], status: 400)],
                        try [reply("/public/refresh-token", renewed()), reply("/scale/reading/list", [:], status: 401)]] {
            let fixture = DrTrustFixture(replies)
            var expired = session; expired.expiresAt = now.timeIntervalSince1970
            do { _ = try await DrTrustCloud(transport: { try await fixture.send($0) }).synchronize(expired, now: now) { s in await fixture.save(s) }; throw DrTrustCheckFailure(message: "Expected expiry") }
            catch DrTrustError.expired { }
            try expect(await fixture.requests.count == replies.count)
        }
    }
    await check("Dr Trust rotated session survives a later history failure; server error text never exposes secrets") {
        let fixture = try DrTrustFixture([reply("/public/refresh-token", renewed("rotated")), reply("/scale/reading/list", ["message": "secret-token-and-phone"], status: 500)])
        var expired = session; expired.expiresAt = now.timeIntervalSince1970
        do { _ = try await DrTrustCloud(transport: { try await fixture.send($0) }).synchronize(expired, now: now) { s in await fixture.save(s) }; throw DrTrustCheckFailure(message: "Expected failure") }
        catch let error as DrTrustError { try expect(!error.localizedDescription.contains("secret-token")) }
        try expect(await fixture.saved.first?.refreshToken == "rotated")
    }
    await check("Dr Trust partial, duplicate, changing-total, foreign-profile and malformed histories are rejected") {
        let variants: [[DrTrustFixture.Reply]] = try [
            [reply("/scale/reading/list", page([row()], total: 2))],
            [reply("/scale/reading/list", page([row(), row()], total: 2))],
            [reply("/scale/reading/list", page([row(user: "other")]))],
            [reply("/scale/reading/list", ["unexpected": true])],
            [reply("/scale/reading/list", page([row()], total: 2, pages: 2, last: false)), reply("/scale/reading/list", page([row("two")], number: 1, total: 3, pages: 2))]
        ]
        for replies in variants {
            let fixture = DrTrustFixture(replies)
            do { _ = try await DrTrustCloud(transport: { try await fixture.send($0) }).fetch(session); throw DrTrustCheckFailure(message: "Expected rejection") }
            catch is DrTrustError { } catch is ValidationError { }
        }
    }
    await check("empty successful Dr Trust responses retain existing history and duplicate cloud sync does not rewrite it") {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ascend-drtrust-cloud-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("body-measurements.json")
        let fixture = try DrTrustFixture([reply("/scale/reading/list", page([row()]))])
        let records = try await DrTrustCloud(transport: { try await fixture.send($0) }).fetch(session)
        _ = try BodyStorage.mergeRecords(records, to: url)
        let bytes = try Data(contentsOf: url)
        _ = try BodyStorage.mergeRecords([], to: url)
        _ = try BodyStorage.mergeRecords(records, to: url)
        try expect(try Data(contentsOf: url) == bytes)
        let empty = try DrTrustFixture([reply("/scale/reading/list", page([], total: 0, pages: 0))])
        try expect(try await DrTrustCloud(transport: { try await empty.send($0) }).fetch(session).isEmpty)
    }
    await check("invalid phone numbers are rejected before requesting OTP; cancelled sync cannot save refreshed credentials") {
        let fixture = DrTrustFixture([])
        do { _ = try await DrTrustCloud(transport: { try await fixture.send($0) }).beginSignIn(phone: "not-a-phone"); throw DrTrustCheckFailure(message: "Expected phone error") }
        catch DrTrustError.phone { }
        let task = Task {
            try Task.checkCancellation()
            return try await DrTrustCloud(transport: { _ in try await Task.sleep(for: .seconds(60)); throw CancellationError() }).synchronize(session, now: now) { s in await fixture.save(s) }
        }
        task.cancel()
        do { _ = try await task.value; throw DrTrustCheckFailure(message: "Expected cancellation") } catch is CancellationError { }
        let savedEmpty = await fixture.saved.isEmpty, requestsEmpty = await fixture.requests.isEmpty
        try expect(savedEmpty && requestsEmpty)
    }
    await check("automatic Dr Trust sync catches up after wake and throttles repeated failures without blocking manual sync") {
        try expect(DrTrustSyncSchedule.isDue(lastSync: nil, lastAttempt: nil, now: now))
        try expect(!DrTrustSyncSchedule.isDue(lastSync: now.addingTimeInterval(-1800), lastAttempt: nil, now: now))
        try expect(!DrTrustSyncSchedule.isDue(lastSync: nil, lastAttempt: now.addingTimeInterval(-60), now: now))
        try expect(DrTrustSyncSchedule.isDue(lastSync: now.addingTimeInterval(-7200), lastAttempt: now.addingTimeInterval(-901), now: now))
    }
    return (count, failures)
}
