import { useConvexAuth } from "convex/react";
import QRCode from "qrcode";
import { useState } from "react";
import { AuthScreen, ShellLoading } from "./AuthScreen";
import { decodeBarcodeFromImage, matrixToString } from "./barcode";
import { CodeRender } from "./CodeRender";
import type { Pass } from "./types";
import { VaultApp } from "./VaultApp";

export default function App() {
  const searchParams = new URLSearchParams(window.location.search);
  const preview = searchParams.get("artPreview");
  if (import.meta.env.DEV && preview !== null) {
    if (preview === "import") return <ImportPreview />;
    return <ArtPreview variant={preview || "qr"} />;
  }
  const authPreview = searchParams.get("authPreview");
  if (import.meta.env.DEV && authPreview !== null) {
    const initialMode = authPreview === "signUp" || authPreview === "verify" ? authPreview : "signIn";
    return <AuthScreen initialMode={initialMode} initialEmail={initialMode === "verify" ? "person@example.com" : ""} />;
  }
  return <AuthenticatedApp />;
}

function ImportPreview() {
  const [result, setResult] = useState<Pass | null>(null);
  const [status, setStatus] = useState("Choose a QR image to exercise the complete browser verification path.");

  async function handleFile(file: File | null) {
    if (!file) return;
    setStatus("Reading and round-trip verifying locally…");
    setResult(null);
    try {
      const decoded = await decodeBarcodeFromImage(file);
      const size = decoded.visualSize;
      if (!size) throw new Error("The browser returned no verified matrix dimensions.");
      setResult({
        _id: "debug-import",
        _creationTime: Date.now(),
        ownerId: "debug-owner",
        title: "Verified Browser Import",
        codeType: decoded.codeType,
        format: decoded.format,
        encodedValue: decoded.rawValue,
        visualMatrix: decoded.visualMatrix,
        visualSize: size,
        visualWidth: size,
        visualHeight: size,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      } as unknown as Pass);
      setStatus(`Verified ${decoded.format} with ${size}×${size} preserved modules.`);
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Import verification failed.");
    }
  }

  return (
    <main className="setup-screen">
      <section className="setup-panel">
        <p className="setup-mark">TicketLifeline import QA</p>
        <h1>Browser verification</h1>
        <label>
          QR image
          <input type="file" accept="image/*,.heic,.heif" onChange={(event) => void handleFile(event.target.files?.[0] ?? null)} />
        </label>
        <p aria-live="polite">{status}</p>
        {result ? <CodeRender pass={result} /> : null}
      </section>
    </main>
  );
}

function AuthenticatedApp() {
  const { isAuthenticated, isLoading } = useConvexAuth();

  if (isLoading) {
    return <ShellLoading />;
  }

  if (!isAuthenticated) {
    return <AuthScreen />;
  }

  return <VaultApp />;
}

function ArtPreview({ variant }: { variant: string }) {
  const payload = "https://ticketlifeline.app/preview/cherry-blossom";
  const qr = QRCode.create(payload, { errorCorrectionLevel: "H" });
  const qrMatrix = matrixToString(qr.modules.data);
  const barcodeMatrix = "110100100001101100010010001101000100011011101011101100011101011";
  const rectangularMatrix = Array.from({ length: 12 }, (_, row) =>
    Array.from({ length: 34 }, (_, column) => ((row * 7 + column * 3) % 11 < 5 ? "1" : "0")).join(""),
  ).join("");
  const basePass = {
    _id: "debug-preview",
    _creationTime: Date.now(),
    ownerId: "debug-owner",
    title: "Cherry Blossom Preview",
    issuer: "TicketLifeline",
    encodedValue: payload,
    launchUrl: payload,
    color: "#8f3f5a",
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };
  const pass = {
    ...basePass,
    ...(variant === "barcode"
      ? {
          codeType: "barcode",
          format: "CODE_128",
          visualMatrix: barcodeMatrix,
          visualWidth: barcodeMatrix.length,
          visualHeight: 1,
        }
      : variant === "matrix"
        ? {
            codeType: "barcode",
            format: "PDF417",
            visualMatrix: rectangularMatrix,
            visualWidth: 34,
            visualHeight: 12,
          }
        : variant === "invalid"
          ? { codeType: "qr", format: "QR_CODE" }
          : {
              codeType: "qr",
              format: "QR_CODE",
              visualMatrix: qrMatrix,
              visualSize: qr.modules.size,
              visualWidth: qr.modules.size,
              visualHeight: qr.modules.size,
            }),
  } as unknown as Pass;
  const labels: Record<string, string> = {
    qr: "Colored QR/tree",
    barcode: "Barcode/cityscape",
    matrix: "Rectangular stacked symbol",
    invalid: "Legacy rescan gate",
  };

  return (
    <main className="setup-screen">
      <section className="setup-panel">
        <p className="setup-mark">TicketLifeline visual QA</p>
        <h1>{labels[variant] ?? labels.qr}</h1>
        <CodeRender pass={pass} />
        <p>{variant === "qr" || variant === "barcode" ? "Tap the code to test the artwork transition." : "Verify the safe static state."}</p>
      </section>
    </main>
  );
}
