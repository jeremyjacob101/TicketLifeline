import { useAuthActions } from "@convex-dev/auth/react";
import { useMutation, useQuery } from "convex/react";
import {
  AlertCircle,
  ArrowUpRight,
  Check,
  Grid2X2,
  ImageUp,
  LogOut,
  Plus,
  QrCode,
  Search,
  Trash2,
  X,
} from "lucide-react";
import { FormEvent, useEffect, useMemo, useState } from "react";
import type { DragEvent } from "react";
import { api } from "@ticketlifeline/convex-api";
import type { Id } from "@ticketlifeline/convex-data-model";
import type { CodeType, Pass } from "./types";
import {
  getDroppedImageFile,
  inferLaunchUrlFromPayload,
  isHeicImage,
  normalizeLaunchUrl,
} from "./utils";
import { decodeBarcodeFromImage } from "./barcode";
import { PassDetail } from "./PassDetail";

type Draft = {
  title: string;
  issuer: string;
  codeType: CodeType;
  format: string;
  encodedValue: string;
  launchUrl: string;
  visualMatrix: string;
  visualSize: number | undefined;
  eventDate: string;
  notes: string;
  color: string;
};

const accentColors = ["#0f766e", "#2563eb", "#7c3aed", "#c2410c"];

function formatDate(timestamp: number) {
  const d = new Date(timestamp);
  const day = String(d.getDate()).padStart(2, "0");
  const month = String(d.getMonth() + 1).padStart(2, "0");
  const year = String(d.getFullYear()).slice(2);
  const hours = String(d.getHours()).padStart(2, "0");
  const mins = String(d.getMinutes()).padStart(2, "0");
  return `${day}/${month}/${year} - ${hours}:${mins}`;
}
const privacyPolicyUrl =
  "https://github.com/jeremyjacob101/TicketLifeline/blob/main/PRIVACY.md";
const emptyDraft: Draft = {
  title: "",
  issuer: "",
  codeType: "qr",
  format: "QR_CODE",
  encodedValue: "",
  launchUrl: "",
  visualMatrix: "",
  visualSize: undefined,
  eventDate: "",
  notes: "",
  color: accentColors[0],
};

export function VaultApp() {
  const { signOut } = useAuthActions();
  const passes = useQuery(api.passes.list);
  const createPass = useMutation(api.passes.create);
  const updatePass = useMutation(api.passes.update);
  const removePass = useMutation(api.passes.remove);
  const markOpened = useMutation(api.passes.markOpened);
  const deleteAccount = useMutation(api.users.deleteAccount);
  const [query, setQuery] = useState("");
  const [selectedId, setSelectedId] = useState<Id<"passes"> | null>(null);
  const [draft, setDraft] = useState<Draft>(emptyDraft);
  const [decodeState, setDecodeState] = useState<"idle" | "decoding" | "success" | "error">("idle");
  const [decodeMessage, setDecodeMessage] = useState("");
  const [isDragActive, setIsDragActive] = useState(false);
  const [isAddOpen, setIsAddOpen] = useState(false);
  const [isDetailOpen, setIsDetailOpen] = useState(false);
  const [isDeleteOpen, setIsDeleteOpen] = useState(false);
  const [isDeletingAccount, setIsDeletingAccount] = useState(false);
  const [deleteError, setDeleteError] = useState("");

  const passList = passes ?? [];
  const filteredPasses = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return passList;
    return passList.filter((pass) =>
      [pass.title, pass.issuer, pass.format, pass.encodedValue, pass.launchUrl, pass.notes]
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
      if (!selectedId) {
        setSelectedId(selectedPass._id);
        setIsDetailOpen(true);
      }
    }
  }, [markOpened, selectedId, selectedPass?._id]);

  async function handleCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!draft.encodedValue.trim()) {
      setDecodeState("error");
      setDecodeMessage("Add a decoded payload or paste the code value.");
      return;
    }
    const launchUrl = draft.codeType === "qr" ? normalizeLaunchUrl(draft.launchUrl) : "";
    if (draft.codeType === "qr" && draft.launchUrl.trim() && !launchUrl) {
      setDecodeState("error");
      setDecodeMessage("Use a valid http:// or https:// URL for camera scanning.");
      return;
    }

    const id = await createPass({
      title: draft.title || "Untitled pass",
      issuer: draft.issuer || undefined,
      codeType: draft.codeType,
      format: draft.format || undefined,
      encodedValue: draft.encodedValue.trim(),
      launchUrl: launchUrl || undefined,
      visualMatrix: draft.visualMatrix || undefined,
      visualSize: draft.visualSize,
      eventDate: draft.eventDate || undefined,
      notes: draft.notes || undefined,
      color: draft.color,
    });
    setDraft({ ...emptyDraft, color: draft.color });
    setSelectedId(id);
    setIsAddOpen(false);
    setIsDetailOpen(true);
    setDecodeState("success");
    setDecodeMessage(
      launchUrl
        ? "Saved the payload. Phone-camera scans will open the URL."
        : "Saved the payload and compact digital QR pattern.",
    );
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
      const inferredLaunchUrl =
        result.codeType === "qr" ? inferLaunchUrlFromPayload(result.rawValue) : "";
      setDraft((current) => ({
        ...current,
        codeType: result.codeType,
        format: result.format,
        encodedValue: result.rawValue,
        launchUrl: current.launchUrl || inferredLaunchUrl,
        visualMatrix: result.visualMatrix,
        visualSize: result.visualSize,
        title: current.title || file.name.replace(/\.[^.]+$/, ""),
      }));
      const scanMessage = inferredLaunchUrl ? " Found a web URL for camera scanning." : "";
      setDecodeState("success");
      setDecodeMessage(
        isHeicImage(file)
          ? result.visualMatrix
            ? `Converted locally and matched the photographed QR pattern.${scanMessage}`
            : `Converted locally. Saved a clean generated code from the payload.${scanMessage}`
          : result.visualMatrix
            ? `Decoded locally and matched the photographed QR pattern.${scanMessage}`
            : `Decoded locally. Saved a clean generated code from the payload.${scanMessage}`,
      );
      setIsAddOpen(true);
    } catch (err) {
      setDecodeState("error");
      setDecodeMessage(
        err instanceof Error
          ? err.message
          : "Could not read that image. Paste the payload manually.",
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

  async function handleDeleteAccount() {
    setDeleteError("");
    setIsDeletingAccount(true);
    try {
      await deleteAccount({});
      await signOut();
    } catch (err) {
      setDeleteError(err instanceof Error ? err.message : "Could not delete your account.");
      setIsDeletingAccount(false);
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
            <span>Stored QR patterns open on any device.</span>
          </div>
          <div className="rail-account-actions">
            <a href={privacyPolicyUrl} target="_blank" rel="noreferrer">
              Privacy
            </a>
            <button type="button" className="delete-account-link" onClick={() => setIsDeleteOpen(true)}>
              <Trash2 size={14} />
              Delete account
            </button>
            <button type="button" className="icon-button" onClick={() => void signOut()}>
              <LogOut size={17} />
              <span className="sr-only">Sign out</span>
            </button>
          </div>
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

        <section className="pass-list" aria-label="Recent passes">
          <div className="section-title">
            <div>
              <h2>Recent passes</h2>
              <p>Most recent first</p>
            </div>
            <span>{filteredPasses.length}</span>
          </div>
          {passes === undefined ? (
            <p className="muted-row">Loading passes...</p>
          ) : filteredPasses.length ? (
            filteredPasses.map((pass) => (
              <div key={pass._id} className="pass-row-wrapper">
                <button
                  type="button"
                  className={`pass-row ${selectedPass?._id === pass._id ? "selected" : ""}`}
                  onClick={() => {
                    setSelectedId(pass._id);
                    setIsDetailOpen(true);
                  }}
                >
                  <span className="pass-swatch" style={{ background: pass.color ?? "#0f766e" }} />
                  <span>
                    <strong>{pass.title}</strong>
                    <small>{formatDate(pass.createdAt)}</small>
                  </span>
                  <ArrowUpRight size={16} />
                </button>
                <button
                  type="button"
                  className="pass-row-delete"
                  onClick={() => void removePass({ id: pass._id })}
                  aria-label={`Delete ${pass.title}`}
                >
                  <Trash2 size={14} />
                </button>
              </div>
            ))
          ) : (
            <p className="muted-row">No passes yet. Add the first one on the right.</p>
          )}
        </section>
      </section>

      <aside className="add-rail" id="add-pass">
        <div className="add-rail-heading">
          <div className="add-rail-icon"><Plus size={18} /></div>
          <div>
            <h2>Add new</h2>
            <p>Drop a ticket image to save it.</p>
          </div>
        </div>
        <label
          className={`upload-target add-drop-target ${isDragActive ? "drag-active" : ""}`}
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
            if (!(nextTarget instanceof Node) || !event.currentTarget.contains(nextTarget)) {
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
          <ImageUp size={24} />
          <span>{isDragActive ? "Drop image here" : "Drop or choose"}</span>
          <small>PNG, JPG, HEIC, or HEIF</small>
        </label>
        <div className={`decode-status add-status ${decodeState}`} aria-live="polite">
          {decodeState === "success" ? <Check size={15} /> : decodeState === "error" ? <AlertCircle size={15} /> : null}
          <span>{decodeMessage || "Your ticket details will appear after the code is read."}</span>
        </div>
      </aside>

      {isAddOpen ? (
        <AddPassDialog
          draft={draft}
          decodeState={decodeState}
          decodeMessage={decodeMessage}
          onDraftChange={setDraft}
          onSubmit={handleCreate}
          onCancel={() => setIsAddOpen(false)}
        />
      ) : null}

      {isDetailOpen && selectedPass ? (
        <div className="dialog-backdrop" role="presentation" onMouseDown={() => setIsDetailOpen(false)}>
          <section
            className="pass-dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="pass-dialog-title"
            onMouseDown={(event) => event.stopPropagation()}
          >
            <button type="button" className="modal-close" onClick={() => setIsDetailOpen(false)} aria-label="Close pass details">
              <X size={18} />
            </button>
            <div id="pass-dialog-title" className="sr-only">Pass details</div>
            <PassDetail
              pass={selectedPass}
              onDelete={() => {
                setIsDetailOpen(false);
                void removePass({ id: selectedPass._id });
              }}
              onUpdate={(fields) => {
                void updatePass({
                  id: selectedPass._id,
                  title: fields.title || "Untitled pass",
                  issuer: fields.issuer || undefined,
                  codeType: selectedPass.codeType,
                  format: selectedPass.format || undefined,
                  encodedValue: selectedPass.encodedValue,
                  launchUrl: fields.launchUrl || undefined,
                  visualMatrix: selectedPass.visualMatrix || undefined,
                  visualSize: selectedPass.visualSize,
                  eventDate: fields.eventDate || undefined,
                  notes: fields.notes || undefined,
                  color: selectedPass.color ?? "#0f766e",
                });
              }}
            />
          </section>
        </div>
      ) : null}

      <DeleteAccountDialog
        isOpen={isDeleteOpen}
        isDeleting={isDeletingAccount}
        error={deleteError}
        onCancel={() => {
          setIsDeleteOpen(false);
          setDeleteError("");
        }}
        onConfirm={() => void handleDeleteAccount()}
      />
    </main>
  );
}

type AddPassDialogProps = {
  draft: Draft;
  decodeState: "idle" | "decoding" | "success" | "error";
  decodeMessage: string;
  onDraftChange: (draft: Draft) => void;
  onSubmit: (event: FormEvent<HTMLFormElement>) => void;
  onCancel: () => void;
};

function AddPassDialog({ draft, decodeState, decodeMessage, onDraftChange, onSubmit, onCancel }: AddPassDialogProps) {
  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={onCancel}>
      <section className="pass-dialog add-dialog" role="dialog" aria-modal="true" aria-labelledby="add-dialog-title" onMouseDown={(event) => event.stopPropagation()}>
        <button type="button" className="modal-close" onClick={onCancel} aria-label="Close add pass dialog">
          <X size={18} />
        </button>
        <div className="modal-heading">
          <div className="add-rail-icon"><Plus size={18} /></div>
          <div>
            <h2 id="add-dialog-title">Add pass details</h2>
            <p>The code was read locally. Add a few details before saving.</p>
          </div>
        </div>
        <form className="pass-form" onSubmit={onSubmit}>
          <div className="field-grid">
            <label>
              Ticket title
              <input value={draft.title} onChange={(event) => onDraftChange({ ...draft, title: event.target.value })} placeholder="Train home" autoFocus />
            </label>
            <label>
              Issuer
              <input value={draft.issuer} onChange={(event) => onDraftChange({ ...draft, issuer: event.target.value })} placeholder="Airline, venue, transit" />
            </label>
            <label>
              Date
              <input type="date" value={draft.eventDate} onChange={(event) => onDraftChange({ ...draft, eventDate: event.target.value })} />
            </label>
            <label>
              Type
              <select value={draft.codeType} onChange={(event) => onDraftChange({ ...draft, codeType: event.target.value as CodeType, format: event.target.value === "qr" ? "QR_CODE" : "CODE_128" })}>
                <option value="qr">QR code</option>
                <option value="barcode">Barcode</option>
              </select>
            </label>
          </div>
          <label>
            Encoded value
            <textarea value={draft.encodedValue} onChange={(event) => onDraftChange({ ...draft, encodedValue: event.target.value, launchUrl: draft.launchUrl || inferLaunchUrlFromPayload(event.target.value) })} rows={3} />
          </label>
          {draft.codeType === "qr" ? (
            <label>
              Opens when scanned
              <input value={draft.launchUrl} onChange={(event) => onDraftChange({ ...draft, launchUrl: event.target.value })} placeholder="https://example.com/ticket" />
            </label>
          ) : null}
          <label>
            Notes
            <input value={draft.notes} onChange={(event) => onDraftChange({ ...draft, notes: event.target.value })} placeholder="Gate, seat, confirmation number" />
          </label>
          <div className="form-footer">
            <div className={`decode-status ${decodeState}`}>
              {decodeState === "success" ? <Check size={15} /> : <AlertCircle size={15} />}
              <span>{decodeMessage || "Photos are decoded locally."}</span>
            </div>
            <button type="submit" className="primary-button"><Plus size={16} />Save pass</button>
          </div>
        </form>
      </section>
    </div>
  );
}

type DeleteAccountDialogProps = {
  isOpen: boolean;
  isDeleting: boolean;
  error: string;
  onCancel: () => void;
  onConfirm: () => void;
};

function DeleteAccountDialog({
  isOpen,
  isDeleting,
  error,
  onCancel,
  onConfirm,
}: DeleteAccountDialogProps) {
  if (!isOpen) return null;

  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={isDeleting ? undefined : onCancel}>
      <section
        className="delete-account-dialog"
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="delete-account-title"
        aria-describedby="delete-account-description"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <span className="dialog-icon" aria-hidden="true">
          <Trash2 size={22} />
        </span>
        <div>
          <h2 id="delete-account-title">Permanently delete your account?</h2>
          <p id="delete-account-description">
            This removes your TicketLifeline account, every saved QR code and barcode,
            and all active sessions across web and iOS. This cannot be undone.
          </p>
        </div>
        {error ? <p className="form-error">{error}</p> : null}
        <div className="dialog-actions">
          <button type="button" className="text-button" onClick={onCancel} disabled={isDeleting}>
            Keep account
          </button>
          <button type="button" className="danger-button" onClick={onConfirm} disabled={isDeleting}>
            {isDeleting ? "Deleting everything..." : "Delete account permanently"}
          </button>
        </div>
      </section>
    </div>
  );
}
