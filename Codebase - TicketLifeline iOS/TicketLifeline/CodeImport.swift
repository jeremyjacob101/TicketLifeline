import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import Vision

struct DetectedCode: Identifiable, Hashable, Sendable {
    let payload: String
    let format: String
    let codeType: String
    let payloadEncoding: String
    let visualMatrix: String?
    let visualWidth: Int?
    let visualHeight: Int?

    init(
        payload: String,
        format: String,
        codeType: String,
        payloadEncoding: String = "utf8",
        visualMatrix: String? = nil,
        visualWidth: Int? = nil,
        visualHeight: Int? = nil
    ) {
        self.payload = payload
        self.format = format
        self.codeType = codeType
        self.payloadEncoding = payloadEncoding
        self.visualMatrix = visualMatrix
        self.visualWidth = visualWidth
        self.visualHeight = visualHeight
    }

    var id: String { "\(format):\(payloadEncoding):\(payload)" }
    var isBarcode: Bool { codeType == "barcode" }
    var visualSize: Int? {
        guard format == "QR_CODE",
              let width = visualWidth,
              width == visualHeight,
              width > 0,
              visualMatrix?.count == width * width else { return nil }
        return width
    }

    var suggestedSharedTitle: String {
        if !isBarcode, let url = inferredLaunchURL.flatMap(URL.init(string:)), let host = url.host {
            let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return cleanHost.isEmpty ? "Shared QR Code" : cleanHost
        }
        return isBarcode ? "Shared Barcode" : "Shared QR Code"
    }

    var inferredLaunchURL: String? { LaunchURLExtractor.extract(from: payload, encoding: payloadEncoding) }
}

enum LaunchURLExtractor {
    private static let bareDomainPattern = #"^(?:www\.)?(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}(?::\d{2,5})?(?:[/\?#][^\s<>\"'`]*)?$"#
    private static let embeddedHTTPPattern = #"https?://[^\s<>\"'`]+"#

    static func extract(from payload: String, encoding: String = "utf8") -> String? {
        guard encoding == "utf8" else { return nil }
        let trimmed = clean(payload)
        if trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
           let direct = normalizedHTTPURL(trimmed) { return direct }

        if trimmed.range(of: bareDomainPattern, options: [.regularExpression, .caseInsensitive]) != nil,
           let bare = normalizedHTTPURL("https://\(trimmed)") {
            return bare
        }

        let range = NSRange(payload.startIndex..<payload.endIndex, in: payload)
        guard let expression = try? NSRegularExpression(
            pattern: embeddedHTTPPattern,
            options: [.caseInsensitive]
        ),
        let match = expression.firstMatch(in: payload, range: range),
        let matchRange = Range(match.range, in: payload) else { return nil }
        return normalizedHTTPURL(clean(String(payload[matchRange])))
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[\(\[\{<]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\),\.;:!\?\}\]>]+$"#, with: "", options: .regularExpression)
    }

    private static func normalizedHTTPURL(_ value: String) -> String? {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false,
              let url = components.url else { return nil }
        return url.absoluteString
    }
}

struct CreatePass: Encodable {
    let title: String
    let issuer: String?
    let codeType: String
    let format: String?
    let encodedValue: String
    let payloadEncoding: String?
    let launchUrl: String?
    let visualMatrix: String?
    let visualSize: Int?
    let visualWidth: Int?
    let visualHeight: Int?
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
        payloadEncoding = code.payloadEncoding == "utf8" ? nil : code.payloadEncoding
        launchUrl = code.inferredLaunchURL
        visualMatrix = code.visualMatrix
        visualSize = code.visualSize
        visualWidth = code.visualWidth
        visualHeight = code.visualHeight
        eventDate = nil
        notes = nil
        self.color = color
    }
}

enum CodeImportError: LocalizedError {
    case invalidImage
    case noCodeFound
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "That image could not be opened. Try another screenshot."
        case .noCodeFound:
            "No QR code or barcode was found. Try a clearer or less-cropped image."
        case .verificationFailed:
            "A code was found but its saved copy could not be verified. Move closer, use zoom, or try a clearer image."
        }
    }
}

struct BinaryCodeMatrix: Hashable, Sendable {
    let bits: String
    let width: Int
    let height: Int

    var isValid: Bool {
        width > 0 &&
            height > 0 &&
            height <= 40_000 &&
            width <= 40_000 / height &&
            width * height == bits.count &&
            bits.allSatisfy { $0 == "0" || $0 == "1" }
    }

    /// Core Image's barcode-descriptor generator can include complete white
    /// quiet-zone rings. Remove only full, symmetric rings: trimming a merely
    /// light outer row or column could delete legitimate symbol modules.
    func trimmingLightBorder() -> BinaryCodeMatrix {
        guard isValid else { return self }
        let cells = Array(bits.utf8)
        var minimumColumn = 0
        var minimumRow = 0
        var maximumColumn = width - 1
        var maximumRow = height - 1

        func isLight(_ row: Int, _ column: Int) -> Bool {
            cells[row * width + column] == 48
        }

        while minimumColumn < maximumColumn, minimumRow < maximumRow {
            let topIsLight = (minimumColumn...maximumColumn).allSatisfy {
                isLight(minimumRow, $0)
            }
            let bottomIsLight = (minimumColumn...maximumColumn).allSatisfy {
                isLight(maximumRow, $0)
            }
            let leftIsLight = (minimumRow...maximumRow).allSatisfy {
                isLight($0, minimumColumn)
            }
            let rightIsLight = (minimumRow...maximumRow).allSatisfy {
                isLight($0, maximumColumn)
            }
            guard topIsLight, bottomIsLight, leftIsLight, rightIsLight else { break }
            minimumColumn += 1
            minimumRow += 1
            maximumColumn -= 1
            maximumRow -= 1
        }

        let croppedWidth = maximumColumn - minimumColumn + 1
        let croppedHeight = maximumRow - minimumRow + 1
        guard croppedWidth != width || croppedHeight != height else { return self }

        var cropped = String()
        cropped.reserveCapacity(croppedWidth * croppedHeight)
        for row in minimumRow...maximumRow {
            for column in minimumColumn...maximumColumn {
                cropped.append(cells[row * width + column] == 49 ? "1" : "0")
            }
        }
        return BinaryCodeMatrix(bits: cropped, width: croppedWidth, height: croppedHeight)
    }
}

enum CodeSymbolCodec {
    private static let iOS17Symbologies: [VNBarcodeSymbology] = [
        .qr, .microQR, .aztec, .dataMatrix, .pdf417, .microPDF417,
        .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum,
        .code93, .code93i, .code128,
        .ean8, .ean13, .upce,
        .i2of5, .i2of5Checksum, .itf14, .codabar,
        .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited, .msiPlessey,
    ]

    static let supportedSymbologies: [VNBarcodeSymbology] = {
        let request = VNDetectBarcodesRequest()
        return (try? request.supportedSymbologies()) ?? iOS17Symbologies
    }()

    static func detectedCode(from observation: VNBarcodeObservation, sourceImage: CGImage?) -> DetectedCode? {
        guard let identity = payloadIdentity(for: observation) else { return nil }
        let format = normalizedFormat(for: observation.symbology)

        let matrix = observation.barcodeDescriptor.flatMap(matrix(from:))
            ?? sourceImage.flatMap { sampledMatrix(from: $0, observation: observation) }
        guard let matrix, matrix.isValid else { return nil }

        let code = DetectedCode(
            payload: identity.value,
            format: format,
            codeType: isQR(observation.symbology) ? "qr" : "barcode",
            payloadEncoding: identity.encoding,
            visualMatrix: matrix.bits,
            visualWidth: matrix.width,
            visualHeight: matrix.height
        )
        guard verifies(code, symbology: observation.symbology) else { return nil }
        return code
    }

    static func verifies(_ code: DetectedCode, symbology: VNBarcodeSymbology? = nil) -> Bool {
        guard let bits = code.visualMatrix,
              let width = code.visualWidth ?? code.visualSize,
              let height = code.visualHeight ?? code.visualSize,
              let image = renderedImage(BinaryCodeMatrix(bits: bits, width: width, height: height), format: code.format) else {
            return false
        }

        return verifies(code, renderedImage: image, symbology: symbology)
    }

    static func verifies(_ code: DetectedCode, renderedImage image: CGImage, symbology: VNBarcodeSymbology? = nil) -> Bool {
        let request = VNDetectBarcodesRequest()
        request.symbologies = symbology.map { [$0] } ?? supportedSymbologies
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        } catch {
            return false
        }
        return (request.results ?? []).contains { observation in
            normalizedFormat(for: observation.symbology) == code.format && payloadMatches(code, observation: observation)
        }
    }

    static func legacyRegeneratedCode(payload: String, format: String) -> DetectedCode? {
        guard let code = regeneratedCode(payload: payload, format: format) else { return nil }
        return verifies(code) ? code : nil
    }

    #if DEBUG
    static func debugGeneratedCode(payload: String, format: String) -> DetectedCode? {
        regeneratedCode(payload: payload, format: format)
    }
    #endif

    private static func regeneratedCode(payload: String, format: String) -> DetectedCode? {
        let output: CIImage?
        switch format {
        case "QR_CODE":
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(payload.utf8)
            filter.correctionLevel = "M"
            output = filter.outputImage
        case "CODE_128":
            let filter = CIFilter.code128BarcodeGenerator()
            filter.message = Data(payload.utf8)
            filter.quietSpace = 0
            output = filter.outputImage
        case "AZTEC":
            let filter = CIFilter.aztecCodeGenerator()
            filter.message = Data(payload.utf8)
            output = filter.outputImage
        case "PDF417":
            let filter = CIFilter.pdf417BarcodeGenerator()
            filter.message = Data(payload.utf8)
            output = filter.outputImage
        default:
            return nil
        }
        guard let output, let matrix = matrix(from: output) else { return nil }
        return DetectedCode(
            payload: payload,
            format: format,
            codeType: format == "QR_CODE" ? "qr" : "barcode",
            visualMatrix: matrix.bits,
            visualWidth: matrix.width,
            visualHeight: matrix.height
        )
    }

    static func normalizedFormat(for symbology: VNBarcodeSymbology) -> String {
        switch symbology {
        case .qr: "QR_CODE"
        case .microQR: "MICRO_QR"
        case .aztec: "AZTEC"
        case .dataMatrix: "DATA_MATRIX"
        case .pdf417: "PDF417"
        case .microPDF417: "MICRO_PDF417"
        case .code39: "CODE_39"
        case .code39Checksum: "CODE_39_CHECKSUM"
        case .code39FullASCII: "CODE_39_FULL_ASCII"
        case .code39FullASCIIChecksum: "CODE_39_FULL_ASCII_CHECKSUM"
        case .code93: "CODE_93"
        case .code93i: "CODE_93I"
        case .code128: "CODE_128"
        case .ean8: "EAN_8"
        case .ean13: "EAN_13"
        case .upce: "UPC_E"
        case .i2of5: "I2OF5"
        case .i2of5Checksum: "I2OF5_CHECKSUM"
        case .itf14: "ITF_14"
        case .codabar: "CODABAR"
        case .gs1DataBar: "GS1_DATABAR"
        case .gs1DataBarExpanded: "GS1_DATABAR_EXPANDED"
        case .gs1DataBarLimited: "GS1_DATABAR_LIMITED"
        case .msiPlessey: "MSI_PLESSEY"
        default: symbology.rawValue.uppercased()
        }
    }

    static func renderedImage(_ matrix: BinaryCodeMatrix, format: String) -> CGImage? {
        guard matrix.isValid else { return nil }
        let linear = matrix.height == 1
        let quietX = linear ? 12 : 4
        let quietY = 4
        let moduleScale = max(1, min(12, 1_200 / max(1, matrix.width + quietX * 2)))
        let contentHeight = linear ? 180 : matrix.height * moduleScale
        let outputWidth = (matrix.width + quietX * 2) * moduleScale
        let outputHeight = contentHeight + quietY * 2 * moduleScale
        guard outputWidth > 0, outputHeight > 0 else { return nil }

        let bits = Array(matrix.bits.utf8)
        var pixels = Array(repeating: UInt8(255), count: outputWidth * outputHeight)
        for y in 0..<contentHeight {
            let sourceRow = linear ? 0 : min(matrix.height - 1, y / moduleScale)
            for x in 0..<(matrix.width * moduleScale) {
                let sourceColumn = min(matrix.width - 1, x / moduleScale)
                if bits[sourceRow * matrix.width + sourceColumn] == 49 {
                    let targetX = x + quietX * moduleScale
                    let targetY = y + quietY * moduleScale
                    pixels[targetY * outputWidth + targetX] = 0
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: outputWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func isQR(_ symbology: VNBarcodeSymbology) -> Bool {
        symbology == .qr || symbology == .microQR
    }

    private static func isLinear(_ symbology: VNBarcodeSymbology) -> Bool {
        ![.qr, .microQR, .aztec, .dataMatrix, .pdf417, .microPDF417].contains(symbology)
    }

    private static func payloadIdentity(for observation: VNBarcodeObservation) -> (value: String, encoding: String)? {
        if let string = observation.payloadStringValue, !string.isEmpty {
            return (string, "utf8")
        }
        if let data = observation.payloadData, !data.isEmpty {
            return (data.base64EncodedString(), "base64")
        }
        return nil
    }

    private static func payloadMatches(_ code: DetectedCode, observation: VNBarcodeObservation) -> Bool {
        if code.payloadEncoding == "base64" {
            return observation.payloadData?.base64EncodedString() == code.payload
        }
        return observation.payloadStringValue == code.payload
    }

    private static func matrix(from descriptor: CIBarcodeDescriptor) -> BinaryCodeMatrix? {
        let filter = CIFilter.barcodeGenerator()
        filter.barcodeDescriptor = descriptor
        guard let output = filter.outputImage else { return nil }
        return matrix(from: output)
    }

    private static func matrix(from image: CIImage) -> BinaryCodeMatrix? {
        let extent = image.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0, width * height <= 40_000 else { return nil }
        var pixels = Array(repeating: UInt8(255), count: width * height * 4)
        CIContext(options: [.useSoftwareRenderer: false]).render(
            image,
            toBitmap: &pixels,
            rowBytes: width * 4,
            bounds: extent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        var bits = String()
        bits.reserveCapacity(width * height)
        for index in 0..<(width * height) {
            bits.append(pixels[index * 4] < 128 ? "1" : "0")
        }
        return BinaryCodeMatrix(bits: bits, width: width, height: height).trimmingLightBorder()
    }

    private static func sampledMatrix(from image: CGImage, observation: VNBarcodeObservation) -> BinaryCodeMatrix? {
        let source = CIImage(cgImage: image)
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let correction = CIFilter.perspectiveCorrection()
        correction.inputImage = source
        correction.topLeft = CGPoint(x: observation.topLeft.x * width, y: observation.topLeft.y * height)
        correction.topRight = CGPoint(x: observation.topRight.x * width, y: observation.topRight.y * height)
        correction.bottomLeft = CGPoint(x: observation.bottomLeft.x * width, y: observation.bottomLeft.y * height)
        correction.bottomRight = CGPoint(x: observation.bottomRight.x * width, y: observation.bottomRight.y * height)
        guard let corrected = correction.outputImage else { return nil }
        return sampledMatrix(from: corrected, linear: isLinear(observation.symbology))
    }

    private static func sampledMatrix(from image: CIImage, linear: Bool) -> BinaryCodeMatrix? {
        let extent = image.extent.integral
        let sourceWidth = Int(extent.width)
        let sourceHeight = Int(extent.height)
        guard sourceWidth > 2, sourceHeight > 2 else { return nil }

        var pixels = Array(repeating: UInt8(255), count: sourceWidth * sourceHeight * 4)
        CIContext().render(
            image,
            toBitmap: &pixels,
            rowBytes: sourceWidth * 4,
            bounds: extent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        if linear {
            let firstRow = sourceHeight / 5
            let lastRow = max(firstRow + 1, sourceHeight * 4 / 5)
            var luminance = Array(repeating: 0.0, count: sourceWidth)
            for x in 0..<sourceWidth {
                var sum = 0.0
                for y in firstRow..<lastRow {
                    let offset = (y * sourceWidth + x) * 4
                    sum += 0.299 * Double(pixels[offset]) + 0.587 * Double(pixels[offset + 1]) + 0.114 * Double(pixels[offset + 2])
                }
                luminance[x] = sum / Double(lastRow - firstRow)
            }
            let sourceBits = thresholdedValues(luminance)
            return normalizedLinearMatrix(sourceBits)
        }

        let scale = min(1, sqrt(40_000.0 / Double(sourceWidth * sourceHeight)))
        let targetWidth = max(1, Int(Double(sourceWidth) * scale))
        let targetHeight = max(1, Int(Double(sourceHeight) * scale))
        var luminance = Array(repeating: 255.0, count: targetWidth * targetHeight)
        for row in 0..<targetHeight {
            for column in 0..<targetWidth {
                let sourceX = min(sourceWidth - 1, column * sourceWidth / targetWidth)
                let sourceY = min(sourceHeight - 1, row * sourceHeight / targetHeight)
                let offset = (sourceY * sourceWidth + sourceX) * 4
                luminance[row * targetWidth + column] =
                    0.299 * Double(pixels[offset]) + 0.587 * Double(pixels[offset + 1]) + 0.114 * Double(pixels[offset + 2])
            }
        }
        let bits = thresholdedValues(luminance).map { $0 ? "1" : "0" }.joined()
        return BinaryCodeMatrix(bits: bits, width: targetWidth, height: targetHeight)
    }

    private static func normalizedLinearMatrix(_ source: [Bool]) -> BinaryCodeMatrix? {
        guard let firstDark = source.firstIndex(of: true), let lastDark = source.lastIndex(of: true), firstDark <= lastDark else { return nil }
        let cropped = Array(source[firstDark...lastDark])
        var runs: [(dark: Bool, length: Int)] = []
        var index = 0
        while index < cropped.count {
            let dark = cropped[index]
            let start = index
            while index < cropped.count && cropped[index] == dark { index += 1 }
            runs.append((dark, index - start))
        }
        let sortedLengths = runs.map(\.length).sorted()
        guard !sortedLengths.isEmpty else { return nil }
        let narrowSample = Array(sortedLengths.prefix(max(1, sortedLengths.count / 3)))
        let module = max(1.0, Double(narrowSample.reduce(0, +)) / Double(narrowSample.count))
        var bits = String()
        for run in runs {
            let count = max(1, min(24, Int((Double(run.length) / module).rounded())))
            bits.append(String(repeating: run.dark ? "1" : "0", count: count))
        }
        return BinaryCodeMatrix(bits: bits, width: bits.count, height: 1)
    }

    private static func otsuThreshold(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 128 }
        var histogram = Array(repeating: 0, count: 256)
        for value in values { histogram[min(255, max(0, Int(value.rounded())))] += 1 }
        let total = values.count
        let sum = histogram.enumerated().reduce(0.0) { $0 + Double($1.offset * $1.element) }
        var backgroundWeight = 0
        var backgroundSum = 0.0
        var bestVariance = -1.0
        var bestThreshold = 128
        for threshold in 0..<256 {
            backgroundWeight += histogram[threshold]
            guard backgroundWeight > 0 else { continue }
            let foregroundWeight = total - backgroundWeight
            guard foregroundWeight > 0 else { break }
            backgroundSum += Double(threshold * histogram[threshold])
            let backgroundMean = backgroundSum / Double(backgroundWeight)
            let foregroundMean = (sum - backgroundSum) / Double(foregroundWeight)
            let variance = Double(backgroundWeight * foregroundWeight) * pow(backgroundMean - foregroundMean, 2)
            if variance > bestVariance {
                bestVariance = variance
                bestThreshold = threshold
            }
        }
        return Double(bestThreshold)
    }

    static func thresholdedValues(_ values: [Double]) -> [Bool] {
        let threshold = otsuThreshold(values)
        return values.map { $0 <= threshold }
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
        let longEdge = max(width, height)

        guard let firstImage = orientedImage(from: source, maxPixelSize: min(4_096, longEdge)) else {
            throw CodeImportError.invalidImage
        }
        var seen = Set<String>()
        var detected: [DetectedCode] = []
        var foundObservation = false

        func decode(_ image: CGImage) throws {
            let observations = try detectObservations(in: image).sorted {
                ($0.boundingBox.width * $0.boundingBox.height) > ($1.boundingBox.width * $1.boundingBox.height)
            }
            foundObservation = foundObservation || !observations.isEmpty
            for observation in observations {
                guard let code = CodeSymbolCodec.detectedCode(from: observation, sourceImage: image),
                      seen.insert(code.id).inserted else { continue }
                detected.append(code)
            }
        }

        try decode(firstImage)
        if longEdge > 4_096, let fullImage = orientedImage(from: source, maxPixelSize: longEdge) {
            try decode(fullImage)
            for rectangle in tileRectangles(for: fullImage) {
                try autoreleasepool {
                    guard let tile = fullImage.cropping(to: rectangle) else { return }
                    try decode(tile)
                }
            }
        }

        guard !detected.isEmpty else {
            throw foundObservation ? CodeImportError.verificationFailed : CodeImportError.noCodeFound
        }
        return detected
    }

    private static func tileRectangles(for image: CGImage, tileSize: Int = 2_048, overlap: Int = 256) -> [CGRect] {
        guard image.width > tileSize || image.height > tileSize else { return [] }
        let step = max(1, tileSize - overlap)
        var origins = Set<String>()
        var result: [CGRect] = []

        for proposedY in stride(from: 0, to: image.height, by: step) {
            for proposedX in stride(from: 0, to: image.width, by: step) {
                let width = min(tileSize, image.width)
                let height = min(tileSize, image.height)
                let x = min(proposedX, image.width - width)
                let y = min(proposedY, image.height - height)
                guard origins.insert("\(x):\(y)").inserted else { continue }
                result.append(CGRect(x: x, y: y, width: width, height: height))
            }
        }
        return result
    }

    private static func orientedImage(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func detectObservations(in image: CGImage) throws -> [VNBarcodeObservation] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = CodeSymbolCodec.supportedSymbologies
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        return request.results ?? []
    }
}
