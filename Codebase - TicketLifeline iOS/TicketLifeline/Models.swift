import Combine
import Foundation

struct SavedCode: Identifiable, Hashable, Decodable {
    let id: String
    let label: String
    let payload: String
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case label = "title"
        case payload = "encodedValue"
        case createdAt
    }

    init(id: String, label: String, payload: String, createdAt: Date) {
        self.id = id
        self.label = label
        self.payload = payload
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        payload = try container.decode(String.self, forKey: .payload)
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
        session = KeychainStore.load(ConvexSession.self, key: "ticketlifeline.convex.session")
        if session != nil {
            Task { try? await refreshCodes() }
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
        KeychainStore.remove(key: "ticketlifeline.convex.session")
    }

    func refreshCodes() async throws {
        let session = try await refreshedSession()
        isLoading = true
        defer { isLoading = false }
        savedCodes = try await client.query("passes:list", token: session.token)
    }

    func saveCode(payload: String, label: String) async throws {
        let session = try await refreshedSession()
        let title = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = CreatePass(
            title: title.isEmpty ? "Scanned QR code" : title,
            issuer: nil,
            codeType: "qr",
            format: "QR_CODE",
            encodedValue: payload,
            launchUrl: nil,
            visualMatrix: nil,
            visualSize: nil,
            eventDate: nil,
            notes: nil,
            color: "#4f46e5"
        )
        _ = try await client.mutation("passes:create", args: input, token: session.token, returning: String.self)
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
        KeychainStore.save(newSession, key: "ticketlifeline.convex.session")
        try await refreshCodes()
    }

    private func refreshedSession() async throws -> ConvexSession {
        guard let session else { throw AppError.message("Please sign in again.") }
        let tokens = try await client.refresh(refreshToken: session.refreshToken)
        let refreshed = ConvexSession(username: session.username, token: tokens.token, refreshToken: tokens.refreshToken)
        self.session = refreshed
        KeychainStore.save(refreshed, key: "ticketlifeline.convex.session")
        return refreshed
    }
}

private struct CreatePass: Encodable {
    let title: String
    let issuer: String?
    let codeType: String
    let format: String?
    let encodedValue: String
    let launchUrl: String?
    let visualMatrix: String?
    let visualSize: Int?
    let eventDate: String?
    let notes: String?
    let color: String?
}

enum AppError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}
