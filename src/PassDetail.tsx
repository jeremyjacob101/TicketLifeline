import { Check, Copy, Link2, Trash2 } from "lucide-react";
import { useState } from "react";
import type { Pass } from "./types";
import { normalizeLaunchUrl } from "./utils";
import { CodeRender } from "./CodeRender";

function getPassScanUrl(pass: Pass) {
  return normalizeLaunchUrl(pass.launchUrl ?? "") || normalizeLaunchUrl(pass.encodedValue);
}

export function PassDetail({ pass, onDelete }: { pass: Pass; onDelete: () => void }) {
  const [copied, setCopied] = useState(false);
  const scanUrl = pass.codeType === "qr" ? getPassScanUrl(pass) : "";

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
