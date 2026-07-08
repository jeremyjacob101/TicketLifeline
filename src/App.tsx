import { useAuthActions } from "@convex-dev/auth/react";
import { useConvexAuth, useMutation, useQuery } from "convex/react";
import {
  AlertCircle,
  ArrowUpRight,
  Check,
  Copy,
  Grid2X2,
  ImageUp,
  KeyRound,
  LockKeyhole,
  LogOut,
  Plus,
  QrCode,
  Search,
  ShieldCheck,
  Trash2,
} from "lucide-react";
import { FormEvent, useEffect, useMemo, useRef, useState } from "react";
import JsBarcode from "jsbarcode";
import QRCode from "qrcode";
import { api } from "../convex/_generated/api";
import type { Doc, Id } from "../convex/_generated/dataModel";
import type { DragEvent } from "react";

type Pass = Doc<"passes">;
type CodeType = "qr" | "barcode";
type Draft = {
  title: string;
  issuer: string;
  codeType: CodeType;
  format: string;
  encodedValue: string;
  eventDate: string;
  notes: string;
  color: string;
};

const accentColors = ["#0f766e", "#2563eb", "#7c3aed", "#c2410c"];
const emptyDraft: Draft = {
  title: "",
  issuer: "",
  codeType: "qr",
  format: "QR_CODE",
  encodedValue: "",
  eventDate: "",
  notes: "",
  color: accentColors[0],
};

export default function App() {
  const { isAuthenticated, isLoading } = useConvexAuth();

  if (isLoading) {
    return <ShellLoading />;
  }

  if (!isAuthenticated) {
    return <AuthScreen />;
  }

  return <VaultApp />;
}

function ShellLoading() {
  return (
    <main className="setup-screen">
      <section className="setup-panel compact">
        <p className="setup-mark">TicketLifeline</p>
        <h1>Opening your vault...</h1>
      </section>
    </main>
  );
}

function AuthScreen() {
  const { signIn } = useAuthActions();
  const [mode, setMode] = useState<"signIn" | "signUp">("signIn");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setIsSubmitting(true);
    try {
      await signIn("password", { username, password, flow: mode });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not sign in.");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <main className="auth-screen">
      <section className="auth-copy">
        <div className="brand-row">
          <span className="brand-icon">
            <QrCode size={22} />
          </span>
          <span>TicketLifeline</span>
        </div>
        <h1>Your QR and barcode safety net.</h1>
        <p>
          Save the encoded value behind tickets, coupons, passes, and backup
          codes. No screenshot storage required.
        </p>
        <div className="assurance-row">
          <ShieldCheck size={18} />
          <span>Per-user vault with lightweight Convex records.</span>
        </div>
      </section>

      <section className="auth-card">
        <div className="auth-card-header">
          <LockKeyhole size={20} />
          <div>
            <h2>{mode === "signIn" ? "Sign in" : "Create account"}</h2>
            <p>Use a username and password for this first version.</p>
          </div>
        </div>
        <form onSubmit={handleSubmit} className="auth-form">
          <label>
            Username
            <input
              type="text"
              value={username}
              onChange={(event) => setUsername(event.target.value)}
              autoComplete="username"
              required
            />
          </label>
          <label>
            Password
            <input
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              autoComplete={mode === "signIn" ? "current-password" : "new-password"}
              required
            />
          </label>
          {error ? <p className="form-error">{error}</p> : null}
          <button type="submit" className="primary-button" disabled={isSubmitting}>
            <KeyRound size={16} />
            {isSubmitting
              ? "Working..."
              : mode === "signIn"
                ? "Sign in"
                : "Create vault"}
          </button>
        </form>
        <button
          type="button"
          className="text-button"
          onClick={() => setMode((value) => (value === "signIn" ? "signUp" : "signIn"))}
        >
          {mode === "signIn" ? "Need an account?" : "Already have an account?"}
        </button>
      </section>
    </main>
  );
}

function VaultApp() {
  const { signOut } = useAuthActions();
  const passes = useQuery(api.passes.list);
  const createPass = useMutation(api.passes.create);
  const removePass = useMutation(api.passes.remove);
  const markOpened = useMutation(api.passes.markOpened);
  const [query, setQuery] = useState("");
  const [selectedId, setSelectedId] = useState<Id<"passes"> | null>(null);
  const [draft, setDraft] = useState<Draft>(emptyDraft);
  const [decodeState, setDecodeState] = useState<"idle" | "decoding" | "success" | "error">("idle");
  const [decodeMessage, setDecodeMessage] = useState("");
  const [isDragActive, setIsDragActive] = useState(false);

  const passList = passes ?? [];
  const filteredPasses = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return passList;
    return passList.filter((pass) =>
      [pass.title, pass.issuer, pass.format, pass.encodedValue, pass.notes]
        .filter(Boolean)
        .some((value) => value!.toLowerCase().includes(needle)),
    );
  }, [passList, query]);

  const selectedPass =
    filteredPasses.find((pass) => pass._id === selectedId) ??
    filteredPasses[0] ??
    null;

  useEffect(() => {
    if (selectedPass) {
      void markOpened({ id: selectedPass._id });
      setSelectedId(selectedPass._id);
    }
  }, [markOpened, selectedPass?._id]);

  async function handleCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!draft.encodedValue.trim()) {
      setDecodeState("error");
      setDecodeMessage("Add a decoded payload or paste the code value.");
      return;
    }

    const id = await createPass({
      title: draft.title || "Untitled pass",
      issuer: draft.issuer || undefined,
      codeType: draft.codeType,
      format: draft.format || undefined,
      encodedValue: draft.encodedValue.trim(),
      eventDate: draft.eventDate || undefined,
      notes: draft.notes || undefined,
      color: draft.color,
    });
    setDraft({ ...emptyDraft, color: draft.color });
    setSelectedId(id);
    setDecodeState("success");
    setDecodeMessage("Saved as a lightweight code payload.");
  }

  async function handleFile(file: File | null) {
    if (!file) return;
    setDecodeState("decoding");
    setDecodeMessage(
      isHeicImage(file)
        ? "Converting HEIC locally, then reading the code..."
        : "Reading the code in your browser...",
    );
    try {
      const result = await decodeBarcodeFromImage(file);
      setDraft((current) => ({
        ...current,
        codeType: result.codeType,
        format: result.format,
        encodedValue: result.rawValue,
        title: current.title || file.name.replace(/\.[^.]+$/, ""),
      }));
      setDecodeState("success");
      setDecodeMessage(
        isHeicImage(file)
          ? "Converted and decoded locally. The image was not uploaded or stored."
          : "Decoded. The image was not uploaded or stored.",
      );
    } catch (err) {
      setDecodeState("error");
      setDecodeMessage(
        err instanceof Error
          ? err.message
          : "Could not read that screenshot. Paste the payload manually.",
      );
    }
  }

  async function handleDrop(event: DragEvent<HTMLLabelElement>) {
    event.preventDefault();
    setIsDragActive(false);
    try {
      const file = await getDroppedImageFile(event.dataTransfer);
      await handleFile(file);
    } catch (err) {
      setDecodeState("error");
      setDecodeMessage(
        err instanceof Error
          ? err.message
          : "Drop an image file or paste the payload manually.",
      );
    }
  }

  return (
    <main className="app-shell">
      <aside className="side-rail">
        <div className="brand-row small">
          <span className="brand-icon">
            <QrCode size={20} />
          </span>
          <span>TicketLifeline</span>
        </div>
        <nav className="rail-nav" aria-label="Primary">
          <a className="active" href="#vault">
            <Grid2X2 size={17} />
            Vault
          </a>
          <a href="#add-pass">
            <Plus size={17} />
            Add pass
          </a>
        </nav>
        <div className="rail-footer">
          <div>
            <p>Emergency copy</p>
            <span>Codes regenerate on any device.</span>
          </div>
          <button type="button" className="icon-button" onClick={() => void signOut()}>
            <LogOut size={17} />
            <span className="sr-only">Sign out</span>
          </button>
        </div>
      </aside>

      <section className="vault-column" id="vault">
        <header className="top-bar">
          <div>
            <h1>Vault</h1>
            <p>{passList.length} saved passes</p>
          </div>
          <div className="search-field">
            <Search size={17} />
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search passes"
            />
          </div>
        </header>

        <section className="add-panel" id="add-pass">
          <div className="panel-heading">
            <ImageUp size={18} />
            <div>
              <h2>Add pass</h2>
              <p>Drop an iPhone screenshot here, choose a file, or paste the payload.</p>
            </div>
          </div>
          <form className="pass-form" onSubmit={handleCreate}>
            <label
              className={`upload-target ${isDragActive ? "drag-active" : ""}`}
              onDragEnter={(event) => {
                event.preventDefault();
                setIsDragActive(true);
              }}
              onDragOver={(event) => {
                event.preventDefault();
                event.dataTransfer.dropEffect = "copy";
                setIsDragActive(true);
              }}
              onDragLeave={(event) => {
                event.preventDefault();
                const nextTarget = event.relatedTarget;
                if (
                  !(nextTarget instanceof Node) ||
                  !event.currentTarget.contains(nextTarget)
                ) {
                  setIsDragActive(false);
                }
              }}
              onDrop={(event) => void handleDrop(event)}
            >
              <input
                type="file"
                accept="image/*,.heic,.heif,image/heic,image/heif"
                onChange={(event) => {
                  void handleFile(event.target.files?.[0] ?? null);
                  event.currentTarget.value = "";
                }}
              />
              <ImageUp size={20} />
              <span>{isDragActive ? "Drop screenshot" : "Drop or choose screenshot"}</span>
              <small>Supports PNG, JPG, HEIC, and HEIF. Nothing is uploaded.</small>
            </label>
            <div className="field-grid">
              <label>
                Ticket title
                <input
                  value={draft.title}
                  onChange={(event) => setDraft({ ...draft, title: event.target.value })}
                  placeholder="Train home"
                />
              </label>
              <label>
                Issuer
                <input
                  value={draft.issuer}
                  onChange={(event) => setDraft({ ...draft, issuer: event.target.value })}
                  placeholder="Airline, venue, transit"
                />
              </label>
              <label>
                Date
                <input
                  type="date"
                  value={draft.eventDate}
                  onChange={(event) => setDraft({ ...draft, eventDate: event.target.value })}
                />
              </label>
              <label>
                Type
                <select
                  value={draft.codeType}
                  onChange={(event) =>
                    setDraft({
                      ...draft,
                      codeType: event.target.value as CodeType,
                      format: event.target.value === "qr" ? "QR_CODE" : "CODE_128",
                    })
                  }
                >
                  <option value="qr">QR code</option>
                  <option value="barcode">Barcode</option>
                </select>
              </label>
            </div>
            <label>
              Encoded value
              <textarea
                value={draft.encodedValue}
                onChange={(event) => setDraft({ ...draft, encodedValue: event.target.value })}
                placeholder="Paste the QR/barcode payload here"
                rows={3}
              />
            </label>
            <label>
              Notes
              <input
                value={draft.notes}
                onChange={(event) => setDraft({ ...draft, notes: event.target.value })}
                placeholder="Gate, seat, confirmation number"
              />
            </label>
            <div className="form-footer">
              <div className={`decode-status ${decodeState}`}>
                {decodeState === "success" ? <Check size={15} /> : <AlertCircle size={15} />}
                <span>{decodeMessage || "Screenshots are decoded locally, then discarded."}</span>
              </div>
              <button type="submit" className="primary-button">
                <Plus size={16} />
                Save pass
              </button>
            </div>
          </form>
        </section>

        <section className="pass-list" aria-label="Recent passes">
          <div className="section-title">
            <h2>Recent passes</h2>
            <span>{filteredPasses.length}</span>
          </div>
          {passes === undefined ? (
            <p className="muted-row">Loading passes...</p>
          ) : filteredPasses.length ? (
            filteredPasses.map((pass) => (
              <button
                key={pass._id}
                type="button"
                className={`pass-row ${selectedPass?._id === pass._id ? "selected" : ""}`}
                onClick={() => setSelectedId(pass._id)}
              >
                <span className="pass-swatch" style={{ background: pass.color ?? "#0f766e" }} />
                <span>
                  <strong>{pass.title}</strong>
                  <small>{pass.issuer || pass.format || "Saved code"}</small>
                </span>
                <ArrowUpRight size={16} />
              </button>
            ))
          ) : (
            <p className="muted-row">No passes yet. Add the first one above.</p>
          )}
        </section>
      </section>

      <aside className="detail-pane">
        {selectedPass ? (
          <PassDetail
            pass={selectedPass}
            onDelete={() => void removePass({ id: selectedPass._id })}
          />
        ) : (
          <div className="empty-detail">
            <QrCode size={40} />
            <h2>No pass selected</h2>
            <p>Add a pass and the regenerated code will appear here.</p>
          </div>
        )}
      </aside>
    </main>
  );
}

function PassDetail({ pass, onDelete }: { pass: Pass; onDelete: () => void }) {
  const [copied, setCopied] = useState(false);

  async function copyValue() {
    await navigator.clipboard.writeText(pass.encodedValue);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1600);
  }

  return (
    <div className="detail-content">
      <div className="detail-header">
        <span className="pass-swatch large" style={{ background: pass.color ?? "#0f766e" }} />
        <div>
          <h2>{pass.title}</h2>
          <p>{pass.issuer || "Saved pass"}</p>
        </div>
      </div>
      <CodeRender pass={pass} />
      <dl className="meta-list">
        <div>
          <dt>Format</dt>
          <dd>{pass.format || (pass.codeType === "qr" ? "QR_CODE" : "CODE_128")}</dd>
        </div>
        <div>
          <dt>Date</dt>
          <dd>{pass.eventDate || "Anytime"}</dd>
        </div>
        <div>
          <dt>Notes</dt>
          <dd>{pass.notes || "No notes"}</dd>
        </div>
      </dl>
      <div className="payload-box">
        <span>{pass.encodedValue}</span>
      </div>
      <div className="detail-actions">
        <button type="button" className="primary-button" onClick={() => void copyValue()}>
          {copied ? <Check size={16} /> : <Copy size={16} />}
          {copied ? "Copied" : "Emergency copy"}
        </button>
        <button type="button" className="danger-button" onClick={onDelete}>
          <Trash2 size={16} />
          Delete
        </button>
      </div>
    </div>
  );
}

function CodeRender({ pass }: { pass: Pass }) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const svgRef = useRef<SVGSVGElement | null>(null);
  const [renderError, setRenderError] = useState("");

  useEffect(() => {
    setRenderError("");
    if (pass.codeType === "qr" && canvasRef.current) {
      QRCode.toCanvas(canvasRef.current, pass.encodedValue, {
        margin: 2,
        width: 280,
        color: { dark: "#111827", light: "#ffffff" },
      }).catch(() => setRenderError("Could not render this QR payload."));
    }

    if (pass.codeType === "barcode" && svgRef.current) {
      try {
        JsBarcode(svgRef.current, pass.encodedValue, {
          format: "CODE128",
          width: 2,
          height: 96,
          margin: 16,
          displayValue: false,
          lineColor: "#111827",
        });
      } catch {
        setRenderError("Could not render this barcode payload.");
      }
    }
  }, [pass.codeType, pass.encodedValue]);

  return (
    <div className="code-frame">
      {pass.codeType === "qr" ? (
        <canvas ref={canvasRef} aria-label="Regenerated QR code" />
      ) : (
        <svg ref={svgRef} aria-label="Regenerated barcode" />
      )}
      {renderError ? <p className="form-error">{renderError}</p> : null}
    </div>
  );
}

async function decodeBarcodeFromImage(file: File): Promise<{
  rawValue: string;
  format: string;
  codeType: CodeType;
}> {
  if (!("BarcodeDetector" in window)) {
    throw new Error("This browser cannot decode screenshots yet. Paste the payload manually.");
  }

  const detector = new window.BarcodeDetector({
    formats: [
      "qr_code",
      "aztec",
      "code_128",
      "code_39",
      "code_93",
      "codabar",
      "data_matrix",
      "ean_13",
      "ean_8",
      "itf",
      "pdf417",
      "upc_a",
      "upc_e",
    ],
  });

  const imageFile = await normalizeImageFile(file);
  const image = await loadImage(imageFile);
  const results = await detector.detect(image);
  if (!results.length || !results[0].rawValue) {
    throw new Error("No QR or barcode was found. Try a clearer screenshot or paste the value.");
  }

  const format = results[0].format.toUpperCase();
  return {
    rawValue: results[0].rawValue,
    format,
    codeType: results[0].format === "qr_code" ? "qr" : "barcode",
  };
}

function loadImage(file: File | Blob) {
  return new Promise<HTMLImageElement>((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const image = new Image();
    image.onload = () => {
      URL.revokeObjectURL(url);
      resolve(image);
    };
    image.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("Could not load that image."));
    };
    image.src = url;
  });
}

async function normalizeImageFile(file: File): Promise<File | Blob> {
  if (!isHeicImage(file)) {
    return file;
  }

  try {
    const { default: heic2any } = await import("heic2any");
    const converted = await heic2any({
      blob: file,
      toType: "image/jpeg",
      quality: 0.96,
    });
    const blob = Array.isArray(converted) ? converted[0] : converted;
    if (!blob) {
      throw new Error("HEIC conversion returned no image.");
    }
    return blob;
  } catch {
    throw new Error(
      "Could not convert that HEIC/HEIF image in this browser. Try exporting it as JPEG/PNG, or paste the code payload manually.",
    );
  }
}

function isHeicImage(file: File | Blob) {
  const type = file.type.toLowerCase();
  const name = "name" in file ? file.name.toLowerCase() : "";
  return (
    type === "image/heic" ||
    type === "image/heif" ||
    name.endsWith(".heic") ||
    name.endsWith(".heif")
  );
}

async function getDroppedImageFile(dataTransfer: DataTransfer): Promise<File> {
  const droppedFile = firstImageFile(dataTransfer.files);
  if (droppedFile) {
    return droppedFile;
  }

  for (const item of Array.from(dataTransfer.items)) {
    if (item.kind !== "file") continue;
    const file = item.getAsFile();
    if (file && isSupportedImageLike(file)) {
      return file;
    }
  }

  const droppedUrl =
    dataTransfer.getData("text/uri-list").split("\n").find((line) => line && !line.startsWith("#")) ||
    dataTransfer.getData("text/plain");

  if (droppedUrl && /^https?:\/\//i.test(droppedUrl)) {
    try {
      const response = await fetch(droppedUrl);
      const blob = await response.blob();
      if (isSupportedImageLike(blob)) {
        return new File([blob], filenameFromUrl(droppedUrl, blob.type), {
          type: blob.type,
        });
      }
    } catch {
      throw new Error("That dropped image URL could not be read by the browser.");
    }
  }

  throw new Error("Drop a PNG, JPG, HEIC, or HEIF screenshot.");
}

function firstImageFile(files: FileList) {
  return Array.from(files).find(isSupportedImageLike) ?? null;
}

function isSupportedImageLike(file: File | Blob) {
  const type = file.type.toLowerCase();
  const name = "name" in file ? file.name.toLowerCase() : "";
  return (
    type.startsWith("image/") ||
    name.endsWith(".heic") ||
    name.endsWith(".heif") ||
    name.endsWith(".jpg") ||
    name.endsWith(".jpeg") ||
    name.endsWith(".png") ||
    name.endsWith(".webp")
  );
}

function filenameFromUrl(url: string, fallbackType: string) {
  try {
    const pathname = new URL(url).pathname;
    const name = pathname.split("/").filter(Boolean).at(-1);
    if (name) return name;
  } catch {
    // Fall through to a MIME-based fallback.
  }
  return fallbackType.includes("png") ? "dropped-image.png" : "dropped-image.jpg";
}
