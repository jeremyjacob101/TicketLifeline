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
            QRCodeImage(payload: code.payload)
                .frame(width: 54, height: 54)
                .padding(5)
                .background(.white, in: RoundedRectangle(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).stroke(.quaternary) }
            VStack(alignment: .leading, spacing: 4) {
                Text(code.label).font(.headline)
                Text(code.payload).lineLimit(1).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct CodeDetailView: View {
    let code: SavedCode

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                QRCodeImage(payload: code.payload)
                    .frame(width: 280, height: 280)
                    .padding(18)
                    .background(.white, in: RoundedRectangle(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                VStack(spacing: 8) {
                    Text(code.label).font(.title2.bold())
                    Text(code.createdAt, format: .dateTime.month().day().year().hour().minute())
                        .font(.footnote).foregroundStyle(.secondary)
                }
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
        .navigationTitle("QR Code")
        .navigationBarTitleDisplayMode(.inline)
    }
}
