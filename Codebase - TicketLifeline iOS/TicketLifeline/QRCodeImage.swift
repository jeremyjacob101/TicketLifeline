import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct QRCodeImage: View {
    let payload: String

    var body: some View {
        Image(uiImage: makeImage(payload: payload) ?? UIImage(systemName: "qrcode")!)
            .resizable()
            .scaledToFit()
            .accessibilityLabel("QR code for scanned value")
    }

    private func makeImage(payload: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct BarcodeImage: View {
    let payload: String

    var body: some View {
        Image(uiImage: makeImage(payload: payload) ?? UIImage(systemName: "barcode")!)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .accessibilityLabel("Barcode for scanned value")
    }

    private func makeImage(payload: String) -> UIImage? {
        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = Data(payload.utf8)
        filter.quietSpace = 8
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 4, y: 5))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
