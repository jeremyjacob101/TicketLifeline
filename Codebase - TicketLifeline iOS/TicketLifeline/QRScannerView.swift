import AVFoundation
import SwiftUI

struct ScanCodeView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var scannedValue: String?
    @State private var label = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let scannedValue {
                    QRCodeImage(payload: scannedValue).frame(width: 190, height: 190)
                    Text("QR code found").font(.title2.bold())
                    Text(scannedValue).lineLimit(3).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    TextField("Name this code (optional)", text: $label)
                        .textFieldStyle(.roundedBorder)
                    Button("Save QR Code") {
                        appState.saveCode(payload: scannedValue, label: label)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Scan another") { self.scannedValue = nil }
                } else {
                    QRScannerView { value in scannedValue = value }
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .overlay { RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.8), lineWidth: 3) }
                        .frame(height: 380)
                    Text("Point the camera at a QR code")
                        .font(.headline)
                    Text("Only QR codes are scanned in this first version.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        ScannerController(onCodeScanned: onCodeScanned)
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let onCodeScanned: (String) -> Void
    private var hasReportedCode = false

    init(onCodeScanned: @escaping (String) -> Void) {
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
        guard output.availableMetadataObjectTypes.contains(.qr) else { showCameraError(); return }
        output.metadataObjectTypes = [.qr]
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    private func showCameraError() {
        let label = UILabel()
        label.text = "Camera access is required to scan QR codes. Enable it in Settings and try again."
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
        onCodeScanned(value)
    }

    deinit { session.stopRunning() }
}
