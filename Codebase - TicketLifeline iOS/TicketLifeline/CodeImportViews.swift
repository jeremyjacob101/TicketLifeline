import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ImportedPhoto: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            ImportedPhoto(data: data)
        }
    }
}

struct PhotoCodeImportView: View {
    @ObservedObject var appState: AppState
    let codes: [DetectedCode]
    @State private var selectedCode: DetectedCode?

    init(appState: AppState, codes: [DetectedCode]) {
        self.appState = appState
        self.codes = codes
        _selectedCode = State(initialValue: codes.count == 1 ? codes[0] : nil)
    }

    var body: some View {
        if let selectedCode {
            CodeImportReviewView(appState: appState, code: selectedCode) {
                self.selectedCode = nil
            }
        } else {
            CodeChoiceView(codes: codes) { self.selectedCode = $0 }
        }
    }
}

private struct CodeChoiceView: View {
    @Environment(\.dismiss) private var dismiss
    let codes: [DetectedCode]
    let onSelect: (DetectedCode) -> Void

    var body: some View {
        NavigationStack {
            List(codes) { code in
                Button { onSelect(code) } label: {
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
            .navigationTitle("Choose a Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct CodeImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appState: AppState
    let code: DetectedCode
    let onBack: (() -> Void)?
    @State private var label = ""
    @State private var errorMessage: String?

    init(appState: AppState, code: DetectedCode, onBack: (() -> Void)? = nil) {
        self.appState = appState
        self.code = code
        self.onBack = onBack
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Group {
                    if code.isBarcode {
                        BarcodeImage(payload: code.payload)
                    } else {
                        QRCodeImage(payload: code.payload)
                    }
                }
                .frame(width: 220, height: 190)

                VStack(spacing: 6) {
                    Text(code.isBarcode ? "Barcode found" : "QR code found")
                        .font(.title2.bold())
                    Text(code.format.replacingOccurrences(of: "_", with: " "))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(code.payload)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                TextField("Name this code (optional)", text: $label)
                    .textFieldStyle(.roundedBorder)

                Button(appState.isLoading ? "Saving…" : "Save Code") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(appState.isLoading)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Add Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if let onBack {
                        Button("Back") { onBack() }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private func save() async {
        errorMessage = nil
        do {
            try await appState.saveCode(code, label: label)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
