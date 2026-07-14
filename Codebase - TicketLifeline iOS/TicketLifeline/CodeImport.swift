import Foundation
import ImageIO
import Vision

struct DetectedCode: Identifiable, Hashable, Sendable {
    let payload: String
    let format: String
    let codeType: String

    var id: String { "\(format):\(payload)" }
    var isBarcode: Bool { codeType == "barcode" }

    var suggestedSharedTitle: String {
        if !isBarcode,
           let url = URL(string: payload),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           let host = url.host {
            let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return cleanHost.isEmpty ? "Shared QR Code" : cleanHost
        }
        return isBarcode ? "Shared Barcode" : "Shared QR Code"
    }

    var inferredLaunchURL: String? {
        guard !isBarcode,
              let url = URL(string: payload),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else { return nil }
        return url.absoluteString
    }
}

struct CreatePass: Encodable {
    let title: String
    let issuer: String?
    let codeType: String
    let format: String?
    let encodedValue: String
    let launchUrl: String?
    let visualMatrix: String?
    let visualSize: Int?
    let eventDate: String?
    let notes: String?
    let color: String?

    init(code: DetectedCode, title: String, color: String = "#4f46e5") {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = cleanTitle.isEmpty ? (code.isBarcode ? "Scanned Barcode" : "Scanned QR Code") : cleanTitle
        issuer = nil
        codeType = code.codeType
        format = code.format
        encodedValue = code.payload
        launchUrl = code.inferredLaunchURL
        visualMatrix = nil
        visualSize = nil
        eventDate = nil
        notes = nil
        self.color = color
    }
}

enum CodeImportError: LocalizedError {
    case invalidImage
    case noCodeFound

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "That image could not be opened. Try another screenshot."
        case .noCodeFound:
            "No QR code or barcode was found. Try a clearer or less-cropped image."
        }
    }
}

enum CodeImageDecoder {
    static func detect(in imageData: Data) async throws -> [DetectedCode] {
        try await Task.detached(priority: .userInitiated) {
            try detectSynchronously(in: imageData)
        }.value
    }

    private static func detectSynchronously(in imageData: Data) throws -> [DetectedCode] {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            throw CodeImportError.invalidImage
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 2_400
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 2_400
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(2_400, max(width, height)),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CodeImportError.invalidImage
        }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [
            .qr, .aztec, .dataMatrix, .pdf417,
            .code39, .code93, .code128,
            .ean8, .ean13, .upce, .itf14, .codabar,
        ]
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])

        let observations = (request.results ?? []).sorted {
            ($0.boundingBox.width * $0.boundingBox.height) > ($1.boundingBox.width * $1.boundingBox.height)
        }
        var seen = Set<String>()
        let detected = observations.compactMap { observation -> DetectedCode? in
            guard let payload = observation.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !payload.isEmpty else { return nil }
            let format = normalizedFormat(for: observation.symbology)
            let key = "\(format):\(payload)"
            guard seen.insert(key).inserted else { return nil }
            return DetectedCode(
                payload: payload,
                format: format,
                codeType: observation.symbology == .qr ? "qr" : "barcode"
            )
        }
        guard !detected.isEmpty else { throw CodeImportError.noCodeFound }
        return detected
    }

    private static func normalizedFormat(for symbology: VNBarcodeSymbology) -> String {
        switch symbology {
        case .qr: "QR_CODE"
        case .aztec: "AZTEC"
        case .dataMatrix: "DATA_MATRIX"
        case .pdf417: "PDF417"
        case .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum: "CODE_39"
        case .code93, .code93i: "CODE_93"
        case .code128: "CODE_128"
        case .ean8: "EAN_8"
        case .ean13: "EAN_13"
        case .upce: "UPC_E"
        case .itf14: "ITF"
        case .codabar: "CODABAR"
        default: symbology.rawValue.uppercased()
        }
    }
}
