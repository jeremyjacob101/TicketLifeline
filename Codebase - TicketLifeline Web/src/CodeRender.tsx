import { AlertTriangle } from "lucide-react";
import { useMemo } from "react";
import type { Pass } from "./types";
import { BarcodeCityCode } from "./BarcodeCityCode";
import { MatrixCode } from "./MatrixCode";
import { QrTreeCode } from "./QrTreeCode";

type StoredSymbol = {
  matrix: string;
  width: number;
  height: number;
};

function storedSymbol(pass: Pass): StoredSymbol | null {
  const width = pass.visualWidth ?? pass.visualSize;
  const height = pass.visualHeight ?? pass.visualSize;
  if (!pass.visualMatrix || !width || !height) return null;
  if (
    !Number.isSafeInteger(width) ||
    !Number.isSafeInteger(height) ||
    width < 1 ||
    height < 1 ||
    width > 40_000 ||
    height > 40_000 ||
    width * height > 40_000 ||
    pass.visualMatrix.length !== width * height ||
    !/^[01]+$/.test(pass.visualMatrix)
  ) {
    return null;
  }
  return { matrix: pass.visualMatrix, width, height };
}

export function CodeRender({ pass }: { pass: Pass }) {
  const symbol = useMemo(() => storedSymbol(pass), [pass]);

  return (
    <div className="code-frame">
      {!symbol ? (
        <div className="code-unavailable">
          <AlertTriangle size={38} aria-hidden="true" />
          <strong>Rescan required</strong>
          <span>This legacy symbol cannot be proven locally, so it will not be shown as scannable.</span>
        </div>
      ) : symbol.width === symbol.height ? (
        <QrTreeCode matrix={symbol.matrix} size={symbol.width} />
      ) : symbol.height === 1 ? (
        <BarcodeCityCode binary={symbol.matrix} />
      ) : (
        <MatrixCode matrix={symbol.matrix} width={symbol.width} height={symbol.height} />
      )}
    </div>
  );
}
