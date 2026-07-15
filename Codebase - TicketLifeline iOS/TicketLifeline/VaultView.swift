import PhotosUI
import SwiftUI

struct VaultView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var appState: AppState
    @ObservedObject var importCoordinator: ImportCoordinator
    @State private var presentedSheet: SheetDestination?
    @State private var isPhotoPickerPresented = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var isReadingPhoto = false
    @State private var importError: String?

    private var sortedCodes: [SavedCode] {
        appState.savedCodes.sorted { $0.preferredDate > $1.preferredDate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if appState.isLoading && appState.savedCodes.isEmpty {
                    ProgressView("Loading your QR codes...")
                } else if appState.savedCodes.isEmpty {
                    ContentUnavailableView {
                        Label("No QR codes yet", systemImage: "qrcode.viewfinder")
                    } description: {
                        Text("Scan a code or choose a screenshot to keep it handy here.")
                    } actions: {
                        Button("Choose Photo") { isPhotoPickerPresented = true }
                            .buttonStyle(.borderedProminent)
                        Button("Scan Code") { presentedSheet = .scanner }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            ForEach(sortedCodes) { code in
                                NavigationLink(value: code) {
                                    CodeRow(code: code)
                                }
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    Task { try? await appState.deleteCode(sortedCodes[index].id) }
                                }
                            }
                        } header: {
                            Text("Go to ticketlifeline.link to access your codes anywhere!")
                                .padding(.bottom, 4)
                        }
                    }
                }
            }
            .navigationTitle("My Passes")
            .navigationDestination(for: SavedCode.self) { code in
                CodeDetailView(code: code, appState: appState)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            presentedSheet = .account
                        } label: {
                            Label("Account Settings", systemImage: "person.crop.circle")
                        }
                        Link(destination: AppLinks.privacyPolicy) {
                            Label("Privacy Policy", systemImage: "hand.raised")
                        }
                        Divider()
                        Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                            appState.signOut()
                        }
                    } label: {
                        Label("Account", systemImage: "person.crop.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isPhotoPickerPresented = true
                        } label: {
                            Label("Choose Photo", systemImage: "photo.badge.plus")
                        }
                        Button {
                            presentedSheet = .scanner
                        } label: {
                            Label("Scan Code", systemImage: "qrcode.viewfinder")
                        }
                    } label: {
                        Label("Add Code", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $presentedSheet) { destination in
                switch destination {
                case .scanner:
                    ScanCodeView(appState: appState)
                case .account:
                    AccountSettingsView(appState: appState)
                case .photo(let codes):
                    PhotoCodeImportView(appState: appState, codes: codes)
                }
            }
            .photosPicker(
                isPresented: $isPhotoPickerPresented,
                selection: $photoSelection,
                matching: .images,
                preferredItemEncoding: .current
            )
            .onChange(of: photoSelection) { _, selection in
                guard let selection else { return }
                Task { await importPhoto(selection) }
            }
            .onChange(of: importCoordinator.pendingAction) { _, _ in
                handlePendingImportAction()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                appState.reloadSharedSession()
                guard appState.isSignedIn else { return }
                Task { try? await appState.activateSession() }
            }
            .refreshable { try? await appState.refreshCodes() }
            .task {
                handlePendingImportAction()
            }
            .overlay {
                if isReadingPhoto {
                    ProgressView("Reading screenshot…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert("Couldn’t Import Code", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
                Button("Choose Another Photo") {
                    importError = nil
                    isPhotoPickerPresented = true
                }
            } message: {
                Text(importError ?? "Try another image.")
            }
        }
    }

    private func handlePendingImportAction() {
        guard appState.isSignedIn,
              let action = importCoordinator.consumePendingAction() else { return }
        switch action {
        case .upload:
            isPhotoPickerPresented = true
        case .scan:
            presentedSheet = .scanner
        }
    }

    private func importPhoto(_ selection: PhotosPickerItem) async {
        isReadingPhoto = true
        importError = nil
        defer {
            isReadingPhoto = false
            photoSelection = nil
        }
        do {
            guard let photo = try await selection.loadTransferable(type: ImportedPhoto.self) else {
                throw CodeImportError.invalidImage
            }
            let codes = try await CodeImageDecoder.detect(in: photo.data)
            presentedSheet = .photo(codes)
        } catch is CancellationError {
            return
        } catch {
            importError = error.localizedDescription
        }
    }

    private enum SheetDestination: Identifiable {
        case scanner
        case account
        case photo([DetectedCode])

        var id: String {
            switch self {
            case .scanner: "scanner"
            case .account: "account"
            case .photo: "photo"
            }
        }
    }
}

private struct AccountSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appState: AppState
    @State private var isConfirmingDeletion = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Username", value: appState.session?.username ?? "Signed in")
                    Link(destination: AppLinks.privacyPolicy) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }

                Section {
                    Button("Delete Account", systemImage: "trash", role: .destructive) {
                        isConfirmingDeletion = true
                    }
                    .disabled(isDeleting)
                } footer: {
                    Text("Permanently removes your account, every saved QR code and barcode, and all active web and iOS sessions.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Account Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(isDeleting)
                }
            }
            .confirmationDialog(
                "Permanently delete your account?",
                isPresented: $isConfirmingDeletion,
                titleVisibility: .visible
            ) {
                Button("Delete Account Permanently", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Keep Account", role: .cancel) {}
            } message: {
                Text("This deletes all of your TicketLifeline data and cannot be undone.")
            }
        }
        .interactiveDismissDisabled(isDeleting)
    }

    private func deleteAccount() async {
        errorMessage = nil
        isDeleting = true
        do {
            try await appState.deleteAccount()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isDeleting = false
        }
    }
}

private struct CodeRow: View {
    let code: SavedCode

    private static let rowFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yy - HH:mm"
        return f
    }()
    private static let overrideFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yy"
        return f
    }()

    var body: some View {
        HStack(spacing: 14) {
            CodeImage(code: code)
                .frame(width: 54, height: 54)
                .padding(5)
                .background(.white, in: RoundedRectangle(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).stroke(.quaternary) }
            VStack(alignment: .leading, spacing: 4) {
                Text(code.label).font(.headline)
                Text(
                    code.hasDateOverride
                        ? Self.overrideFormatter.string(from: code.preferredDate)
                        : Self.rowFormatter.string(from: code.createdAt)
                )
                    .lineLimit(1)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct CodeDetailView: View {
    let code: SavedCode
    @ObservedObject var appState: AppState
    @State private var displayMode: DisplayMode = .code
    @State private var isConfirmingDelete = false
    @State private var isEditing = false
    @State private var isDeleting = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Button {
                    displayMode = displayMode == .code ? .art : .code
                } label: {
                    CodePreview(code: code, isFlat: displayMode == .code)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .accessibilityLabel(displayMode == .code ? (code.isBarcode ? "Scannable barcode" : "Scannable QR code") : (code.isBarcode ? "Barcode skyline" : "Cherry tree"))
                .accessibilityHint("Double tap to switch between the scannable code and its art view")
                VStack(spacing: 8) {
                    Text(code.label).font(.title2.bold())
                    Group {
                        if code.hasDateOverride {
                            Text(code.preferredDate, format: .dateTime.month().day().year())
                        } else {
                            Text(code.createdAt, format: .dateTime.month().day().year().hour().minute())
                        }
                    }
                        .font(.footnote).foregroundStyle(.secondary)
                }
                PassInfoCard(code: code)
                VStack(alignment: .leading, spacing: 8) {
                    Text("SCANNED VALUE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(code.payload).textSelection(.enabled).font(.body.monospaced())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(code.isBarcode ? "Barcode" : "QR Code")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { isEditing = true } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) { isConfirmingDelete = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert("Delete this code?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await deleteCode() } }
        } message: {
            Text("This permanently removes \"\(code.label)\" and cannot be undone.")
        }
        .sheet(isPresented: $isEditing) {
            EditCodeView(code: code, appState: appState)
        }
    }

    private func deleteCode() async {
        isDeleting = true
        do {
            try await appState.deleteCode(code.id)
        } catch {
            isDeleting = false
        }
    }

    private enum DisplayMode: Hashable { case code, art }
}

private struct CodePreview: View {
    let code: SavedCode
    let isFlat: Bool

    var body: some View {
        Group {
            if code.isBarcode {
                BarcodeCityView(code: code, isFlat: isFlat)
            } else {
                QRTreeMetalView(code: code, isFlat: isFlat)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

private struct EditCodeView: View {
    let code: SavedCode
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var issuer: String
    @State private var notes: String
    @State private var eventDate: String
    @State private var launchURL: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(code: SavedCode, appState: AppState) {
        self.code = code
        self.appState = appState
        _title = State(initialValue: code.label)
        _issuer = State(initialValue: code.issuer ?? "")
        _notes = State(initialValue: code.notes ?? "")
        _eventDate = State(initialValue: code.preferredDateInput)
        _launchURL = State(initialValue: code.launchURL ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Issuer", text: $issuer)
                }
                Section {
                    TextField("Notes", text: $notes)
                    TextField("Pass date", text: $eventDate)
                    Text("Defaults to the created date. Change it only when this pass should use a different date.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("Scan URL", text: $launchURL)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .disabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanEventDate = eventDate.trimmingCharacters(in: .whitespacesAndNewlines)
            try await appState.updateCode(
                code.id,
                title: cleanTitle.isEmpty ? code.label : cleanTitle,
                issuer: issuer.trimmingCharacters(in: .whitespaces).isEmpty ? nil : issuer.trimmingCharacters(in: .whitespaces),
                codeType: code.codeType,
                format: code.format,
                encodedValue: code.payload,
                launchUrl: launchURL.trimmingCharacters(in: .whitespaces).isEmpty ? nil : launchURL.trimmingCharacters(in: .whitespaces),
                visualMatrix: code.visualMatrix,
                visualSize: code.visualSize,
                eventDate: cleanEventDate.isEmpty || cleanEventDate == code.createdDateInput ? nil : cleanEventDate,
                notes: notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes.trimmingCharacters(in: .whitespaces),
                color: code.color
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}

private struct CodeImage: View {
    let code: SavedCode

    var body: some View {
        if code.isBarcode {
            BarcodeImage(payload: code.payload)
        } else {
            QRCodeImage(payload: code.payload)
        }
    }
}

private struct PassInfoCard: View {
    let code: SavedCode

    var body: some View {
        VStack(spacing: 0) {
            InfoRow(label: "Type", value: code.isBarcode ? "Barcode" : "QR code")
            InfoRow(label: "Format", value: code.format ?? "Not available")
            InfoRow(label: "Issuer", value: code.issuer ?? "Not provided")
            InfoRow(label: "Pass date", value: code.hasDateOverride ? Self.overrideFormatter.string(from: code.preferredDate) : Self.rowFormatter.string(from: code.createdAt))
            InfoRow(label: "Created", value: Self.rowFormatter.string(from: code.createdAt))
            InfoRow(label: "Notes", value: code.notes ?? "No notes")
            if let launchURL = code.launchURL {
                InfoRow(label: "Scan link", value: launchURL)
            }
        }
        .padding(.horizontal)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    private static let rowFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yy - HH:mm"
        return f
    }()

    private static let overrideFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yy"
        return f
    }()
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider().opacity(label == "Scan link" ? 0 : 1) }
    }
}
