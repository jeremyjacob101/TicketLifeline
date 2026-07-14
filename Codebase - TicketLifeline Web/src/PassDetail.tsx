import { Check, Copy, Link2, Pencil, Trash2, X } from "lucide-react";
import { useState } from "react";
import type { Pass } from "./types";
import { normalizeLaunchUrl } from "./utils";
import { CodeRender } from "./CodeRender";

function getPassScanUrl(pass: Pass) {
  return normalizeLaunchUrl(pass.launchUrl ?? "") || normalizeLaunchUrl(pass.encodedValue);
}

type EditFields = {
  title: string;
  issuer: string;
  notes: string;
  eventDate: string;
  launchUrl: string;
};

function dateInputValue(timestamp: number) {
  const date = new Date(timestamp);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function displayDateValue(pass: Pass) {
  return pass.eventDate || dateInputValue(pass.createdAt);
}

function displayDateLabel(pass: Pass) {
  if (pass.eventDate) {
    const [year, month, day] = pass.eventDate.split("-");
    if (year && month && day) return `${day}/${month}/${year.slice(2)}`;
  }
  const date = new Date(pass.createdAt);
  const day = String(date.getDate()).padStart(2, "0");
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const year = String(date.getFullYear()).slice(2);
  const hours = String(date.getHours()).padStart(2, "0");
  const mins = String(date.getMinutes()).padStart(2, "0");
  return `${day}/${month}/${year} - ${hours}:${mins}`;
}

export function PassDetail({
  pass,
  onDelete,
  onUpdate,
}: {
  pass: Pass;
  onDelete: () => void;
  onUpdate: (fields: EditFields) => void;
}) {
  const [copied, setCopied] = useState(false);
  const [isEditing, setIsEditing] = useState(false);
  const [edit, setEdit] = useState<EditFields>({
    title: pass.title,
    issuer: pass.issuer ?? "",
    notes: pass.notes ?? "",
    eventDate: displayDateValue(pass),
    launchUrl: pass.launchUrl ?? "",
  });
  const scanUrl = pass.codeType === "qr" ? getPassScanUrl(pass) : "";

  function startEditing() {
    setEdit({
      title: pass.title,
      issuer: pass.issuer ?? "",
      notes: pass.notes ?? "",
      eventDate: displayDateValue(pass),
      launchUrl: pass.launchUrl ?? "",
    });
    setIsEditing(true);
  }

  function cancelEditing() {
    setIsEditing(false);
  }

  function handleSave() {
    onUpdate({
      ...edit,
      eventDate: edit.eventDate === dateInputValue(pass.createdAt) ? "" : edit.eventDate,
    });
    setIsEditing(false);
  }

  async function copyValue() {
    await navigator.clipboard.writeText(pass.encodedValue);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1600);
  }

  if (isEditing) {
    return (
      <div className="detail-content">
        <div className="detail-header">
          <span className="pass-swatch large" style={{ background: pass.color ?? "#0f766e" }} />
          <div>
            <h2>Edit pass</h2>
            <p>{pass.format || (pass.codeType === "qr" ? "QR_CODE" : "CODE_128")}</p>
          </div>
        </div>
        <CodeRender pass={pass} />
        <div className="edit-fields">
          <label>
            Title
            <input value={edit.title} onChange={(e) => setEdit({ ...edit, title: e.target.value })} />
          </label>
          <label>
            Issuer
            <input value={edit.issuer} onChange={(e) => setEdit({ ...edit, issuer: e.target.value })} />
          </label>
          <label>
            Pass date
            <input type="date" value={edit.eventDate} onChange={(e) => setEdit({ ...edit, eventDate: e.target.value })} />
            <small className="field-hint">Defaults to the created date. Change it only to set a different preferred date.</small>
          </label>
          <label>
            Notes
            <input value={edit.notes} onChange={(e) => setEdit({ ...edit, notes: e.target.value })} />
          </label>
          {pass.codeType === "qr" ? (
            <label>
              Opens when scanned
              <input value={edit.launchUrl} onChange={(e) => setEdit({ ...edit, launchUrl: e.target.value })} placeholder="https://example.com/ticket" />
            </label>
          ) : null}
        </div>
        <div className="detail-actions">
          <button type="button" className="secondary-button" onClick={cancelEditing}>
            <X size={16} />
            Cancel
          </button>
          <button type="button" className="primary-button" onClick={handleSave}>
            <Check size={16} />
            Save
          </button>
        </div>
      </div>
    );
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
          <dd>{displayDateLabel(pass)}</dd>
        </div>
        <div>
          <dt>Created</dt>
          <dd>{displayDateLabel({ ...pass, eventDate: undefined })}</dd>
        </div>
        <div>
          <dt>Notes</dt>
          <dd>{pass.notes || "No notes"}</dd>
        </div>
        {scanUrl ? (
          <div>
            <dt>Scan opens</dt>
            <dd>
              <a href={scanUrl} target="_blank" rel="noreferrer">
                <Link2 size={13} />
                Web link
              </a>
            </dd>
          </div>
        ) : null}
      </dl>
      <div className="payload-box">
        <span>{pass.encodedValue}</span>
      </div>
      <div className="detail-actions">
        <div className="detail-actions-left">
          <button type="button" className="primary-button" onClick={() => void copyValue()}>
            {copied ? <Check size={16} /> : <Copy size={16} />}
            {copied ? "Copied" : "Emergency copy"}
          </button>
        </div>
        <div className="detail-actions-right">
          <button type="button" className="secondary-button" onClick={startEditing}>
            <Pencil size={16} />
            Edit
          </button>
          <button type="button" className="danger-button" onClick={onDelete}>
            <Trash2 size={16} />
            Delete
          </button>
        </div>
      </div>
    </div>
  );
}
