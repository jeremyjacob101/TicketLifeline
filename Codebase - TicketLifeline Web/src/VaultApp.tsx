import { useAuthActions } from "@convex-dev/auth/react";
import { useMutation, useQuery } from "convex/react";
import {
  AlertCircle,
  ArrowUpRight,
  Check,
  Grid2X2,
  ImageUp,
  LogOut,
  Menu,
  Plus,
  QrCode,
  Search,
  ShieldCheck,
  Trash2,
  X,
} from "lucide-react";
import { FormEvent, useEffect, useMemo, useState } from "react";
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
import { useDeviceType } from "./useDeviceType";

type Draft = {
  title: string;
  issuer: string;
  codeType: CodeType;
  format: string;
  encodedValue: string;
  payloadEncoding: "utf8" | "base64";
  launchUrl: string;
  visualMatrix: string;
  visualSize: number | undefined;
  visualWidth: number | undefined;
  visualHeight: number | undefined;
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

function preferredDateTimestamp(pass: Pass) {
  if (pass.eventDate) {
    const timestamp = Date.parse(`${pass.eventDate}T00:00:00`);
    if (!Number.isNaN(timestamp)) return timestamp;
  }
  return pass.createdAt;
}

function formatPreferredDate(pass: Pass) {
  if (pass.eventDate) {
    const [year, month, day] = pass.eventDate.split("-");
    if (year && month && day) return `${day}/${month}/${year.slice(2)}`;
  }
  return formatDate(pass.createdAt);
}
const privacyPolicyUrl =
  "https://github.com/jeremyjacob101/TicketLifeline/blob/main/PRIVACY.md";
const emptyDraft: Draft = {
  title: "",
  issuer: "",
  codeType: "qr",
  format: "QR_CODE",
  encodedValue: "",
  payloadEncoding: "utf8",
  launchUrl: "",
  visualMatrix: "",
  visualSize: undefined,
  visualWidth: undefined,
  visualHeight: undefined,
  eventDate: "",
  notes: "",
  color: accentColors[0],
};

export function VaultApp() {
  const { signOut } = useAuthActions();
  const deviceType = useDeviceType();
  const isMobile = deviceType === "mobile";
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
  const [isAddOpen, setIsAddOpen] = useState(false);
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const [isDetailOpen, setIsDetailOpen] = useState(false);
  const [isDeleteOpen, setIsDeleteOpen] = useState(false);
  const [isDeletingAccount, setIsDeletingAccount] = useState(false);
  const [deleteError, setDeleteError] = useState("");

  const passList = useMemo(
    () => [...(passes ?? [])].sort((a, b) => preferredDateTimestamp(b) - preferredDateTimestamp(a)),
    [passes],
  );
  const filteredPasses = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return passList;
    return passList.filter((pass) =>
      [pass.title, pass.issuer, pass.format, pass.encodedValue, pass.launchUrl, pass.notes]
        .filter(Boolean)
        .some((value) => value!.toLowerCase().includes(needle)),
    );
  }, [passList, query]);

  const selectedPass = selectedId
    ? filteredPasses.find((pass) => pass._id === selectedId) ?? null
    : filteredPasses[0] ?? null;

  useEffect(() => {
    if (selectedId && selectedPass) {
      void markOpened({ id: selectedPass._id });
    }
  }, [markOpened, selectedId, selectedPass?._id]);

  useEffect(() => {
    if (!isMobile) setIsMobileMenuOpen(false);
  }, [isMobile]);

  useEffect(() => {
    if (!isMobile || !isMobileMenuOpen) return;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = previousOverflow;
    };
  }, [isMobile, isMobileMenuOpen]);

  function openAddPass() {
    setIsMobileMenuOpen(false);
    setIsAddOpen(true);
  }

  async function handleCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!draft.encodedValue) {
      setDecodeState("error");
      setDecodeMessage("Add a decoded payload or paste the code value.");
      return;
    }
    const launchUrl = normalizeLaunchUrl(draft.launchUrl);
    if (draft.launchUrl.trim() && !launchUrl) {
      setDecodeState("error");
      setDecodeMessage("Use a valid HTTP(S) website address.");
      return;
    }

    const id = await createPass({
      title: draft.title || "Untitled pass",
      issuer: draft.issuer || undefined,
      codeType: draft.codeType,
      format: draft.format || undefined,
      encodedValue: draft.encodedValue,
      payloadEncoding: draft.payloadEncoding === "utf8" ? undefined : draft.payloadEncoding,
      launchUrl: launchUrl || undefined,
      visualMatrix: draft.visualMatrix || undefined,
      visualSize: draft.visualSize,
      visualWidth: draft.visualWidth,
      visualHeight: draft.visualHeight,
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
        ? "Saved the original payload, verified symbol, and website link."
        : draft.visualMatrix
          ? "Saved the original payload and verified symbol."
          : "Saved the metadata. Rescan the original before using it as a scannable symbol.",
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
      const inferredLaunchUrl = inferLaunchUrlFromPayload(result.rawValue);
      setDraft((current) => ({
        ...current,
        codeType: result.codeType,
        format: result.format,
        encodedValue: result.rawValue,
        payloadEncoding: "utf8",
        launchUrl: inferredLaunchUrl,
        visualMatrix: result.visualMatrix,
        visualSize: result.visualSize,
        visualWidth: result.visualSize,
        visualHeight: result.visualSize,
        title: current.title || file.name.replace(/\.[^.]+$/, ""),
      }));
      const scanMessage = inferredLaunchUrl ? " Found a website link without changing the encoded payload." : "";
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

  async function handleDrop(dataTransfer: DataTransfer) {
    try {
      const file = await getDroppedImageFile(dataTransfer);
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
      <aside className={`side-rail ${isMobileMenuOpen ? "mobile-menu-open" : ""}`}>
        <div className="rail-header">
          <div className="brand-row small">
            <span className="brand-icon">
              <QrCode size={20} />
            </span>
            <span>TicketLifeline</span>
          </div>
          {isMobile ? (
            <button
              type="button"
              className="mobile-menu-close"
              onClick={() => setIsMobileMenuOpen(false)}
              aria-label="Close menu"
            >
              <X size={20} />
            </button>
          ) : null}
        </div>
        <nav className="rail-nav" aria-label="Primary">
          <a className="active" href="#vault" onClick={() => setIsMobileMenuOpen(false)}>
            <Grid2X2 size={17} />
            Vault
          </a>
          <a
            href="#add-pass"
            onClick={(event) => {
              event.preventDefault();
              openAddPass();
            }}
          >
            <Plus size={17} />
            Add pass
          </a>
        </nav>
        <div className="rail-footer">
          <div className="rail-account-actions">
            <a
              className="rail-action"
              href={privacyPolicyUrl}
              target="_blank"
              rel="noreferrer"
            >
              <ShieldCheck size={17} />
              Privacy
            </a>
            <button
              type="button"
              className="rail-action"
              onClick={() => void signOut()}
            >
              <LogOut size={17} />
              Sign out
            </button>
            <button
              type="button"
              className="rail-action rail-action-danger"
              onClick={() => setIsDeleteOpen(true)}
            >
              <Trash2 size={14} />
              Delete account
            </button>
          </div>
        </div>
      </aside>

      {isMobile ? (
        <button
          type="button"
          className={`mobile-menu-backdrop ${isMobileMenuOpen ? "is-visible" : ""}`}
          onClick={() => setIsMobileMenuOpen(false)}
          aria-label="Close menu"
          aria-hidden={!isMobileMenuOpen}
          tabIndex={isMobileMenuOpen ? 0 : -1}
        />
      ) : null}

      <section className="vault-column" id="vault">
        {isMobile ? (
          <header className="mobile-top-bar">
            <div>
              <h1>Vault</h1>
              <p>{passList.length} saved passes</p>
            </div>
            <div className="mobile-top-actions">
              <button
                type="button"
                className="mobile-icon-button"
                onClick={openAddPass}
                aria-label="Add pass"
              >
                <Plus size={21} />
              </button>
              <button
                type="button"
                className="mobile-icon-button"
                onClick={() => setIsMobileMenuOpen((open) => !open)}
                aria-label={isMobileMenuOpen ? "Close menu" : "Open menu"}
              >
                {isMobileMenuOpen ? <X size={21} /> : <Menu size={21} />}
              </button>
            </div>
          </header>
        ) : null}
        {isMobile ? (
          <div className="mobile-search-field search-field">
            <Search size={17} />
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search passes"
            />
          </div>
        ) : null}
        <header className="top-bar">
          <div>
            <h1>Vault</h1>
            <p>{passList.length} saved passes</p>
          </div>
          <div className="desktop-top-actions">
            <div className="search-field">
              <Search size={17} />
              <input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Search passes"
              />
            </div>
            <button
              type="button"
              className="desktop-add-button"
              onClick={openAddPass}
              aria-label="Add pass"
            >
              <Plus size={21} />
            </button>
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
                    <small>{formatPreferredDate(pass)}</small>
                  </span>
                  <ArrowUpRight size={16} />
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
        <ImageUploadTarget className="add-drop-target" onFile={handleFile} onDrop={handleDrop} />
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
          onFile={handleFile}
          onDrop={handleDrop}
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
              onUpdate={async (fields) => {
                await updatePass({
                  id: selectedPass._id,
                  title: fields.title || "Untitled pass",
                  issuer: fields.issuer || undefined,
                  codeType: selectedPass.codeType,
                  format: selectedPass.format || undefined,
                  encodedValue: selectedPass.encodedValue,
                  payloadEncoding: selectedPass.payloadEncoding,
                  launchUrl: fields.launchUrl || undefined,
                  visualMatrix: selectedPass.visualMatrix || undefined,
                  visualSize: selectedPass.visualSize,
                  visualWidth: selectedPass.visualWidth,
                  visualHeight: selectedPass.visualHeight,
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
  onFile: (file: File | null) => void | Promise<void>;
  onDrop: (dataTransfer: DataTransfer) => void | Promise<void>;
  onSubmit: (event: FormEvent<HTMLFormElement>) => void;
  onCancel: () => void;
};

function AddPassDialog({ draft, decodeState, decodeMessage, onDraftChange, onFile, onDrop, onSubmit, onCancel }: AddPassDialogProps) {
  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={onCancel}>
      <section className="pass-dialog add-dialog" role="dialog" aria-modal="true" aria-labelledby="add-dialog-title" onMouseDown={(event) => event.stopPropagation()}>
        <button type="button" className="modal-close" onClick={onCancel} aria-label="Close add pass dialog">
          <X size={18} />
        </button>
        <div className="modal-heading">
          <div className="add-rail-icon"><Plus size={18} /></div>
          <div>
            <h2 id="add-dialog-title">Add new</h2>
            <p>Drop a ticket image to save it.</p>
          </div>
        </div>
        <ImageUploadTarget className="add-drop-target modal-upload-target" onFile={onFile} onDrop={onDrop} />
        <form className="pass-form" onSubmit={onSubmit}>
          <div className="field-grid">
            <label>
              Ticket title
              <input value={draft.title} onChange={(event) => onDraftChange({ ...draft, title: event.target.value })} placeholder="Train home" />
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
              <select value={draft.codeType} onChange={(event) => onDraftChange({ ...draft, codeType: event.target.value as CodeType, format: event.target.value === "qr" ? "QR_CODE" : "CODE_128", visualMatrix: "", visualSize: undefined, visualWidth: undefined, visualHeight: undefined })}>
                <option value="qr">QR code</option>
                <option value="barcode">Barcode</option>
              </select>
            </label>
          </div>
          <label>
            Encoded value
            <textarea value={draft.encodedValue} onChange={(event) => onDraftChange({ ...draft, encodedValue: event.target.value, payloadEncoding: "utf8", launchUrl: inferLaunchUrlFromPayload(event.target.value), visualMatrix: "", visualSize: undefined, visualWidth: undefined, visualHeight: undefined })} rows={3} />
          </label>
          <label>
            Website link
            <input value={draft.launchUrl} onChange={(event) => onDraftChange({ ...draft, launchUrl: event.target.value })} placeholder="https://example.com/ticket" />
          </label>
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

type ImageUploadTargetProps = {
  className?: string;
  onFile: (file: File | null) => void | Promise<void>;
  onDrop: (dataTransfer: DataTransfer) => void | Promise<void>;
};

function ImageUploadTarget({ className = "", onFile, onDrop }: ImageUploadTargetProps) {
  const [isDragActive, setIsDragActive] = useState(false);

  return (
    <label
      className={`upload-target ${className} ${isDragActive ? "drag-active" : ""}`.trim()}
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
      onDrop={(event) => {
        event.preventDefault();
        setIsDragActive(false);
        void onDrop(event.dataTransfer);
      }}
    >
      <input
        type="file"
        accept="image/*,.heic,.heif,image/heic,image/heif"
        onChange={(event) => {
          void onFile(event.target.files?.[0] ?? null);
          event.currentTarget.value = "";
        }}
      />
      <ImageUp size={24} />
      <span>{isDragActive ? "Drop image here" : "Drop or choose"}</span>
      <small>PNG, JPG, HEIC, or HEIF</small>
    </label>
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
