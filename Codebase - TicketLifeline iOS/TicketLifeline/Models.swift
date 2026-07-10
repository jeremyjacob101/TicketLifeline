import CryptoKit
import Foundation
import Combine

struct LocalAccount: Codable, Identifiable {
    let id: UUID
    let username: String
    let passwordHash: String
}

struct SavedCode: Codable, Identifiable, Hashable {
    let id: UUID
    let ownerID: UUID
    var label: String
    let payload: String
    let createdAt: Date
}

final class AppState: ObservableObject {
    @Published private(set) var accounts: [LocalAccount] = []
    @Published private(set) var codes: [SavedCode] = []
    @Published private(set) var signedInAccountID: UUID?

    var signedInAccount: LocalAccount? {
        accounts.first { $0.id == signedInAccountID }
    }

    var savedCodes: [SavedCode] {
        guard let signedInAccountID else { return [] }
        return codes
            .filter { $0.ownerID == signedInAccountID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    init() {
        load()
    }

    func createAccount(username: String, password: String) throws {
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedUsername.count >= 3 else {
            throw AppError.message("Choose a username with at least 3 characters.")
        }
        guard password.count >= 4 else {
            throw AppError.message("Choose a password with at least 4 characters.")
        }
        guard !accounts.contains(where: { $0.username.caseInsensitiveCompare(normalizedUsername) == .orderedSame }) else {
            throw AppError.message("That username is already in use on this device.")
        }

        let account = LocalAccount(id: UUID(), username: normalizedUsername, passwordHash: Self.hash(password))
        accounts.append(account)
        signedInAccountID = account.id
        save()
    }

    func signIn(username: String, password: String) throws {
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let account = accounts.first(where: {
            $0.username.caseInsensitiveCompare(normalizedUsername) == .orderedSame && $0.passwordHash == Self.hash(password)
        }) else {
            throw AppError.message("Incorrect username or password.")
        }
        signedInAccountID = account.id
        save()
    }

    func signOut() {
        signedInAccountID = nil
        save()
    }

    func saveCode(payload: String, label: String) {
        guard let signedInAccountID else { return }
        codes.append(SavedCode(
            id: UUID(), ownerID: signedInAccountID,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Scanned QR code" : label.trimmingCharacters(in: .whitespacesAndNewlines),
            payload: payload,
            createdAt: Date()
        ))
        save()
    }

    func deleteCode(_ code: SavedCode) {
        codes.removeAll { $0.id == code.id }
        save()
    }

    private static let storageKey = "ticketLifeline.localVault.v1"

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let vault = try? JSONDecoder().decode(LocalVault.self, from: data) else { return }
        accounts = vault.accounts
        codes = vault.codes
        signedInAccountID = vault.signedInAccountID
    }

    private func save() {
        let vault = LocalVault(accounts: accounts, codes: codes, signedInAccountID: signedInAccountID)
        guard let data = try? JSONEncoder().encode(vault) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func hash(_ password: String) -> String {
        SHA256.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private struct LocalVault: Codable {
    let accounts: [LocalAccount]
    let codes: [SavedCode]
    let signedInAccountID: UUID?
}

enum AppError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}
