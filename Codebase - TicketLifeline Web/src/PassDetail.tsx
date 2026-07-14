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
    eventDate: pass.eventDate ?? "",
    launchUrl: pass.launchUrl ?? "",
  });
  const scanUrl = pass.codeType === "qr" ? getPassScanUrl(pass) : "";

  function startEditing() {
    setEdit({
      title: pass.title,
      issuer: pass.issuer ?? "",
      notes: pass.notes ?? "",
      eventDate: pass.eventDate ?? "",
      launchUrl: pass.launchUrl ?? "",
    });
    setIsEditing(true);
  }

  function cancelEditing() {
    setIsEditing(false);
  }

  function handleSave() {
    onUpdate(edit);
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
            Date
            <input type="date" value={edit.eventDate} onChange={(e) => setEdit({ ...edit, eventDate: e.target.value })} />
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
          <dd>{pass.eventDate || "Anytime"}</dd>
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
