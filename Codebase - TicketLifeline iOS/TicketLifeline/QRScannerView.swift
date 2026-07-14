import AVFoundation
import SwiftUI

struct ScanCodeView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var detectedCode: DetectedCode?
    @State private var label = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let detectedCode {
                    Group {
                        if detectedCode.isBarcode {
                            BarcodeImage(payload: detectedCode.payload)
                        } else {
                            QRCodeImage(payload: detectedCode.payload)
                        }
                    }
                    .frame(width: 220, height: 190)
                    Text(detectedCode.isBarcode ? "Barcode found" : "QR code found").font(.title2.bold())
                    Text(detectedCode.payload).lineLimit(3).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    TextField("Name this code (optional)", text: $label)
                        .textFieldStyle(.roundedBorder)
                    Button(detectedCode.isBarcode ? "Save Barcode" : "Save QR Code") {
                        save(detectedCode)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isLoading)
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                    Button("Scan another") { self.detectedCode = nil }
                } else {
                    QRScannerView { code in detectedCode = code }
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .overlay { RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.8), lineWidth: 3) }
                        .frame(height: 380)
                    Text("Point the camera at a code")
                        .font(.headline)
                    Text("QR codes and common ticket barcodes are supported.")
                        .font(.subheadline).foregroundStyle(.secondary)
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
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (DetectedCode) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        ScannerController(onCodeScanned: onCodeScanned)
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let onCodeScanned: (DetectedCode) -> Void
    private var hasReportedCode = false

    init(onCodeScanned: @escaping (DetectedCode) -> Void) {
        self.onCodeScanned = onCodeScanned
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        requestCameraAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layer.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer }.forEach { $0.frame = view.bounds }
    }

    private func requestCameraAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async { granted ? self?.configureSession() : self?.showCameraError() }
            }
        default: showCameraError()
        }
    }

    private func configureSession() {
        guard session.inputs.isEmpty,
              let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showCameraError(); return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { showCameraError(); return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        let supportedTypes: [AVMetadataObject.ObjectType] = [
            .qr, .aztec, .dataMatrix, .pdf417,
            .code39, .code93, .code128,
            .ean8, .ean13, .upce, .interleaved2of5, .itf14, .codabar,
        ]
        output.metadataObjectTypes = supportedTypes.filter(output.availableMetadataObjectTypes.contains)
        guard !output.metadataObjectTypes.isEmpty else { showCameraError(); return }
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    private func showCameraError() {
        let label = UILabel()
        label.text = "Camera access is required to scan codes. Enable it in Settings and try again."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasReportedCode,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        hasReportedCode = true
        session.stopRunning()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onCodeScanned(DetectedCode(
            payload: value,
            format: Self.normalizedFormat(for: object.type),
            codeType: object.type == .qr ? "qr" : "barcode"
        ))
    }

    private static func normalizedFormat(for type: AVMetadataObject.ObjectType) -> String {
        switch type {
        case .qr: "QR_CODE"
        case .aztec: "AZTEC"
        case .dataMatrix: "DATA_MATRIX"
        case .pdf417: "PDF417"
        case .code39, .code39Mod43: "CODE_39"
        case .code93: "CODE_93"
        case .code128: "CODE_128"
        case .ean8: "EAN_8"
        case .ean13: "EAN_13"
        case .upce: "UPC_E"
        case .interleaved2of5, .itf14: "ITF"
        case .codabar: "CODABAR"
        default: type.rawValue.uppercased()
        }
    }

    deinit { session.stopRunning() }
}
