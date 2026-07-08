import JsBarcode from "jsbarcode";
import { QrCode } from "lucide-react";
import QRCode from "qrcode";
import { useEffect, useMemo, useRef, useState } from "react";
import type { Pass } from "./types";
import { normalizeLaunchUrl } from "./utils";
import { QrTreeCode } from "./QrTreeCode";
import { matrixToString } from "./barcode";

export function CodeRender({ pass }: { pass: Pass }) {
  const svgRef = useRef<SVGSVGElement | null>(null);
  const [barcodeRenderError, setBarcodeRenderError] = useState("");
  const qrRender = useMemo(() => {
    if (pass.codeType !== "qr") {
      return null;
    }
    const launchUrl = normalizeLaunchUrl(pass.launchUrl ?? "");

    if (!launchUrl && pass.visualMatrix && pass.visualSize) {
      return {
        matrix: pass.visualMatrix,
        size: pass.visualSize,
        error: "",
      };
    }

    try {
      const qr = QRCode.create(launchUrl || pass.encodedValue, { errorCorrectionLevel: "M" });
      return {
        matrix: matrixToString(qr.modules.data),
        size: qr.modules.size,
        error: "",
      };
    } catch {
      return {
        matrix: "",
        size: 0,
        error: "Could not render this QR payload.",
      };
    }
  }, [pass.codeType, pass.encodedValue, pass.launchUrl, pass.visualMatrix, pass.visualSize]);

  useEffect(() => {
    setBarcodeRenderError("");

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
        setBarcodeRenderError("Could not render this barcode payload.");
      }
    }
  }, [pass.codeType, pass.encodedValue]);

  const renderError = qrRender?.error || barcodeRenderError;

  return (
    <div className="code-frame">
      {pass.codeType === "qr" && qrRender?.matrix ? (
        <QrTreeCode matrix={qrRender.matrix} size={qrRender.size} />
      ) : pass.codeType === "qr" ? (
        <QrCode size={40} aria-hidden="true" />
      ) : (
        <svg ref={svgRef} className="barcode-svg" aria-label="Regenerated barcode" />
      )}
      {renderError ? <p className="form-error">{renderError}</p> : null}
    </div>
  );
}
