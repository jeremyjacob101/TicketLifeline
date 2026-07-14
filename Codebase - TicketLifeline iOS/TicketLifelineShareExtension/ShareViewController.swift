import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let rootView = ShareImportView(extensionContext: extensionContext)
        let host = UIHostingController(rootView: rootView)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }
}

private struct ShareImportView: View {
    @StateObject private var model: ShareImportModel

    init(extensionContext: NSExtensionContext?) {
        _model = StateObject(wrappedValue: ShareImportModel(extensionContext: extensionContext))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .loading:
                    statusView("Reading screenshot…", symbol: "viewfinder", showsProgress: true)
                case .choosing(let codes):
                    List(codes) { code in
                        Button { model.choose(code) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: code.isBarcode ? "barcode" : "qrcode")
                                    .font(.title2)
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(code.format.replacingOccurrences(of: "_", with: " "))
                                        .font(.headline)
                                    Text(code.payload)
                                        .font(.footnote.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                case .saving:
                    statusView("Saving to TicketLifeline…", symbol: "arrow.up.circle", showsProgress: true)
                case .saved:
                    statusView("Saved to TicketLifeline", symbol: "checkmark.circle.fill")
                case .signedOut:
                    VStack(spacing: 16) {
                        statusView(
                            "Open TicketLifeline and sign in, then share this screenshot again. The image was not retained.",
                            symbol: "person.crop.circle.badge.exclamationmark"
                        )
                        Button("Done") { model.cancel() }
                            .buttonStyle(.borderedProminent)
                    }
                case .failed(let message):
                    VStack(spacing: 16) {
                        statusView(message, symbol: "exclamationmark.triangle")
                        Button("Retry") { model.retry() }
                            .buttonStyle(.borderedProminent)
                        Button("Cancel", role: .cancel) { model.cancel() }
                    }
                }
            }
            .navigationTitle(model.state.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if model.state.canCancel {
                        Button("Cancel") { model.cancel() }
                    }
                }
            }
            .task { await model.start() }
        }
        .tint(.indigo)
    }

    private func statusView(_ text: String, symbol: String, showsProgress: Bool = false) -> some View {
        VStack(spacing: 18) {
            if showsProgress {
                ProgressView()
                    .controlSize(.large)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(symbol.hasPrefix("checkmark") ? .green : .indigo)
            }
            Text(text)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private final class ShareImportModel: ObservableObject {
    enum State {
        case loading
        case choosing([DetectedCode])
        case saving
        case saved
        case signedOut
        case failed(String)

        var title: String {
            switch self {
            case .choosing: "Choose a Code"
            default: "TicketLifeline"
            }
        }

        var canCancel: Bool {
            switch self {
            case .saved, .signedOut: false
            default: true
            }
        }
    }

    @Published private(set) var state: State = .loading
    private let extensionContext: NSExtensionContext?
    private var hasStarted = false
    private var imageData: Data?
    private var selectedCode: DetectedCode?

    init(extensionContext: NSExtensionContext?) {
        self.extensionContext = extensionContext
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await decodeSharedImage()
    }

    func choose(_ code: DetectedCode) {
        selectedCode = code
        Task { await save(code) }
    }

    func retry() {
        if let selectedCode {
            Task { await save(selectedCode) }
        } else {
            Task { await decodeSharedImage() }
        }
    }

    func cancel() {
        imageData = nil
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func decodeSharedImage() async {
        state = .loading
        do {
            let data = try await loadSharedImageData()
            imageData = data
            let codes = try await CodeImageDecoder.detect(in: data)
            imageData = nil
            if codes.count == 1, let code = codes.first {
                selectedCode = code
                await save(code)
            } else {
                state = .choosing(codes)
            }
        } catch {
            imageData = nil
            state = .failed(error.localizedDescription)
        }
    }

    private func save(_ code: DetectedCode) async {
        guard KeychainStore.load(ConvexSession.self, key: KeychainStore.sessionKey) != nil else {
            imageData = nil
            selectedCode = nil
            state = .signedOut
            return
        }
        state = .saving
        do {
            let _: String = try await TrustedSessionManager.shared.perform { session in
                try await ConvexClient().createPass(
                    code: code,
                    title: code.suggestedSharedTitle,
                    token: session.token
                )
            }
            selectedCode = nil
            state = .saved
            try? await Task.sleep(for: .milliseconds(650))
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            let message = error.localizedDescription
            if error.isAuthorizationFailure {
                imageData = nil
                selectedCode = nil
                state = .signedOut
            } else {
                state = .failed(message)
            }
        }
    }

    private func loadSharedImageData() async throws -> Data {
        guard let item = extensionContext?.inputItems.compactMap({ $0 as? NSExtensionItem }).first,
              let provider = item.attachments?.first(where: {
                  $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
              }) else {
            throw CodeImportError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CodeImportError.invalidImage)
                }
            }
        }
    }
}
