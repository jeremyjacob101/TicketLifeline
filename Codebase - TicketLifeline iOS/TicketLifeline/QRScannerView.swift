import AVFoundation
import SwiftUI
import VisionKit

struct ScanCodeView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var detectedCode: DetectedCode?
    @State private var label = ""
    @State private var errorMessage: String?

    init(appState: AppState, previewCode: DetectedCode? = nil) {
        self.appState = appState
        _detectedCode = State(initialValue: previewCode)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let detectedCode {
                    DetectedCodeArtPreview(code: detectedCode)
                        .frame(width: 240, height: 220)
                    Text(detectedCode.isBarcode ? "Barcode found" : "QR code found")
                        .font(.title2.bold())
                    Text(detectedCode.payloadEncoding == "base64" ? "Binary payload" : detectedCode.payload)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if let rawURL = detectedCode.inferredLaunchURL, let url = URL(string: rawURL) {
                        Link(destination: url) {
                            Label("Open website", systemImage: "safari")
                        }
                    }
                    TextField("Name this code (optional)", text: $label)
                        .textFieldStyle(.roundedBorder)
                    Button(detectedCode.isBarcode ? "Save Barcode" : "Save QR Code") {
                        save(detectedCode)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isLoading)
                    Button("Scan another") {
                        errorMessage = nil
                        self.detectedCode = nil
                    }
                } else {
                    QRScannerView(
                        onCodeScanned: {
                            errorMessage = nil
                            detectedCode = $0
                        },
                        onError: { errorMessage = $0 }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay { RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.8), lineWidth: 3) }
                    .frame(height: 380)
                    Text("Hold the code inside the guide")
                        .font(.headline)
                    Text("The centered code captures after it stays steady briefly. Pinch to zoom for small codes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .navigationTitle("Scan Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func save(_ code: DetectedCode) {
        errorMessage = nil
        Task {
            do {
                try await appState.saveCode(code, label: label)
                dismiss()
            } catch {
                errorMessage = CodeOperationError.userFacingMessage(for: error)
            }
        }
    }
}

struct StableScanCandidate: Equatable {
    let id: UUID
    let payload: String
    let format: String
    let center: CGPoint
}

struct StableScanTracker {
    let minimumDuration: TimeInterval
    let minimumUpdates: Int
    let movementTolerance: CGFloat

    private(set) var candidate: StableScanCandidate?
    private(set) var firstSeen: TimeInterval = 0
    private(set) var updateCount = 0
    private var anchorCenter: CGPoint?

    init(minimumDuration: TimeInterval = 0.7, minimumUpdates: Int = 4, movementTolerance: CGFloat = 48) {
        self.minimumDuration = minimumDuration
        self.minimumUpdates = minimumUpdates
        self.movementTolerance = movementTolerance
    }

    mutating func observe(_ next: StableScanCandidate?, at time: TimeInterval) -> Bool {
        guard let next else {
            reset()
            return false
        }
        guard let current = candidate,
              let anchorCenter,
              current.id == next.id,
              current.payload == next.payload,
              current.format == next.format,
              hypot(anchorCenter.x - next.center.x, anchorCenter.y - next.center.y) <= movementTolerance else {
            candidate = next
            anchorCenter = next.center
            firstSeen = time
            updateCount = 1
            return false
        }
        candidate = next
        updateCount += 1
        return updateCount >= minimumUpdates && time - firstSeen >= minimumDuration
    }

    mutating func reset() {
        candidate = nil
        anchorCenter = nil
        firstSeen = 0
        updateCount = 0
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (DetectedCode) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        ScannerController(onCodeScanned: onCodeScanned, onError: onError)
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}
}

@MainActor
final class ScannerController: UIViewController, DataScannerViewControllerDelegate {
    private let onCodeScanned: (DetectedCode) -> Void
    private let onError: (String) -> Void
    private var scanner: DataScannerViewController?
    private var tracker = StableScanTracker()
    private var isFinalizing = false
    private var pendingBarcode: RecognizedItem.Barcode?
    private let guide = UIView()

    init(onCodeScanned: @escaping (DetectedCode) -> Void, onError: @escaping (String) -> Void) {
        self.onCodeScanned = onCodeScanned
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestCameraAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guide.frame = targetRect
    }

    private var targetRect: CGRect {
        view.bounds.insetBy(dx: view.bounds.width * 0.16, dy: view.bounds.height * 0.25)
    }

    private func requestCameraAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureScanner()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    granted ? self?.configureScanner() : self?.showCameraError()
                }
            }
        default:
            showCameraError()
        }
    }

    private func configureScanner() {
        guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else {
            showError("Live scanning is unavailable on this iPhone. Choose a screenshot instead.")
            return
        }
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: CodeSymbolCodec.supportedSymbologies)],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = self
        addChild(scanner)
        scanner.view.frame = view.bounds
        scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scanner.view)
        scanner.didMove(toParent: self)
        self.scanner = scanner

        guide.isUserInteractionEnabled = false
        guide.layer.cornerRadius = 18
        guide.layer.borderWidth = 3
        guide.layer.borderColor = UIColor.white.withAlphaComponent(0.92).cgColor
        guide.backgroundColor = .clear
        view.addSubview(guide)
        guide.frame = targetRect

        do {
            try scanner.startScanning()
        } catch {
            showError("The camera could not start scanning. Close this screen and try again.")
        }
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        evaluate(allItems)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        evaluate(allItems)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        evaluate(allItems)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
        showError("Live scanning became unavailable. Choose a screenshot or try again.")
    }

    private func evaluate(_ items: [RecognizedItem]) {
        guard !isFinalizing else { return }
        let candidates = items.compactMap { item -> (RecognizedItem.Barcode, CGPoint)? in
            guard case .barcode(let barcode) = item,
                  let payload = stablePayload(for: barcode),
                  !payload.isEmpty else { return nil }
            let points = [barcode.bounds.topLeft, barcode.bounds.topRight, barcode.bounds.bottomRight, barcode.bounds.bottomLeft]
            let center = CGPoint(
                x: points.reduce(0) { $0 + $1.x } / 4,
                y: points.reduce(0) { $0 + $1.y } / 4
            )
            guard targetRect.contains(center) else { return nil }
            return (barcode, center)
        }
        let viewCenter = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        guard let selected = candidates.min(by: {
            hypot($0.1.x - viewCenter.x, $0.1.y - viewCenter.y) < hypot($1.1.x - viewCenter.x, $1.1.y - viewCenter.y)
        }) else {
            _ = tracker.observe(nil, at: CACurrentMediaTime())
            return
        }
        let observation = selected.0.observation
        let payload = stablePayload(for: selected.0) ?? ""
        let stable = StableScanCandidate(
            id: selected.0.id,
            payload: payload,
            format: CodeSymbolCodec.normalizedFormat(for: observation.symbology),
            center: selected.1
        )
        if tracker.observe(stable, at: CACurrentMediaTime()) {
            isFinalizing = true
            guide.layer.borderColor = UIColor.systemGreen.cgColor
            pendingBarcode = selected.0
            Task { [weak self] in await self?.finalizePending() }
        }
    }

    private func finalizePending() async {
        guard let pendingBarcode, let scanner else { return }
        await finalize(pendingBarcode, using: scanner)
    }

    private func finalize(_ barcode: RecognizedItem.Barcode, using scanner: DataScannerViewController) async {
        if let code = await Task.detached(priority: .userInitiated, operation: {
            CodeSymbolCodec.detectedCode(from: barcode.observation, sourceImage: nil)
        }).value {
            finish(with: code)
            return
        }

        do {
            let photo = try await scanner.capturePhoto()
            guard let data = photo.jpegData(compressionQuality: 0.96) else { throw CodeImportError.invalidImage }
            let codes = try await CodeImageDecoder.detect(in: data)
            let expectedFormat = CodeSymbolCodec.normalizedFormat(for: barcode.observation.symbology)
            let expectedPayload = stablePayload(for: barcode)
            guard let code = codes.first(where: { $0.format == expectedFormat && $0.payload == expectedPayload }) else {
                throw CodeImportError.verificationFailed
            }
            finish(with: code)
        } catch {
            tracker.reset()
            isFinalizing = false
            guide.layer.borderColor = UIColor.white.withAlphaComponent(0.92).cgColor
            onError(CodeImportError.verificationFailed.localizedDescription)
        }
    }

    private func finish(with code: DetectedCode) {
        scanner?.stopScanning()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onCodeScanned(code)
    }

    private func stablePayload(for barcode: RecognizedItem.Barcode) -> String? {
        if let value = barcode.payloadStringValue, !value.isEmpty { return value }
        guard let data = barcode.observation.payloadData, !data.isEmpty else { return nil }
        return data.base64EncodedString()
    }

    private func showCameraError() {
        showError("Camera access is required to scan codes. Enable it in Settings and try again.")
    }

    private func showError(_ message: String) {
        onError(message)
        scanner?.stopScanning()
        scanner?.view.removeFromSuperview()
        scanner?.removeFromParent()
        scanner = nil

        let label = UILabel()
        label.text = message
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
