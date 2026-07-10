import SwiftUI

struct RootView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            if !appState.isSignedIn {
                AuthView(appState: appState)
            } else {
                VaultView(appState: appState)
            }
        }
        .tint(.indigo)
    }
}

private struct AuthView: View {
    enum Mode { case signIn, createAccount }

    @ObservedObject var appState: AppState
    @State private var mode: Mode = .signIn
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "qrcode")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(.indigo)
                VStack(spacing: 8) {
                    Text("TicketLifeline")
                        .font(.largeTitle.bold())
                    Text(mode == .signIn ? "Sign in to your shared QR vault." : "Create a shared QR vault account.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 14) {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .padding()
                        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                    Button(mode == .signIn ? "Sign In" : "Create Account") { submit() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .disabled(appState.isLoading)
                }
                Button(mode == .signIn ? "Need an account? Create one" : "Already have an account? Sign in") {
                    mode = mode == .signIn ? .createAccount : .signIn
                    errorMessage = nil
                }
                .font(.subheadline)
                Spacer()
                Text("Your account and saved QR codes sync with the TicketLifeline web vault.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
        }
    }

    private func submit() {
        errorMessage = nil
        Task {
            do {
                if mode == .signIn {
                    try await appState.signIn(username: username, password: password)
                } else {
                    try await appState.createAccount(username: username, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
