import JsBarcode from "jsbarcode";
import { Barcode, QrCode } from "lucide-react";
import QRCode from "qrcode";
import { useMemo } from "react";
import type { Pass } from "./types";
import { normalizeLaunchUrl } from "./utils";
import { BarcodeCityCode } from "./BarcodeCityCode";
import { QrTreeCode } from "./QrTreeCode";
import { matrixToString } from "./barcode";

type BarcodeEncoding = {
  data?: string;
};
type BarcodeRenderTarget = {
  encodings?: BarcodeEncoding[];
};

export function CodeRender({ pass }: { pass: Pass }) {
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

  const barcodeRender = useMemo(() => {
    if (pass.codeType !== "barcode") {
      return null;
    }

    try {
      const target: BarcodeRenderTarget = {};
      JsBarcode(target, pass.encodedValue, {
        format: "CODE128",
        displayValue: false,
        margin: 0,
        width: 1,
      });
      const binary = target.encodings?.map((encoding) => encoding.data ?? "").join("") ?? "";

      if (!/^[01]+$/.test(binary)) {
        throw new Error("Invalid barcode binary");
      }

      return {
        binary,
        error: "",
      };
    } catch {
      return {
        binary: "",
        error: "Could not render this barcode payload.",
      };
    }
  }, [pass.codeType, pass.encodedValue]);

  const renderError = qrRender?.error || barcodeRender?.error;

  return (
    <div className="code-frame">
      {pass.codeType === "qr" && qrRender?.matrix ? (
        <QrTreeCode matrix={qrRender.matrix} size={qrRender.size} />
      ) : pass.codeType === "qr" ? (
        <QrCode size={40} aria-hidden="true" />
      ) : barcodeRender?.binary ? (
        <BarcodeCityCode binary={barcodeRender.binary} />
      ) : (
        <Barcode size={44} aria-hidden="true" />
      )}
      {renderError ? <p className="form-error">{renderError}</p> : null}
    </div>
  );
}
