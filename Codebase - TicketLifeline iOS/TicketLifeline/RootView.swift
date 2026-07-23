import SwiftUI

#if DEBUG
private enum DebugPreview {
    static var authMode: String? {
        if let value = ProcessInfo.processInfo.environment["TICKETLIFELINE_AUTH_PREVIEW"] {
            return value
        }
        if let value = UserDefaults.standard.string(forKey: "TICKETLIFELINE_AUTH_PREVIEW") {
            return value
        }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-TICKETLIFELINE_AUTH_PREVIEW"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
#endif

struct RootView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var importCoordinator: ImportCoordinator

    var body: some View {
        Group {
            #if DEBUG
            if DebugPreview.authMode != nil {
                AuthView(appState: appState)
            } else if ProcessInfo.processInfo.environment["TICKETLIFELINE_ART_PREVIEW"] == "scan",
               let detected = DetectedCode.debugQRCode {
                ScanCodeView(appState: appState, previewCode: detected)
            } else if ProcessInfo.processInfo.environment["TICKETLIFELINE_ART_PREVIEW"] == "scan-barcode",
                      let detected = DetectedCode.debugBarcode {
                ScanCodeView(appState: appState, previewCode: detected)
            } else if let previewCode {
                NavigationStack { CodeDetailView(code: previewCode, appState: appState) }
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

    #if DEBUG
    private var previewCode: SavedCode? {
        switch ProcessInfo.processInfo.environment["TICKETLIFELINE_ART_PREVIEW"] {
        case "1", "qr": .debugQRCode
        case "barcode": .debugBarcode
        default: nil
        }
    }
    #endif
}

#if DEBUG
private extension DetectedCode {
    static let debugQRCode = CodeSymbolCodec.debugGeneratedCode(
        payload: "https://ticketlifeline.app/preview/cherry-blossom",
        format: "QR_CODE"
    )

    static let debugBarcode = CodeSymbolCodec.debugGeneratedCode(
        payload: "123456789012",
        format: "CODE_128"
    )
}

private extension SavedCode {
    static let debugQRCode: SavedCode = {
        let payload = "https://ticketlifeline.app/preview/cherry-blossom"
        let generated = CodeSymbolCodec.debugGeneratedCode(payload: payload, format: "QR_CODE")
        return SavedCode(
            id: "debug-qr",
            label: "Cherry Blossom Preview",
            payload: payload,
            codeType: "qr",
            format: "QR_CODE",
            issuer: "TicketLifeline",
            launchURL: nil,
            eventDate: nil,
            notes: "Metal renderer visual QA",
            color: "#8f3f5a",
            visualMatrix: generated?.visualMatrix,
            visualSize: generated?.visualSize,
            visualWidth: generated?.visualWidth,
            visualHeight: generated?.visualHeight,
            createdAt: Date()
        )
    }()

    static let debugBarcode: SavedCode = {
        let payload = "123456789012"
        let generated = CodeSymbolCodec.debugGeneratedCode(payload: payload, format: "CODE_128")
        return SavedCode(
            id: "debug-barcode",
            label: "Cityscape Preview",
            payload: payload,
            codeType: "barcode",
            format: "CODE_128",
            issuer: "TicketLifeline",
            launchURL: nil,
            eventDate: nil,
            notes: "Metal renderer visual QA",
            color: "#0f766e",
            visualMatrix: generated?.visualMatrix,
            visualSize: nil,
            visualWidth: generated?.visualWidth,
            visualHeight: generated?.visualHeight,
            createdAt: Date()
        )
    }()
}
#endif

private struct AuthView: View {
    enum Mode { case signIn, createAccount, confirmEmail }

    @ObservedObject var appState: AppState
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var confirmationCode = ""
    @State private var errorMessage: String?
    @State private var noticeMessage: String?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer()
                        Image("AuthLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .accessibilityHidden(true)
                        VStack(spacing: 8) {
                            Text("TicketLifeline")
                                .font(.largeTitle.bold())
                            Text(subtitle)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        VStack(spacing: 14) {
                            TextField("Email", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .disabled(mode == .confirmEmail)
                                .padding()
                                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
                            if mode == .confirmEmail {
                                TextField("6-digit confirmation code", text: confirmationCodeBinding)
                                    .textContentType(.oneTimeCode)
                                    .keyboardType(.numberPad)
                                    .padding()
                                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
                            } else {
                                SecureField("Password", text: $password)
                                    .textContentType(mode == .signIn ? .password : .newPassword)
                                    .padding()
                                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
                                if mode == .createAccount {
                                    SecureField("Confirm password", text: $confirmPassword)
                                        .textContentType(.newPassword)
                                        .padding()
                                        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
                                    Text("Use 8–128 characters.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            if let noticeMessage {
                                Text(noticeMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.green)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Button(primaryButtonTitle) { submit() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .frame(maxWidth: .infinity)
                                .disabled(appState.isLoading)
                        }
                        if mode == .confirmEmail {
                            VStack(spacing: 12) {
                                Button("Send a new code") { resendCode() }
                                    .disabled(appState.isLoading)
                                Button("Back to sign in") { changeMode(to: .signIn) }
                                    .disabled(appState.isLoading)
                            }
                            .font(.subheadline)
                        } else {
                            Button(mode == .signIn ? "Need an account? Create one" : "Already have an account? Sign in") {
                                changeMode(to: mode == .signIn ? .createAccount : .signIn)
                            }
                            .font(.subheadline)
                        }
                        Spacer()
                        Text("After one email confirmation, use the same email and password on iOS or any web browser.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Link("Privacy Policy", destination: AppLinks.privacyPolicy)
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(28)
                    .frame(minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            #if DEBUG
            .onAppear {
                switch DebugPreview.authMode {
                case "signUp":
                    mode = .createAccount
                case "verify":
                    mode = .confirmEmail
                    email = "person@example.com"
                    noticeMessage = "We sent a 6-digit confirmation code to person@example.com."
                default:
                    break
                }
            }
            #endif
        }
    }

    private var subtitle: String {
        switch mode {
        case .signIn: "Sign in with email and password from any device."
        case .createAccount: "Create a shared QR vault and confirm your email once."
        case .confirmEmail: "Enter the code we emailed you. Future sign-ins will not require a code."
        }
    }

    private var primaryButtonTitle: String {
        switch mode {
        case .signIn: "Sign In"
        case .createAccount: "Create Account"
        case .confirmEmail: "Confirm and Sign In"
        }
    }

    private var confirmationCodeBinding: Binding<String> {
        Binding(
            get: { confirmationCode },
            set: { confirmationCode = String($0.filter(\.isNumber).prefix(6)) }
        )
    }

    private func submit() {
        errorMessage = nil
        noticeMessage = nil
        Task {
            do {
                switch mode {
                case .signIn:
                    let result = try await appState.signIn(email: email, password: password)
                    handle(result)
                case .createAccount:
                    guard password == confirmPassword else {
                        throw AppError.message("Passwords do not match.")
                    }
                    let result = try await appState.createAccount(email: email, password: password)
                    handle(result)
                case .confirmEmail:
                    try await appState.verifyEmail(email, code: confirmationCode)
                }
            } catch {
                if error.localizedDescription == "Passwords do not match." {
                    errorMessage = error.localizedDescription
                } else {
                    errorMessage = AccountAuthValidation.userFacingMessage(for: error)
                }
            }
        }
    }

    private func handle(_ result: AccountAuthenticationOutcome) {
        guard case .confirmationRequired(let cleanEmail) = result else { return }
        email = cleanEmail
        confirmationCode = ""
        mode = .confirmEmail
        noticeMessage = "We sent a 6-digit confirmation code to \(cleanEmail)."
    }

    private func resendCode() {
        errorMessage = nil
        noticeMessage = nil
        Task {
            do {
                try await appState.resendEmailConfirmation(to: email, password: password)
                noticeMessage = "A new confirmation code was sent to \(email)."
            } catch {
                errorMessage = AccountAuthValidation.userFacingMessage(for: error)
            }
        }
    }

    private func changeMode(to newMode: Mode) {
        mode = newMode
        password = ""
        confirmPassword = ""
        confirmationCode = ""
        errorMessage = nil
        noticeMessage = nil
    }
}
