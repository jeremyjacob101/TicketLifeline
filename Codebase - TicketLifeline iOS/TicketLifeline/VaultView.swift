import SwiftUI

struct VaultView: View {
    @ObservedObject var appState: AppState
    @State private var isShowingScanner = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.isLoading && appState.savedCodes.isEmpty {
                    ProgressView("Loading your QR codes...")
                } else if appState.savedCodes.isEmpty {
                    ContentUnavailableView {
                        Label("No QR codes yet", systemImage: "qrcode.viewfinder")
                    } description: {
                        Text("Scan a digital QR code to keep it handy here.")
                    } actions: {
                        Button("Scan QR Code") { isShowingScanner = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(appState.savedCodes) { code in
                        NavigationLink(value: code) {
                            CodeRow(code: code)
                        }
                    }
                }
            }
            .navigationTitle("My QR Codes")
            .navigationDestination(for: SavedCode.self) { code in
                CodeDetailView(code: code)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign Out") { appState.signOut() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isShowingScanner = true } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                    }
                }
            }
            .sheet(isPresented: $isShowingScanner) {
                ScanCodeView(appState: appState)
            }
            .refreshable { try? await appState.refreshCodes() }
            .task { try? await appState.refreshCodes() }
        }
    }
}

private struct CodeRow: View {
    let code: SavedCode

    var body: some View {
        HStack(spacing: 14) {
            CodeImage(code: code)
                .frame(width: 54, height: 54)
                .padding(5)
                .background(.white, in: RoundedRectangle(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).stroke(.quaternary) }
            VStack(alignment: .leading, spacing: 4) {
                Text(code.label).font(.headline)
                Text(code.format ?? (code.isBarcode ? "Barcode" : "QR Code"))
                    .lineLimit(1)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct CodeDetailView: View {
    let code: SavedCode
    @State private var displayMode: DisplayMode = .code

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Button {
                    displayMode = displayMode == .code ? .art : .code
                } label: {
                    Group {
                        if code.isBarcode {
                            BarcodeCityView(code: code, isFlat: displayMode == .code)
                        } else {
                            QRTreeMetalView(code: code, isFlat: displayMode == .code)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .accessibilityLabel(displayMode == .code ? (code.isBarcode ? "Scannable barcode" : "Scannable QR code") : (code.isBarcode ? "Barcode skyline" : "Cherry tree"))
                .accessibilityHint("Double tap to switch between the scannable code and its art view")
                VStack(spacing: 8) {
                    Text(code.label).font(.title2.bold())
                    Text(code.createdAt, format: .dateTime.month().day().year().hour().minute())
                        .font(.footnote).foregroundStyle(.secondary)
                }
                PassInfoCard(code: code)
                VStack(alignment: .leading, spacing: 8) {
                    Text("SCANNED VALUE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(code.payload).textSelection(.enabled).font(.body.monospaced())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(code.isBarcode ? "Barcode" : "QR Code")
        .navigationBarTitleDisplayMode(.inline)
    }

    private enum DisplayMode: Hashable { case code, art }
}

private struct CodeImage: View {
    let code: SavedCode

    var body: some View {
        if code.isBarcode {
            BarcodeImage(payload: code.payload)
        } else {
            QRCodeImage(payload: code.payload)
        }
    }
}

private struct PassInfoCard: View {
    let code: SavedCode

    var body: some View {
        VStack(spacing: 0) {
            InfoRow(label: "Type", value: code.isBarcode ? "Barcode" : "QR code")
            InfoRow(label: "Format", value: code.format ?? "Not available")
            InfoRow(label: "Issuer", value: code.issuer ?? "Not provided")
            InfoRow(label: "Pass date", value: code.eventDate ?? "Anytime")
            InfoRow(label: "Notes", value: code.notes ?? "No notes")
            if let launchURL = code.launchURL {
                InfoRow(label: "Scan link", value: launchURL)
            }
        }
        .padding(.horizontal)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider().opacity(label == "Scan link" ? 0 : 1) }
    }
}
