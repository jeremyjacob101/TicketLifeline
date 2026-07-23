import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
import UIKit
import Vision
import XCTest
@testable import TicketLifeline

final class CodeImageDecoderTests: XCTestCase {
    private let qrPayload = "https://ticketlifeline.app/test-pass"
    private let barcodePayload = "123456789012"

    func testEmailAuthenticationValidation() throws {
        XCTAssertEqual(
            try AccountAuthValidation.normalizedEmail("  Person@Example.COM "),
            "person@example.com"
        )
        XCTAssertThrowsError(try AccountAuthValidation.normalizedEmail("person"))
        XCTAssertNoThrow(try AccountAuthValidation.validatePassword("12345678"))
        XCTAssertThrowsError(try AccountAuthValidation.validatePassword("1234567"))
        XCTAssertEqual(try AccountAuthValidation.confirmationCode(" 012345 "), "012345")
        XCTAssertThrowsError(try AccountAuthValidation.confirmationCode("12345"))
    }

    func testAuthenticationErrorsDoNotExposeRawServerDetails() {
        XCTAssertEqual(
            AccountAuthValidation.userFacingMessage(for: AppError.message("Invalid credentials")),
            "Email or password is incorrect."
        )
        XCTAssertTrue(
            AccountAuthValidation.userFacingMessage(for: AppError.message("Could not verify code"))
                .contains("incorrect or expired")
        )
        XCTAssertEqual(
            AccountAuthValidation.userFacingMessage(
                for: AppError.message("[Request ID: secret] Server Error: internal stack")
            ),
            "We could not complete that request. Please try again."
        )
    }

    func testCodeSaveErrorsDoNotExposeRawServerDetails() {
        XCTAssertEqual(
            CodeOperationError.userFacingMessage(
                for: AppError.message("[Request ID: secret] Server Error: internal stack")
            ),
            "TicketLifeline could not save this code. Please try again."
        )
        XCTAssertTrue(
            CodeOperationError.userFacingMessage(
                for: AppError.message("QR matrix size is invalid.")
            ).contains("saved safely")
        )
    }

    func testLegacyUsernameSessionDecodesAsEmailIdentity() throws {
        let data = Data(#"{"username":"legacy@example.com","token":"token","refreshToken":"refresh"}"#.utf8)
        let session = try JSONDecoder().decode(ConvexSession.self, from: data)
        XCTAssertEqual(session.email, "legacy@example.com")
        let encoded = try JSONEncoder().encode(session)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: String])
        XCTAssertEqual(object["email"], "legacy@example.com")
        XCTAssertNil(object["username"])
    }

    func testVisionDirectQRProbe() throws {
        let image = try XCTUnwrap(qrImage().cgImage)
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        } catch {
            if isUnavailableVisionError(error) {
                throw XCTSkip("Vision inference is unavailable in this simulator runtime: \(error.localizedDescription)")
            }
            throw error
        }
        guard let decoded = request.results?.first?.payloadStringValue else {
            #if targetEnvironment(simulator)
            throw XCTSkip("Vision completed without barcode results in this simulator runtime.")
            #else
            XCTFail("Vision returned no barcode result.")
            return
            #endif
        }
        XCTAssertEqual(decoded, qrPayload)
        XCTAssertTrue(CodeSymbolCodec.supportedSymbologies.contains(.qr))
    }

    func testDecodesPNGQRCode() async throws {
        let codes = try await decodeOrSkip(try pngData(qrImage()))
        XCTAssertEqual(codes.first?.payload, qrPayload)
        XCTAssertEqual(codes.first?.format, "QR_CODE")
        XCTAssertEqual(codes.first?.codeType, "qr")
        XCTAssertNotNil(codes.first?.visualMatrix)
        XCTAssertEqual(codes.first?.visualWidth, codes.first?.visualHeight)
        XCTAssertTrue(codes.first.map { CodeSymbolCodec.verifies($0) } == true)
    }

    func testTrimsQuietBorderBeforeSavingMatrixDimensions() {
        let bordered = BinaryCodeMatrix(
            bits: "00000" + "01110" + "01010" + "01110" + "00000",
            width: 5,
            height: 5
        )
        let trimmed = bordered.trimmingLightBorder()
        XCTAssertEqual(trimmed.width, 3)
        XCTAssertEqual(trimmed.height, 3)
        XCTAssertEqual(trimmed.bits, "111101111")
    }

    func testLegacyQRVisualSizePreservesAnyVerifiedSquareDimensions() {
        let standard = DetectedCode(
            payload: "standard",
            format: "QR_CODE",
            codeType: "qr",
            visualMatrix: String(repeating: "0", count: 21 * 21),
            visualWidth: 21,
            visualHeight: 21
        )
        let bordered = DetectedCode(
            payload: "bordered",
            format: "QR_CODE",
            codeType: "qr",
            visualMatrix: String(repeating: "0", count: 23 * 23),
            visualWidth: 23,
            visualHeight: 23
        )
        XCTAssertEqual(standard.visualSize, 21)
        XCTAssertEqual(bordered.visualSize, 23)
        let pass = CreatePass(code: bordered, title: "Bordered fixture")
        XCTAssertEqual(pass.visualSize, 23)
        XCTAssertEqual(pass.visualWidth, 23)
        XCTAssertEqual(pass.visualHeight, 23)
    }

    func testQuietBorderTrimmingDoesNotRemoveAsymmetricLightEdges() {
        let matrix = BinaryCodeMatrix(
            bits: "001" + "011" + "001",
            width: 3,
            height: 3
        )
        XCTAssertEqual(matrix.trimmingLightBorder(), matrix)
    }

    func testDecodesJPEGAndRotatedQRCode() async throws {
        let rotated = rotate(qrImage(), radians: .pi / 2)
        let data = try XCTUnwrap(rotated.jpegData(compressionQuality: 0.72))
        let codes = try await decodeOrSkip(data)
        XCTAssertEqual(codes.first?.payload, qrPayload)
    }

    func testDecodesHEICWhenEncoderIsAvailable() async throws {
        guard let data = imageData(qrImage(), type: UTType.heic.identifier) else {
            throw XCTSkip("HEIC encoding is unavailable on this simulator runtime.")
        }
        let codes = try await decodeOrSkip(data)
        XCTAssertEqual(codes.first?.payload, qrPayload)
    }

    func testDecodesCroppedLowContrastQRCode() async throws {
        let source = qrImage(foreground: UIColor(white: 0.30, alpha: 1), background: UIColor(white: 0.88, alpha: 1))
        let insetCrop = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 720)).image { context in
            UIColor(white: 0.88, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 720, height: 720)))
            source.draw(in: CGRect(x: -20, y: -20, width: 760, height: 760))
        }
        let codes = try await decodeOrSkip(try pngData(insetCrop))
        XCTAssertEqual(codes.first?.payload, qrPayload)
    }

    func testDescriptorReconstructsQRCodeWithCenterObstruction() async throws {
        let source = qrImage(size: 900)
        let obstructed = UIGraphicsImageRenderer(size: source.size).image { context in
            source.draw(at: .zero)
            UIColor.white.setFill()
            context.fill(CGRect(x: 385, y: 385, width: 130, height: 130))
        }
        let codes = try await decodeOrSkip(pngData(obstructed))
        let code = try XCTUnwrap(codes.first)
        XCTAssertEqual(code.payload, qrPayload)
        XCTAssertEqual(code.format, "QR_CODE")
        XCTAssertTrue(CodeSymbolCodec.verifies(code))
    }

    func testDecodesCode128Barcode() async throws {
        let codes = try await decodeOrSkip(try pngData(barcodeImage()))
        XCTAssertEqual(codes.first?.payload, barcodePayload)
        XCTAssertEqual(codes.first?.format, "CODE_128")
        XCTAssertEqual(codes.first?.codeType, "barcode")
    }

    func testReturnsAllDistinctCodesAndRemovesDuplicates() async throws {
        let first = qrImage(payload: qrPayload, size: 480)
        let duplicate = qrImage(payload: qrPayload, size: 480)
        let second = qrImage(payload: "ticketlifeline-second-code", size: 480)
        let composite = UIGraphicsImageRenderer(size: CGSize(width: 1_440, height: 520)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_440, height: 520))
            first.draw(in: CGRect(x: 20, y: 20, width: 480, height: 480))
            duplicate.draw(in: CGRect(x: 500, y: 20, width: 480, height: 480))
            second.draw(in: CGRect(x: 960, y: 20, width: 480, height: 480))
        }
        let codes = try await decodeOrSkip(try pngData(composite))
        XCTAssertEqual(Set(codes.map(\.payload)), Set([qrPayload, "ticketlifeline-second-code"]))
        XCTAssertEqual(codes.count, 2)
    }

    func testNoCodeError() async throws {
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
        }
        do {
            _ = try await decodeOrSkip(try pngData(blank))
            XCTFail("Expected noCodeFound")
        } catch let error as CodeImportError {
            XCTAssertEqual(error.errorDescription, CodeImportError.noCodeFound.errorDescription)
        }
    }

    func testInvalidImageError() async throws {
        do {
            _ = try await CodeImageDecoder.detect(in: Data("not an image".utf8))
            XCTFail("Expected invalidImage")
        } catch let error as CodeImportError {
            XCTAssertEqual(error.errorDescription, CodeImportError.invalidImage.errorDescription)
        }
    }

    func testLaunchURLExtractionNeverChangesPayload() {
        let receiptURL = "https://redcap.cs.huji.ac.il/surveys/?s=DYTEDXWXFYNNWCAC"
        XCTAssertEqual(LaunchURLExtractor.extract(from: receiptURL), receiptURL)
        XCTAssertNil(LaunchURLExtractor.extract(from: "0100050907202618505903100006555039"))
        XCTAssertEqual(
            LaunchURLExtractor.extract(from: "https://example.com/ticket?id=7"),
            "https://example.com/ticket?id=7"
        )
        XCTAssertEqual(
            LaunchURLExtractor.extract(from: "Ticket details: https://example.com/t/7). Keep this."),
            "https://example.com/t/7"
        )
        XCTAssertEqual(LaunchURLExtractor.extract(from: "www.example.com/ticket"), "https://www.example.com/ticket")
        XCTAssertEqual(LaunchURLExtractor.extract(from: "(example.com/ticket)"), "https://example.com/ticket")
        XCTAssertEqual(LaunchURLExtractor.extract(from: "<https://example.com/ticket>"), "https://example.com/ticket")
        XCTAssertEqual(
            LaunchURLExtractor.extract(from: "First https://one.example/a, then https://two.example/b."),
            "https://one.example/a"
        )
        XCTAssertNil(LaunchURLExtractor.extract(from: "Ticket site: example.com/ticket"))
        XCTAssertNil(LaunchURLExtractor.extract(from: "ftp://example.com/ticket"))
        XCTAssertNil(LaunchURLExtractor.extract(from: "javascript:alert(1)"))
        XCTAssertNil(LaunchURLExtractor.extract(from: "mailto:person@example.com"))
        XCTAssertNil(LaunchURLExtractor.extract(from: "https://example.com", encoding: "base64"))
    }

    func testStableScanRequiresTimeUpdatesIdentityAndPosition() {
        let id = UUID()
        var tracker = StableScanTracker(minimumDuration: 0.7, minimumUpdates: 4, movementTolerance: 20)
        let candidate = StableScanCandidate(id: id, payload: "value", format: "QR_CODE", center: CGPoint(x: 100, y: 100))
        XCTAssertFalse(tracker.observe(candidate, at: 0))
        XCTAssertFalse(tracker.observe(candidate, at: 0.3))
        XCTAssertFalse(tracker.observe(candidate, at: 0.6))
        XCTAssertTrue(tracker.observe(candidate, at: 0.71))

        let moved = StableScanCandidate(id: id, payload: "value", format: "QR_CODE", center: CGPoint(x: 140, y: 100))
        XCTAssertFalse(tracker.observe(moved, at: 0.8))
        XCTAssertEqual(tracker.updateCount, 1)

        let decoy = StableScanCandidate(id: UUID(), payload: "other", format: "QR_CODE", center: CGPoint(x: 100, y: 100))
        XCTAssertFalse(tracker.observe(decoy, at: 1.8))
        XCTAssertEqual(tracker.updateCount, 1)
        let identicalNearby = StableScanCandidate(id: UUID(), payload: "other", format: "QR_CODE", center: CGPoint(x: 102, y: 100))
        XCTAssertFalse(tracker.observe(identicalNearby, at: 1.9))
        XCTAssertEqual(tracker.updateCount, 1)
        XCTAssertFalse(tracker.observe(nil, at: 2))
        XCTAssertNil(tracker.candidate)
    }

    func testStableScanRejectsRapidChangesAndFormatChanges() {
        var tracker = StableScanTracker(minimumDuration: 0.7, minimumUpdates: 4, movementTolerance: 20)
        let firstID = UUID()
        let secondID = UUID()
        let first = StableScanCandidate(id: firstID, payload: "first", format: "QR_CODE", center: CGPoint(x: 100, y: 100))
        let second = StableScanCandidate(id: secondID, payload: "second", format: "QR_CODE", center: CGPoint(x: 100, y: 100))

        XCTAssertFalse(tracker.observe(first, at: 0))
        XCTAssertFalse(tracker.observe(second, at: 0.3))
        XCTAssertFalse(tracker.observe(first, at: 0.6))
        XCTAssertFalse(tracker.observe(second, at: 0.9))
        XCTAssertEqual(tracker.updateCount, 1)

        let changedFormat = StableScanCandidate(id: secondID, payload: "second", format: "DATA_MATRIX", center: CGPoint(x: 100, y: 100))
        XCTAssertFalse(tracker.observe(changedFormat, at: 1.7))
        XCTAssertEqual(tracker.updateCount, 1)
        XCTAssertFalse(tracker.observe(changedFormat, at: 1.95))
        XCTAssertFalse(tracker.observe(changedFormat, at: 2.2))
        XCTAssertTrue(tracker.observe(changedFormat, at: 2.41))
    }

    func testBinaryMatrixValidationWithoutVision() {
        XCTAssertTrue(BinaryCodeMatrix(bits: "1001", width: 2, height: 2).isValid)
        XCTAssertTrue(BinaryCodeMatrix(bits: "10101", width: 5, height: 1).isValid)
        XCTAssertFalse(BinaryCodeMatrix(bits: "10x1", width: 2, height: 2).isValid)
        XCTAssertFalse(BinaryCodeMatrix(bits: "100", width: 2, height: 2).isValid)
        XCTAssertFalse(BinaryCodeMatrix(bits: "", width: 0, height: 0).isValid)
        XCTAssertFalse(BinaryCodeMatrix(bits: String(repeating: "1", count: 40_001), width: 40_001, height: 1).isValid)
    }

    func testPureBlackPixelsRemainDarkAtZeroThreshold() {
        XCTAssertEqual(CodeSymbolCodec.thresholdedValues([0, 255]), [true, false])
        XCTAssertEqual(CodeSymbolCodec.thresholdedValues([0, 0, 255, 255]), [true, true, false, false])
    }

    func testFormatNormalizationCoversRuntimeFamilies() {
        let expected: [(VNBarcodeSymbology, String)] = [
            (.qr, "QR_CODE"), (.microQR, "MICRO_QR"), (.aztec, "AZTEC"),
            (.dataMatrix, "DATA_MATRIX"), (.pdf417, "PDF417"), (.microPDF417, "MICRO_PDF417"),
            (.code39, "CODE_39"), (.code93, "CODE_93"), (.code128, "CODE_128"),
            (.ean8, "EAN_8"), (.ean13, "EAN_13"), (.upce, "UPC_E"),
            (.i2of5, "I2OF5"), (.itf14, "ITF_14"), (.codabar, "CODABAR"),
            (.gs1DataBar, "GS1_DATABAR"), (.gs1DataBarExpanded, "GS1_DATABAR_EXPANDED"),
            (.gs1DataBarLimited, "GS1_DATABAR_LIMITED"), (.msiPlessey, "MSI_PLESSEY"),
        ]
        for (symbology, format) in expected {
            XCTAssertEqual(CodeSymbolCodec.normalizedFormat(for: symbology), format)
        }
    }

    func testCreatePassPreservesPayloadAndDimensions() {
        let matrix = String(repeating: "0", count: 21 * 21)
        let code = DetectedCode(
            payload: "Ticket https://example.com/open",
            format: "QR_CODE",
            codeType: "qr",
            visualMatrix: matrix,
            visualWidth: 21,
            visualHeight: 21
        )
        let pass = CreatePass(code: code, title: "  Demo  ")
        XCTAssertEqual(pass.title, "Demo")
        XCTAssertEqual(pass.encodedValue, code.payload)
        XCTAssertEqual(pass.launchUrl, "https://example.com/open")
        XCTAssertEqual(pass.visualMatrix, matrix)
        XCTAssertEqual(pass.visualSize, 21)
        XCTAssertEqual(pass.visualWidth, 21)
        XCTAssertEqual(pass.visualHeight, 21)
        XCTAssertNil(pass.payloadEncoding)
    }

    func testSafeLegacyRegeneration() throws {
        try requireVision()
        let qr = try XCTUnwrap(CodeSymbolCodec.legacyRegeneratedCode(payload: qrPayload, format: "QR_CODE"))
        XCTAssertTrue(CodeSymbolCodec.verifies(qr))
        let barcode = try XCTUnwrap(CodeSymbolCodec.legacyRegeneratedCode(payload: barcodePayload, format: "CODE_128"))
        XCTAssertTrue(CodeSymbolCodec.verifies(barcode))
        let aztec = try XCTUnwrap(CodeSymbolCodec.legacyRegeneratedCode(payload: qrPayload, format: "AZTEC"))
        XCTAssertTrue(CodeSymbolCodec.verifies(aztec))
        let pdf417 = try XCTUnwrap(CodeSymbolCodec.legacyRegeneratedCode(payload: qrPayload, format: "PDF417"))
        XCTAssertTrue(CodeSymbolCodec.verifies(pdf417))
        XCTAssertNil(CodeSymbolCodec.legacyRegeneratedCode(payload: barcodePayload, format: "EAN_13"))
    }

    func testMatrixValidationRejectsInvalidBitsAndDimensionMismatch() throws {
        try requireVision()
        let original = try XCTUnwrap(CodeSymbolCodec.legacyRegeneratedCode(payload: qrPayload, format: "QR_CODE"))
        let matrix = try XCTUnwrap(original.visualMatrix)
        let width = try XCTUnwrap(original.visualWidth)
        let height = try XCTUnwrap(original.visualHeight)

        let invalidBits = DetectedCode(
            payload: original.payload,
            format: original.format,
            codeType: original.codeType,
            payloadEncoding: original.payloadEncoding,
            visualMatrix: String(matrix.dropLast()) + "x",
            visualWidth: width,
            visualHeight: height
        )
        XCTAssertFalse(CodeSymbolCodec.verifies(invalidBits))

        let wrongDimensions = DetectedCode(
            payload: original.payload,
            format: original.format,
            codeType: original.codeType,
            payloadEncoding: original.payloadEncoding,
            visualMatrix: matrix,
            visualWidth: width + 1,
            visualHeight: height
        )
        XCTAssertFalse(CodeSymbolCodec.verifies(wrongDimensions))
    }

    private func qrImage(
        payload: String? = nil,
        size: CGFloat = 760,
        foreground: UIColor = .black,
        background: UIColor = .white
    ) -> UIImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data((payload ?? qrPayload).utf8)
        filter.correctionLevel = "H"
        let native = filter.outputImage!
        let side = Int(native.extent.width)
        let moduleScale = max(1, Int(size / CGFloat(side + 8)))
        let colorFilter = CIFilter.falseColor()
        colorFilter.inputImage = native
        colorFilter.color0 = CIColor(color: foreground)
        colorFilter.color1 = CIColor(color: background)
        let output = colorFilter.outputImage!
            .transformed(by: CGAffineTransform(scaleX: CGFloat(moduleScale), y: CGFloat(moduleScale)))
        let cgImage = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(output, from: output.extent)!
        let rendered = UIImage(cgImage: cgImage)
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: size, height: size)))
            context.cgContext.interpolationQuality = .none
            let origin = CGPoint(
                x: floor((size - rendered.size.width) / 2),
                y: floor((size - rendered.size.height) / 2)
            )
            rendered.draw(at: origin)
        }
    }

    private func barcodeImage() -> UIImage {
        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = Data(barcodePayload.utf8)
        filter.quietSpace = 12
        let output = filter.outputImage!
            .transformed(by: CGAffineTransform(scaleX: 4, y: 7))
        return coloredCode(output, size: CGSize(width: 1_100, height: 420), foreground: .black, background: .white)
    }

    private func coloredCode(_ code: CIImage, size: CGSize, foreground: UIColor, background: UIColor) -> UIImage {
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let cgImage = context.createCGImage(code, from: code.extent)!
        let rendered = UIImage(cgImage: cgImage)
        return UIGraphicsImageRenderer(size: size).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let fitted = AVMakeRect(aspectRatio: rendered.size, insideRect: CGRect(origin: .zero, size: size).insetBy(dx: 24, dy: 24))
            rendered.draw(in: fitted, blendMode: .normal, alpha: foreground == .black && background == .white ? 1 : 0.65)
        }
    }

    private func rotate(_ image: UIImage, radians: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: image.size.height, height: image.size.width)).image { context in
            context.cgContext.translateBy(x: image.size.height / 2, y: image.size.width / 2)
            context.cgContext.rotate(by: radians)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }

    private func pngData(_ image: UIImage) throws -> Data {
        try XCTUnwrap(image.pngData())
    }

    private func imageData(_ image: UIImage, type: String) -> Data? {
        guard let cgImage = image.cgImage,
              let output = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(output, type as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private func decodeOrSkip(_ data: Data) async throws -> [DetectedCode] {
        try requireVision()
        do {
            return try await CodeImageDecoder.detect(in: data)
        } catch {
            let message = error.localizedDescription.lowercased()
            if isUnavailableVisionError(error) || message.contains("civisionfilters") {
                throw XCTSkip("Vision inference is unavailable in this simulator runtime: \(error.localizedDescription)")
            }
            throw error
        }
    }

    private func requireVision() throws {
        let image = try XCTUnwrap(qrImage(size: 240).cgImage)
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        } catch {
            if isUnavailableVisionError(error) {
                throw XCTSkip("Vision inference is unavailable in this simulator runtime: \(error.localizedDescription)")
            }
            throw error
        }
        guard request.results?.first?.payloadStringValue != nil else {
            #if targetEnvironment(simulator)
            throw XCTSkip("Vision completed without barcode results in this simulator runtime.")
            #else
            XCTFail("Vision returned no barcode result.")
            return
            #endif
        }
    }

    private func isUnavailableVisionError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("inference context") || message.contains("civisionfilters")
    }
}
