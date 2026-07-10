import Foundation
import Security

struct ConvexSession: Codable {
    let username: String
    let token: String
    let refreshToken: String
}

struct ConvexTokens: Decodable {
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

struct ConvexClient {
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

    private func request<Body: Encodable, Value: Decodable>(endpoint: String, body: Body, token: String?) async throws -> Value {
        var request = URLRequest(url: baseURL.appending(path: endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        guard let response = urlResponse as? HTTPURLResponse else { throw AppError.message("No response from Convex.") }
        let envelope = try JSONDecoder().decode(ConvexResponse<Value>.self, from: data)
        guard (200...299).contains(response.statusCode), envelope.status == "success", let value = envelope.value else {
            throw AppError.message(envelope.errorMessage ?? "Convex request failed.")
        }
        return value
    }
}

private struct FunctionCall<Args: Encodable>: Encodable {
    let path: String
    let args: Args
    let format = "json"
}

private struct EmptyArgs: Encodable {}

enum KeychainStore {
    static func save<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        remove(key: key)
        SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.ticketlifeline.app",
            kSecAttrAccount: key,
            kSecValueData: data,
        ] as CFDictionary, nil)
    }

    static func load<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.ticketlifeline.app",
            kSecAttrAccount: key,
            kSecReturnData: true,
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func remove(key: String) {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.ticketlifeline.app",
            kSecAttrAccount: key,
        ] as CFDictionary)
    }
}
