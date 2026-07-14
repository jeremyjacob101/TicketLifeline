import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
import UIKit
import XCTest
@testable import TicketLifeline

final class CodeImageDecoderTests: XCTestCase {
    private let qrPayload = "https://ticketlifeline.app/test-pass"
    private let barcodePayload = "123456789012"

    func testDecodesPNGQRCode() async throws {
        let codes = try await decodeOrSkip(try pngData(qrImage()))
        XCTAssertEqual(codes, [DetectedCode(payload: qrPayload, format: "QR_CODE", codeType: "qr")])
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

    private func qrImage(
        payload: String? = nil,
        size: CGFloat = 760,
        foreground: UIColor = .black,
        background: UIColor = .white
    ) -> UIImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data((payload ?? qrPayload).utf8)
        filter.correctionLevel = "H"
        let output = filter.outputImage!
            .transformed(by: CGAffineTransform(scaleX: 18, y: 18))
        return coloredCode(output, size: CGSize(width: size, height: size), foreground: foreground, background: background)
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
        do {
            return try await CodeImageDecoder.detect(in: data)
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("inference context") || message.contains("civisionfilters") {
                throw XCTSkip("Vision inference is unavailable in this simulator runtime: \(error.localizedDescription)")
            }
            throw error
        }
    }
}
