import Combine
import Foundation

struct SavedCode: Identifiable, Hashable, Decodable {
    let id: String
    let label: String
    let payload: String
    let codeType: String
    let format: String?
    let issuer: String?
    let launchURL: String?
    let eventDate: String?
    let notes: String?
    let color: String?
    let visualMatrix: String?
    let visualSize: Int?
    let createdAt: Date

    var isBarcode: Bool { codeType == "barcode" }
    var hasDateOverride: Bool {
        guard let eventDate else { return false }
        return !eventDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var preferredDate: Date {
        guard hasDateOverride,
              let eventDate,
              let date = Self.dateFromInput(eventDate) else {
            return createdAt
        }
        return date
    }
    var createdDateInput: String { Self.dateInputString(createdAt) }
    var preferredDateInput: String {
        if hasDateOverride, let eventDate { return eventDate }
        return createdDateInput
    }

    private static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func dateFromInput(_ value: String) -> Date? {
        dateFormatter().date(from: value)
    }

    private static func dateInputString(_ date: Date) -> String {
        dateFormatter().string(from: date)
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case label = "title"
        case payload = "encodedValue"
        case codeType
        case format
        case issuer
        case launchURL = "launchUrl"
        case eventDate
        case notes
        case color
        case visualMatrix
        case visualSize
        case createdAt
    }

    init(id: String, label: String, payload: String, codeType: String, format: String?, issuer: String?, launchURL: String?, eventDate: String?, notes: String?, color: String?, visualMatrix: String?, visualSize: Int?, createdAt: Date) {
        self.id = id
        self.label = label
        self.payload = payload
        self.codeType = codeType
        self.format = format
        self.issuer = issuer
        self.launchURL = launchURL
        self.eventDate = eventDate
        self.notes = notes
        self.color = color
        self.visualMatrix = visualMatrix
        self.visualSize = visualSize
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        payload = try container.decode(String.self, forKey: .payload)
        codeType = try container.decode(String.self, forKey: .codeType)
        format = try container.decodeIfPresent(String.self, forKey: .format)
        issuer = try container.decodeIfPresent(String.self, forKey: .issuer)
        launchURL = try container.decodeIfPresent(String.self, forKey: .launchURL)
        eventDate = try container.decodeIfPresent(String.self, forKey: .eventDate)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        visualMatrix = try container.decodeIfPresent(String.self, forKey: .visualMatrix)
        visualSize = try container.decodeIfPresent(Int.self, forKey: .visualSize)
        let milliseconds = try container.decode(Double.self, forKey: .createdAt)
        createdAt = Date(timeIntervalSince1970: milliseconds / 1_000)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var savedCodes: [SavedCode] = []
    @Published private(set) var isLoading = false
    @Published private(set) var session: ConvexSession?

    var isSignedIn: Bool { session != nil }

    private let client: ConvexClient

    init() {
        client = ConvexClient()
        session = KeychainStore.load(ConvexSession.self, key: KeychainStore.sessionKey)
        if session != nil {
            Task { try? await activateSession() }
        }
    }

    func createAccount(username: String, password: String) async throws {
        try await authenticate(username: username, password: password, flow: "signUp")
    }

    func signIn(username: String, password: String) async throws {
        try await authenticate(username: username, password: password, flow: "signIn")
    }

    func signOut() {
        session = nil
        savedCodes = []
        KeychainStore.remove(key: KeychainStore.sessionKey)
    }

    func reloadSharedSession() {
        if let stored = KeychainStore.load(ConvexSession.self, key: KeychainStore.sessionKey) {
            session = stored
        }
    }

    func activateSession() async throws {
        guard let currentSession = session else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            session = try await TrustedSessionManager.shared.refreshStoredSession(
                fallbackSession: currentSession
            )
        } catch where !error.isAuthorizationFailure {
            // Keep a potentially usable cached access token during temporary
            // network failures. The query below will retry if it has expired.
        } catch {
            session = nil
            savedCodes = []
            throw error
        }

        savedCodes = try await loadCodes()
    }

    func deleteAccount() async throws {
        isLoading = true
        defer { isLoading = false }
        let _: DeleteAccountResult = try await withTrustedSession { session in
            try await self.client.mutation(
                "users:deleteAccount",
                args: EmptyMutationArgs(),
                token: session.token,
                returning: DeleteAccountResult.self
            )
        }
        signOut()
    }

    func refreshCodes() async throws {
        isLoading = true
        defer { isLoading = false }
        savedCodes = try await loadCodes()
    }

    func deleteCode(_ id: String) async throws {
        try await withTrustedSession { session in
            try await self.client.deletePass(id, token: session.token)
        }
        try await refreshCodes()
    }

    func updateCode(_ id: String, title: String, issuer: String?, codeType: String, format: String?, encodedValue: String, launchUrl: String?, visualMatrix: String?, visualSize: Int?, eventDate: String?, notes: String?, color: String?) async throws {
        try await withTrustedSession { session in
            try await self.client.updatePass(
                id, title: title, issuer: issuer, codeType: codeType,
                format: format, encodedValue: encodedValue, launchUrl: launchUrl,
                visualMatrix: visualMatrix, visualSize: visualSize,
                eventDate: eventDate, notes: notes, color: color,
                token: session.token
            )
        }
        try await refreshCodes()
    }

    func saveCode(_ code: DetectedCode, label: String) async throws {
        let _: String = try await withTrustedSession { session in
            try await self.client.createPass(code: code, title: label, token: session.token)
        }
        try await refreshCodes()
    }

    private func authenticate(username: String, password: String, flow: String) async throws {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanUsername.count >= 3 else { throw AppError.message("Choose a username with at least 3 characters.") }
        guard password.count >= 4 else { throw AppError.message("Choose a password with at least 4 characters.") }

        isLoading = true
        defer { isLoading = false }
        let tokens = try await client.signIn(username: cleanUsername, password: password, flow: flow)
        let newSession = ConvexSession(username: cleanUsername, token: tokens.token, refreshToken: tokens.refreshToken)
        session = newSession
        KeychainStore.save(newSession, key: KeychainStore.sessionKey)
        try await refreshCodes()
    }

    private func loadCodes() async throws -> [SavedCode] {
        try await withTrustedSession { session in
            try await self.client.query("passes:list", token: session.token)
        }
    }

    private func withTrustedSession<Value: Sendable>(
        _ operation: @escaping @Sendable (ConvexSession) async throws -> Value
    ) async throws -> Value {
        do {
            let currentSession = session
            let value = try await TrustedSessionManager.shared.perform(
                fallbackSession: currentSession,
                operation
            )
            if let stored = await TrustedSessionManager.shared.storedSession() {
                session = stored
            }
            return value
        } catch {
            if error.isAuthorizationFailure,
               await TrustedSessionManager.shared.storedSession() == nil {
                session = nil
                savedCodes = []
            }
            throw error
        }
    }
}

private struct EmptyMutationArgs: Encodable {}

private struct DeleteAccountResult: Decodable {
    let deletedPasses: Int
}
