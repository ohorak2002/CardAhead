import Foundation
import Observation
import Security
import CardKit

@Observable
final class ImpactCloudStore {
    static let shared = ImpactCloudStore()
    private(set) var state = ImpactSharingState()
    private(set) var isOwner = false
    private(set) var isBusy = false
    private(set) var status = "Sharing is off. Local Impact works without an account."
    private(set) var session: CloudSession?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private let fileURL: URL
    private var baseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "ImpactServiceURL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
    private var publicKey: String { Bundle.main.object(forInfoDictionaryKey: "ImpactPublicKey") as? String ?? "" }
    var configured: Bool { baseURL != nil && !publicKey.isEmpty && !publicKey.contains("$(") }
    var signedIn: Bool { session != nil }

    private init() {
        let directory = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? .temporaryDirectory
        fileURL = directory.appendingPathComponent("impact-sharing.json")
        if let data = try? Data(contentsOf: fileURL), let loaded = try? JSONDecoder().decode(ImpactSharingState.self, from: data) { state = loaded }
        session = CloudSessionKeychain.read()
    }
    func signIn(email: String, password: String, create: Bool) async {
        guard !isBusy else { return }; isBusy = true; defer { isBusy = false }
        do {
            let data = try await request(path: create ? "auth/v1/signup" : "auth/v1/token?grant_type=password", body: ["email": email, "password": password], authenticated: false)
            if create { status = "Check your email to verify your account, then sign in. Sharing stays off."; return }
            let next = try JSONDecoder().decode(CloudSession.self, from: data)
            guard state.accountID == nil || state.accountID == next.user.id || (!state.enabled && !state.needsRevocation && !state.needsDeletion && state.pending.isEmpty) else {
                status = "Sign in to the previous account to finish its pending privacy request first."; return
            }
            session = next; CloudSessionKeychain.save(next); state.accountID = next.user.id; save()
            await refreshOwner(); flush()
            status = "Signed in. Impact sharing is \(state.enabled ? "on" : "off")."
        } catch { status = "Sign-in failed. Check your credentials, email verification and connection." }
    }
    func signOut() {
        guard !state.enabled && !state.needsRevocation && !state.needsDeletion && !isBusy else {
            status = "Turn off sharing and finish pending privacy requests before signing out."; return
        }
        session = nil; isOwner = false; CloudSessionKeychain.clear(); status = "Signed out."
    }
    func setSharing(_ enabled: Bool) {
        if enabled {
            guard configured, signedIn, !state.needsDeletion, !state.needsRevocation else { status = "Sign in and finish pending privacy requests first."; return }
            state.enable()
        } else { state.disable() }
        save(); flush(force: true)
    }
    func deleteShared() { state.disable(deletePreviouslyShared: true); save(); flush(force: true) }
    func receive(_ event: ImpactEvent) {
        guard let record = SharedImpactRecord(event: event) else { return }
        state.enqueue(record, createdAt: event.date); save(); flush()
    }
    func receive(_ redemption: OfferRedemption, productID: String?, category: SpendingCategory?) {
        state.enqueue(SharedImpactRecord(redemption: redemption, productID: productID, category: category), createdAt: redemption.date)
        save(); flush()
    }
    func shareHistory(_ events: [ImpactEvent]) {
        guard state.enabled else { return }
        // Called only by the explicitly labeled historical-sharing confirmation.
        for event in events { if let record = SharedImpactRecord(event: event) { state.enqueue(record, createdAt: Date()) } }
        save(); flush()
    }
    func refreshOwner() async {
        isOwner = false
        guard signedIn else { return }
        do {
            try await refreshSessionIfNeeded()
            let data = try await rpc("cardahead_is_owner", body: [:])
            isOwner = (try? JSONDecoder().decode(Bool.self, from: data)) == true
        } catch { isOwner = false }
    }
    /// Single serialized worker. Revocation/deletion follows any in-flight upload;
    /// server-side row locking makes a late upload unable to resurrect deleted data.
    func flush(force: Bool = false) {
        guard worker == nil, configured, signedIn else { return }
        guard force || state.retryAfter.map({ $0 <= Date() }) ?? true else { scheduleRetry(); return }
        worker = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.worker = nil }
            do {
                try await self.refreshSessionIfNeeded()
                while self.state.enabled || self.state.needsRevocation || self.state.needsDeletion {
                    let epoch = self.state.epoch
                    if self.state.needsDeletion {
                        _ = try await self.rpc("cardahead_delete_shared", body: [:])
                        if self.state.epoch == epoch { self.state.acknowledgePrivacyChange() }
                        self.status = "Previously shared records deleted. Sharing is off."
                    } else if self.state.needsRevocation {
                        _ = try await self.rpc("cardahead_set_sharing", body: ["enabled": false, "epoch": epoch.uuidString])
                        if self.state.epoch == epoch { self.state.acknowledgePrivacyChange() }
                        self.status = "Sharing is off. Previously shared records remain until you delete them."
                    } else {
                        _ = try await self.rpc("cardahead_set_sharing", body: ["enabled": true, "epoch": epoch.uuidString])
                        guard self.state.enabled, self.state.epoch == epoch else { continue }
                        let batch = Array(self.state.pending.prefix(100))
                        if batch.isEmpty { self.status = "Sharing is on. No pending uploads."; break }
                        let records = try JSONSerialization.jsonObject(with: JSONEncoder().encode(batch))
                        _ = try await self.rpc("cardahead_upload", body: ["epoch": epoch.uuidString, "records": records])
                        self.state.acknowledge(Set(batch.map(\.id)), epoch: epoch)
                        self.status = "Shared \(batch.count) reports. Estimates and user reports are not verified outcomes."
                    }
                    self.save()
                }
            } catch {
                self.state.failed(); self.save()
                self.status = self.state.needsDeletion ? "Deletion pending. Reconnect and stay signed in to finish." : "Delivery pending. CardAhead will retry with the same record IDs when connected."
                self.scheduleRetry()
            }
        }
    }
    private func scheduleRetry() {
        retryTask?.cancel()
        let delay = max(1, state.retryAfter?.timeIntervalSinceNow ?? 10)
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }; self?.flush()
        }
    }
    func dashboard(from: Date, to: Date) async throws -> OwnerDashboard {
        try await refreshSessionIfNeeded()
        // Authorization happens on the server every time, regardless of cached UI state.
        let data = try await rpc("cardahead_dashboard", body: ["from_day": SharedImpactRecord.day(from), "to_day": SharedImpactRecord.day(to)])
        return try JSONDecoder().decode(OwnerDashboard.self, from: data)
    }
    private func refreshSessionIfNeeded() async throws {
        guard let session else { throw CloudError.unavailable }
        guard session.expires_at < Date().timeIntervalSince1970 + 60 else { return }
        let data = try await request(path: "auth/v1/token?grant_type=refresh_token", body: ["refresh_token": session.refresh_token], authenticated: false)
        let next = try JSONDecoder().decode(CloudSession.self, from: data)
        guard next.user.id == session.user.id else { throw CloudError.unavailable }
        self.session = next; CloudSessionKeychain.save(next)
    }
    private func rpc(_ name: String, body: [String: Any]) async throws -> Data {
        try await request(path: "rest/v1/rpc/" + name, body: body, authenticated: true)
    }
    private func request(path: String, body: [String: Any], authenticated: Bool) async throws -> Data {
        guard configured, let baseURL, let url = URL(string: path, relativeTo: baseURL.appendingPathComponent("/")) else { throw CloudError.unavailable }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue(publicKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            guard let session else { throw CloudError.unavailable }
            request.setValue("Bearer " + session.access_token, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw CloudError.unavailable }
        return data
    }
    private func save() {
        do { try JSONEncoder().encode(state).write(to: fileURL, options: [.atomic, .completeFileProtection]) }
        catch { status = "Could not save sharing preferences. Sharing stopped."; state.disable(); worker?.cancel() }
    }
    private enum CloudError: Error { case unavailable }
}

struct CloudSession: Codable {
    struct User: Codable { var id: UUID }
    var access_token: String
    var refresh_token: String
    var expires_at: Double
    var user: User
}
private enum CloudSessionKeychain {
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "CardAhead.Impact", kSecAttrAccount as String: "session"] }
    static func read() -> CloudSession? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(CloudSession.self, from: data)
    }
    static func save(_ session: CloudSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        clear(); var q = query; q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}

struct OwnerDashboard: Decodable {
    var participating_users: Int
    var reporting_users: Int
    var acted_on: Int
    var purchase_cents: Int?
    var estimated_cents: Int?
    var incremental_cents: Int?
    var received_cents: Int?
    var known_baselines: Int
    var priced_recommendations: Int
    var breakdowns: [Breakdown]
    struct Breakdown: Decodable, Identifiable {
        var dimension: String; var label: String; var acted: Int
        var purchases: Int?; var estimated: Int?; var incremental: Int?; var received: Int?
        var id: String { dimension + ":" + label }
    }
}
