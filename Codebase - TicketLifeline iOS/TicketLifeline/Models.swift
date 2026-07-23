import Combine
import Foundation

enum AccountAuthenticationOutcome: Equatable {
    case signedIn
    case confirmationRequired(email: String)
}

enum AccountAuthValidation {
    static func normalizedEmail(_ value: String) throws -> String {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pattern = "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$"
        guard (3...254).contains(email.count),
              email.range(of: pattern, options: .regularExpression) != nil else {
            throw AppError.message("Enter a valid email address.")
        }
        return email
    }

    static func validatePassword(_ password: String) throws {
        guard password.count >= 8 else {
            throw AppError.message("Use a password with at least 8 characters.")
        }
        guard password.count <= 128 else {
            throw AppError.message("Use a password with no more than 128 characters.")
        }
    }

    static func confirmationCode(_ value: String) throws -> String {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            throw AppError.message("Enter the 6-digit confirmation code.")
        }
        return code
    }

    static func userFacingMessage(for error: Error) -> String {
        let message = error.localizedDescription
        let normalized = message.lowercased()
        if normalized.contains("invalid credentials") {
            return "Email or password is incorrect."
        }
        if normalized.contains("could not verify code") || normalized.contains("invalid code") {
            return "That confirmation code is incorrect or expired. Request a new code and try again."
        }
        if normalized.contains("already exists") {
            return "An account already exists for this email. Sign in instead."
        }
        if normalized.contains("too many") || normalized.contains("rate limit") {
            return "Too many attempts. Wait a few minutes and try again."
        }
        if normalized.contains("email delivery is not configured") ||
            normalized.contains("verification email could not be delivered") {
            return "We could not send the confirmation email. Please try again shortly."
        }
        if normalized.contains("network") || normalized.contains("offline") || normalized.contains("connection") {
            return "Could not connect to TicketLifeline. Check your connection and try again."
        }
        if normalized.contains("valid email") || normalized.contains("at least 8") ||
            normalized.contains("no more than 128") || normalized.contains("6-digit") {
            return message
        }
        return "We could not complete that request. Please try again."
    }
}

enum CodeOperationError {
    static func userFacingMessage(for error: Error) -> String {
        if let importError = error as? CodeImportError {
            return importError.localizedDescription
        }
        if let appError = error as? AppError {
            switch appError {
            case .network:
                return "Could not connect to TicketLifeline. Check your connection and try again."
            case .unauthorized:
                return "Your session expired. Please sign in again."
            case .message:
                break
            }
        }

        let message = error.localizedDescription
        let normalized = message.lowercased()
        if normalized.contains("matrix") {
            return "This code could not be saved safely. Scan it again or move closer and retry."
        }
        if normalized.contains("[request id") ||
            normalized.contains("server error") ||
            normalized.contains("uncaught error") {
            return "TicketLifeline could not save this code. Please try again."
        }
        return message
    }
}

struct SavedCode: Identifiable, Hashable, Decodable {
    let id: String
    let label: String
    let payload: String
    let codeType: String
    let format: String?
    let payloadEncoding: String
    let issuer: String?
    let launchURL: String?
    let eventDate: String?
    let notes: String?
    let color: String?
    let visualMatrix: String?
    let visualSize: Int?
    let visualWidth: Int?
    let visualHeight: Int?
    let createdAt: Date

    var isBarcode: Bool { codeType == "barcode" }
    var effectiveLaunchURL: String? {
        if let launchURL, let normalized = LaunchURLExtractor.extract(from: launchURL) { return normalized }
        return LaunchURLExtractor.extract(from: payload, encoding: payloadEncoding)
    }
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
        case payloadEncoding
        case issuer
        case launchURL = "launchUrl"
        case eventDate
        case notes
        case color
        case visualMatrix
        case visualSize
        case visualWidth
        case visualHeight
        case createdAt
    }

    init(id: String, label: String, payload: String, codeType: String, format: String?, payloadEncoding: String = "utf8", issuer: String?, launchURL: String?, eventDate: String?, notes: String?, color: String?, visualMatrix: String?, visualSize: Int?, visualWidth: Int? = nil, visualHeight: Int? = nil, createdAt: Date) {
        self.id = id
        self.label = label
        self.payload = payload
        self.codeType = codeType
        self.format = format
        self.payloadEncoding = payloadEncoding
        self.issuer = issuer
        self.launchURL = launchURL
        self.eventDate = eventDate
        self.notes = notes
        self.color = color
        self.visualMatrix = visualMatrix
        self.visualSize = visualSize
        self.visualWidth = visualWidth
        self.visualHeight = visualHeight
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        payload = try container.decode(String.self, forKey: .payload)
        codeType = try container.decode(String.self, forKey: .codeType)
        format = try container.decodeIfPresent(String.self, forKey: .format)
        payloadEncoding = try container.decodeIfPresent(String.self, forKey: .payloadEncoding) ?? "utf8"
        issuer = try container.decodeIfPresent(String.self, forKey: .issuer)
        launchURL = try container.decodeIfPresent(String.self, forKey: .launchURL)
        eventDate = try container.decodeIfPresent(String.self, forKey: .eventDate)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        visualMatrix = try container.decodeIfPresent(String.self, forKey: .visualMatrix)
        visualSize = try container.decodeIfPresent(Int.self, forKey: .visualSize)
        visualWidth = try container.decodeIfPresent(Int.self, forKey: .visualWidth)
        visualHeight = try container.decodeIfPresent(Int.self, forKey: .visualHeight)
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

    func createAccount(email: String, password: String) async throws -> AccountAuthenticationOutcome {
        try await authenticate(email: email, password: password, flow: "signUp")
    }

    func signIn(email: String, password: String) async throws -> AccountAuthenticationOutcome {
        try await authenticate(email: email, password: password, flow: "signIn")
    }

    func verifyEmail(_ email: String, code: String) async throws {
        let cleanEmail = try AccountAuthValidation.normalizedEmail(email)
        let cleanCode = try AccountAuthValidation.confirmationCode(code)
        isLoading = true
        defer { isLoading = false }
        let result = try await client.passwordAuthentication(
            email: cleanEmail,
            code: cleanCode,
            flow: "email-verification"
        )
        guard case .signedIn(let tokens) = result else {
            throw AppError.message("Could not verify code")
        }
        try await storeSession(email: cleanEmail, tokens: tokens)
    }

    func resendEmailConfirmation(to email: String, password: String) async throws {
        let cleanEmail = try AccountAuthValidation.normalizedEmail(email)
        try AccountAuthValidation.validatePassword(password)
        isLoading = true
        defer { isLoading = false }
        let result = try await client.passwordAuthentication(
            email: cleanEmail,
            password: password,
            flow: "signIn"
        )
        switch result {
        case .verificationRequired:
            return
        case .signedIn(let tokens):
            try await storeSession(email: cleanEmail, tokens: tokens)
        }
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

    func updateCode(_ id: String, title: String, issuer: String?, codeType: String, format: String?, encodedValue: String, payloadEncoding: String?, launchUrl: String?, visualMatrix: String?, visualSize: Int?, visualWidth: Int?, visualHeight: Int?, eventDate: String?, notes: String?, color: String?) async throws {
        try await withTrustedSession { session in
            try await self.client.updatePass(
                id, title: title, issuer: issuer, codeType: codeType,
                format: format, encodedValue: encodedValue, payloadEncoding: payloadEncoding, launchUrl: launchUrl,
                visualMatrix: visualMatrix, visualSize: visualSize, visualWidth: visualWidth, visualHeight: visualHeight,
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

    private func authenticate(email: String, password: String, flow: String) async throws -> AccountAuthenticationOutcome {
        let cleanEmail = try AccountAuthValidation.normalizedEmail(email)
        try AccountAuthValidation.validatePassword(password)
        isLoading = true
        defer { isLoading = false }
        let result = try await client.passwordAuthentication(
            email: cleanEmail,
            password: password,
            flow: flow
        )
        switch result {
        case .signedIn(let tokens):
            try await storeSession(email: cleanEmail, tokens: tokens)
            return .signedIn
        case .verificationRequired:
            return .confirmationRequired(email: cleanEmail)
        }
    }

    private func storeSession(email: String, tokens: ConvexTokens) async throws {
        let newSession = ConvexSession(email: email, token: tokens.token, refreshToken: tokens.refreshToken)
        session = newSession
        KeychainStore.save(newSession, key: KeychainStore.sessionKey)
        savedCodes = try await loadCodes()
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
