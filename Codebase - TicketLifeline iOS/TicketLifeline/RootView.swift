import SwiftUI

struct RootView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var importCoordinator: ImportCoordinator

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.environment["TICKETLIFELINE_ART_PREVIEW"] == "1" {
                NavigationStack { CodeDetailView(code: .debugQRCode) }
            } else if !appState.isSignedIn {
                AuthView(appState: appState)
            } else {
                VaultView(appState: appState, importCoordinator: importCoordinator)
            }
            #else
            if !appState.isSignedIn {
                AuthView(appState: appState)
            } else {
                VaultView(appState: appState, importCoordinator: importCoordinator)
            }
            #endif
        }
        .tint(.indigo)
    }
}

#if DEBUG
private extension SavedCode {
    static let debugQRCode = SavedCode(
        id: "debug-qr",
        label: "Cherry Blossom Preview",
        payload: "https://ticketlifeline.app/preview/cherry-blossom",
        codeType: "qr",
        format: "QR_CODE",
        issuer: "TicketLifeline",
        launchURL: nil,
        eventDate: nil,
        notes: "Metal renderer visual QA",
        color: "#8f3f5a",
        visualMatrix: nil,
        visualSize: nil,
        createdAt: Date()
    )
}
#endif

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
                Link("Privacy Policy", destination: AppLinks.privacyPolicy)
                    .font(.footnote.weight(.semibold))
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
