import Foundation
import Security

struct ConvexSession: Codable, Sendable {
    let username: String
    let token: String
    let refreshToken: String
}

struct ConvexTokens: Decodable, Sendable {
    let token: String
    let refreshToken: String
}

private struct SignInResponse: Decodable {
    let tokens: ConvexTokens?
}

private struct ConvexResponse<Value: Decodable>: Decodable {
    let status: String
    let value: Value?
    let errorMessage: String?
}

struct ConvexClient: Sendable {
    private let baseURL: URL

    init() {
        guard let rawURL = Bundle.main.object(forInfoDictionaryKey: "ConvexURL") as? String,
              let url = URL(string: rawURL),
              url.host?.hasSuffix(".convex.cloud") == true else {
            fatalError("Set the ConvexURL value in Info.plist to the shared Convex deployment URL.")
        }
        baseURL = url
    }

    func signIn(username: String, password: String, flow: String) async throws -> ConvexTokens {
        struct Args: Encodable {
            let provider = "password"
            let params: Params
            struct Params: Encodable { let username: String; let password: String; let flow: String }
        }
        let response: SignInResponse = try await request(
            endpoint: "api/action",
            body: FunctionCall(path: "auth:signIn", args: Args(params: .init(username: username, password: password, flow: flow))),
            token: nil
        )
        guard let tokens = response.tokens else { throw AppError.message("Could not create a session.") }
        return tokens
    }

    func refresh(refreshToken: String) async throws -> ConvexTokens {
        struct Args: Encodable { let refreshToken: String }
        let response: SignInResponse = try await request(
            endpoint: "api/action",
            body: FunctionCall(path: "auth:signIn", args: Args(refreshToken: refreshToken)),
            token: nil
        )
        guard let tokens = response.tokens else { throw AppError.message("Your session expired. Please sign in again.") }
        return tokens
    }

    func query<Value: Decodable>(_ path: String, token: String) async throws -> Value {
        try await request(endpoint: "api/query", body: FunctionCall(path: path, args: EmptyArgs()), token: token)
    }

    func mutation<Args: Encodable, Value: Decodable>(_ path: String, args: Args, token: String, returning: Value.Type) async throws -> Value {
        try await request(endpoint: "api/mutation", body: FunctionCall(path: path, args: args), token: token)
    }

    func deletePass(_ id: String, token: String) async throws {
        let _: Bool = try await mutation(
            "passes:remove",
            args: DeletePassArgs(id: id),
            token: token,
            returning: Bool.self
        )
    }

    func updatePass(_ id: String, title: String, issuer: String?, codeType: String, format: String?, encodedValue: String, launchUrl: String?, visualMatrix: String?, visualSize: Int?, eventDate: String?, notes: String?, color: String?, token: String) async throws {
        let _: Bool = try await mutation(
            "passes:update",
            args: UpdatePassArgs(
                id: id, title: title, issuer: issuer, codeType: codeType,
                format: format, encodedValue: encodedValue, launchUrl: launchUrl,
                visualMatrix: visualMatrix, visualSize: visualSize,
                eventDate: eventDate, notes: notes, color: color
            ),
            token: token,
            returning: Bool.self
        )
    }

    func createPass(code: DetectedCode, title: String, token: String) async throws -> String {
        try await mutation(
            "passes:create",
            args: CreatePass(code: code, title: title),
            token: token,
            returning: String.self
        )
    }

    private func request<Body: Encodable, Value: Decodable>(endpoint: String, body: Body, token: String?) async throws -> Value {
        var request = URLRequest(url: baseURL.appending(path: endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, urlResponse): (Data, URLResponse)
        do {
            (data, urlResponse) = try await URLSession.shared.data(for: request)
        } catch {
            throw AppError.network(error.localizedDescription)
        }
        guard let response = urlResponse as? HTTPURLResponse else { throw AppError.message("No response from Convex.") }
        let envelope: ConvexResponse<Value>
        do {
            envelope = try JSONDecoder().decode(ConvexResponse<Value>.self, from: data)
        } catch {
            throw AppError.message("Convex returned an unreadable response.")
        }
        guard (200...299).contains(response.statusCode), envelope.status == "success", let value = envelope.value else {
            let message = envelope.errorMessage ?? "Convex request failed."
            if response.statusCode == 401 || response.statusCode == 403 || Self.isAuthorizationMessage(message) {
                throw AppError.unauthorized(message)
            }
            throw AppError.message(message)
        }
        return value
    }

    private static func isAuthorizationMessage(_ message: String) -> Bool {
        let value = message.lowercased()
        return [
            "unauthenticated", "unauthorized", "not authenticated",
            "authentication required", "invalid refresh token", "session expired",
            "refresh token used outside", "missing refresh token",
        ].contains(where: value.contains)
    }
}

private struct DeletePassArgs: Encodable {
    let id: String
}

private struct UpdatePassArgs: Encodable {
    let id: String
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

private struct FunctionCall<Args: Encodable>: Encodable {
    let path: String
    let args: Args
    let format = "json"
}

private struct EmptyArgs: Encodable {}

enum KeychainStore {
    static let sessionKey = "ticketlifeline.convex.session"
    private static let service = "com.ticketlifeline.app"

    static func save<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        guard let sharedAccessGroup else {
            saveToLegacyGroup(data, key: key)
            return
        }
        let status = upsert(data, key: key, accessGroup: sharedAccessGroup)
        if status != errSecSuccess {
            saveToLegacyGroup(data, key: key)
        }
    }

    static func load<Value: Codable>(_ type: Value.Type, key: String) -> Value? {
        if let shared: Value = load(type, key: key, accessGroup: sharedAccessGroup) {
            return shared
        }
        guard let legacy: Value = load(type, key: key, accessGroup: nil) else { return nil }
        save(legacy, key: key)
        return legacy
    }

    static func remove(key: String) {
        removeFromSharedGroup(key: key)
        removeFromLegacyGroup(key: key)
    }

    private static var sharedAccessGroup: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String,
              !value.isEmpty,
              !value.contains("$(") else { return nil }
        return value
    }

    private static func load<Value: Decodable>(_ type: Value.Type, key: String, accessGroup: String?) -> Value? {
        var result: CFTypeRef?
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
        ]
        if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func saveToLegacyGroup(_ data: Data, key: String) {
        _ = upsert(data, key: key, accessGroup: nil)
    }

    private static func upsert(_ data: Data, key: String, accessGroup: String?) -> OSStatus {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }
        let values: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        guard updateStatus == errSecItemNotFound else { return updateStatus }
        query.merge(values) { _, new in new }
        return SecItemAdd(query as CFDictionary, nil)
    }

    private static func removeFromSharedGroup(key: String) {
        guard let sharedAccessGroup else { return }
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecAttrAccessGroup: sharedAccessGroup,
        ] as CFDictionary)
    }

    private static func removeFromLegacyGroup(key: String) {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ] as CFDictionary)
    }
}

enum AppError: LocalizedError, Sendable {
    case message(String)
    case network(String)
    case unauthorized(String)

    var isAuthorizationFailure: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .message(let text), .network(let text), .unauthorized(let text): text
        }
    }
}

extension Error {
    var isAuthorizationFailure: Bool {
        (self as? AppError)?.isAuthorizationFailure == true
    }
}

actor TrustedSessionManager {
    static let shared = TrustedSessionManager()

    private var refreshTask: Task<ConvexSession, Error>?

    func storedSession() -> ConvexSession? {
        KeychainStore.load(ConvexSession.self, key: KeychainStore.sessionKey)
    }

    func perform<Value: Sendable>(
        fallbackSession: ConvexSession? = nil,
        _ operation: @escaping @Sendable (ConvexSession) async throws -> Value
    ) async throws -> Value {
        guard let original = storedSession() ?? fallbackSession else {
            throw AppError.unauthorized("Please sign in again.")
        }

        do {
            return try await operation(original)
        } catch where error.isAuthorizationFailure {
            if let latest = storedSession(), latest.token != original.token {
                do {
                    return try await operation(latest)
                } catch where !error.isAuthorizationFailure {
                    throw error
                } catch {
                    // The newer access token is also expired; refresh it below.
                }
            }

            let refreshed = try await refreshSession(fallback: original)
            do {
                return try await operation(refreshed)
            } catch where error.isAuthorizationFailure {
                KeychainStore.remove(key: KeychainStore.sessionKey)
                throw error
            }
        }
    }

    private func refreshSession(fallback: ConvexSession) async throws -> ConvexSession {
        if let refreshTask { return try await refreshTask.value }

        let task = Task<ConvexSession, Error> {
            let source = KeychainStore.load(ConvexSession.self, key: KeychainStore.sessionKey) ?? fallback
            do {
                let tokens = try await ConvexClient().refresh(refreshToken: source.refreshToken)
                let refreshed = ConvexSession(
                    username: source.username,
                    token: tokens.token,
                    refreshToken: tokens.refreshToken
                )
                KeychainStore.save(refreshed, key: KeychainStore.sessionKey)
                return refreshed
            } catch where error.isAuthorizationFailure {
                KeychainStore.remove(key: KeychainStore.sessionKey)
                throw error
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
}
