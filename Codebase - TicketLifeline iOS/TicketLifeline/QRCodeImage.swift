import SwiftUI
import UIKit

private struct CodeDisplayData: Hashable, Sendable {
    let payload: String
    let payloadEncoding: String
    let format: String
    let codeType: String
    let matrix: String?
    let width: Int?
    let height: Int?

    init(_ code: DetectedCode) {
        payload = code.payload
        payloadEncoding = code.payloadEncoding
        format = code.format
        codeType = code.codeType
        matrix = code.visualMatrix
        width = code.visualWidth
        height = code.visualHeight
    }

    init(_ code: SavedCode) {
        payload = code.payload
        payloadEncoding = code.payloadEncoding
        format = code.format ?? (code.isBarcode ? "CODE_128" : "QR_CODE")
        codeType = code.codeType
        matrix = code.visualMatrix
        width = code.visualWidth ?? code.visualSize
        height = code.visualHeight ?? code.visualSize
    }

    var detectedCode: DetectedCode {
        DetectedCode(
            payload: payload,
            format: format,
            codeType: codeType,
            payloadEncoding: payloadEncoding,
            visualMatrix: matrix,
            visualWidth: width,
            visualHeight: height
        )
    }
}

struct CodeSymbolView: View {
    private let data: CodeDisplayData
    private let requiresVerification: Bool
    @State private var image: UIImage?
    @State private var isUnavailable = false

    init(code: DetectedCode, requiresVerification: Bool = false) {
        data = CodeDisplayData(code)
        self.requiresVerification = requiresVerification
    }

    init(code: SavedCode, requiresVerification: Bool = true) {
        data = CodeDisplayData(code)
        self.requiresVerification = requiresVerification
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .accessibilityLabel(data.format.replacingOccurrences(of: "_", with: " "))
            } else if isUnavailable {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                    Text("Rescan required")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("This saved code must be rescanned before it can be displayed safely")
            } else {
                ProgressView("Verifying code…")
                    .font(.caption)
            }
        }
        .task(id: data) { await prepare() }
    }

    @MainActor
    private func prepare() async {
        image = nil
        isUnavailable = false
        let prepared = await Task.detached(priority: .userInitiated) { () -> DetectedCode? in
            let supplied = data.detectedCode
            if supplied.visualMatrix != nil {
                return !requiresVerification || CodeSymbolCodec.verifies(supplied) ? supplied : nil
            }
            guard data.payloadEncoding == "utf8" else { return nil }
            return CodeSymbolCodec.legacyRegeneratedCode(payload: data.payload, format: data.format)
        }.value

        guard let prepared,
              let bits = prepared.visualMatrix,
              let width = prepared.visualWidth,
              let height = prepared.visualHeight else {
            isUnavailable = true
            return
        }
        let matrix = BinaryCodeMatrix(bits: bits, width: width, height: height)
        guard let cgImage = CodeSymbolCodec.renderedImage(
            matrix,
            format: prepared.format
        ) else {
            isUnavailable = true
            return
        }
        image = UIImage(cgImage: cgImage)
    }
}

/// The preserved matrix drives the same flat-to-art Metal transition used on
/// saved passes. The flat endpoint stays an exact module/bar representation;
/// tapping reveals the tree or city without replacing the scanned data.
struct DetectedCodeArtPreview: View {
    let code: DetectedCode
    @State private var isFlat = true

    var body: some View {
        Button {
            isFlat.toggle()
        } label: {
            Group {
                if hasValidMatrix, isSquareMatrix {
                    QRTreeMetalView(code: code, isFlat: isFlat)
                } else if hasValidMatrix {
                    BarcodeCityView(code: code, isFlat: isFlat)
                } else {
                    CodeSymbolView(code: code)
                        .padding(20)
                        .background(.white)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFlat ? (code.isBarcode ? "Barcode" : "QR code") : (code.isBarcode ? "Barcode city" : "Cherry tree"))
        .accessibilityHint("Double tap to switch between the code and its artwork")
    }

    private var hasValidMatrix: Bool {
        guard let bits = code.visualMatrix,
              let width = code.visualWidth,
              let height = code.visualHeight else { return false }
        return BinaryCodeMatrix(bits: bits, width: width, height: height).isValid
    }

    private var isSquareMatrix: Bool {
        guard let width = code.visualWidth, let height = code.visualHeight else { return false }
        return width == height
    }
}

struct QRCodeImage: View {
    let payload: String

    var body: some View {
        CodeSymbolView(
            code: CodeSymbolCodec.legacyRegeneratedCode(payload: payload, format: "QR_CODE")
                ?? DetectedCode(payload: payload, format: "QR_CODE", codeType: "qr")
        )
    }
}

struct BarcodeImage: View {
    let payload: String

    var body: some View {
        CodeSymbolView(
            code: CodeSymbolCodec.legacyRegeneratedCode(payload: payload, format: "CODE_128")
                ?? DetectedCode(payload: payload, format: "CODE_128", codeType: "barcode")
        )
    }
}
