import QRCode from "qrcode";
import type { DetectionSource, BarcodeDetectorInstance, BarcodeDetectionResult, CodeType, MatrixMatch } from "./types";
import { normalizeImageFile } from "./utils";

export function matrixToString(data: Uint8Array) {
  let value = "";
  for (const bit of data) {
    value += bit ? "1" : "0";
  }
  return value;
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

function scaleImageToCanvas(image: HTMLImageElement, maxLongEdge: number) {
  const width = image.naturalWidth || image.width;
  const height = image.naturalHeight || image.height;
  const scale = Math.min(1, maxLongEdge / Math.max(width, height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(width * scale));
  canvas.height = Math.max(1, Math.round(height * scale));
  const context = canvas.getContext("2d");
  if (!context) {
    throw new Error("Could not prepare image for scanning.");
  }
  context.imageSmoothingEnabled = true;
  context.imageSmoothingQuality = "high";
  context.drawImage(image, 0, 0, canvas.width, canvas.height);
  return canvas;
}

function rotateCanvas(source: HTMLCanvasElement, degrees: 90 | 180 | 270) {
  const canvas = document.createElement("canvas");
  const quarterTurn = degrees === 90 || degrees === 270;
  canvas.width = quarterTurn ? source.height : source.width;
  canvas.height = quarterTurn ? source.width : source.height;
  const context = canvas.getContext("2d");
  if (!context) {
    throw new Error("Could not rotate image for scanning.");
  }
  context.translate(canvas.width / 2, canvas.height / 2);
  context.rotate((degrees * Math.PI) / 180);
  context.drawImage(source, -source.width / 2, -source.height / 2);
  return canvas;
}

function createDetectionSources(image: HTMLImageElement) {
  const base = scaleImageToCanvas(image, 2200);
  return [base, rotateCanvas(base, 90), rotateCanvas(base, 180), rotateCanvas(base, 270)];
}

function getSourceWidth(source: DetectionSource) {
  return source instanceof HTMLImageElement
    ? source.naturalWidth || source.width
    : source.width;
}

function getSourceHeight(source: DetectionSource) {
  return source instanceof HTMLImageElement
    ? source.naturalHeight || source.height
    : source.height;
}

async function detectAcrossOrientations(
  detector: BarcodeDetectorInstance,
  image: HTMLImageElement,
) {
  const sources = createDetectionSources(image);
  for (const source of sources) {
    const results = await detector.detect(source);
    const result = results[0];
    if (result?.rawValue) {
      return { result, source };
    }
  }

  throw new Error("No QR or barcode was found. Try a clearer image or paste the value.");
}

function lerpPoint(
  start: { x: number; y: number },
  end: { x: number; y: number },
  amount: number,
) {
  return {
    x: start.x + (end.x - start.x) * amount,
    y: start.y + (end.y - start.y) * amount,
  };
}

function interpolateQuad(
  corners: ReturnType<typeof getOrderedQrCorners>,
  u: number,
  v: number,
) {
  const top = lerpPoint(corners.topLeft, corners.topRight, u);
  const bottom = lerpPoint(corners.bottomLeft, corners.bottomRight, u);
  return lerpPoint(top, bottom, v);
}

function readLuminance(imageData: ImageData, x: number, y: number) {
  const safeX = Math.min(imageData.width - 1, Math.max(0, Math.round(x)));
  const safeY = Math.min(imageData.height - 1, Math.max(0, Math.round(y)));
  const index = (safeY * imageData.width + safeX) * 4;
  return (
    imageData.data[index] * 0.299 +
    imageData.data[index + 1] * 0.587 +
    imageData.data[index + 2] * 0.114
  );
}

function otsuThreshold(values: number[]) {
  const histogram = new Array<number>(256).fill(0);
  for (const value of values) {
    histogram[Math.min(255, Math.max(0, Math.round(value)))]++;
  }

  const total = values.length;
  let sum = 0;
  for (let index = 0; index < histogram.length; index++) {
    sum += index * histogram[index];
  }

  let sumBackground = 0;
  let weightBackground = 0;
  let maxVariance = 0;
  let threshold = 128;

  for (let index = 0; index < histogram.length; index++) {
    weightBackground += histogram[index];
    if (weightBackground === 0) continue;
    const weightForeground = total - weightBackground;
    if (weightForeground === 0) break;

    sumBackground += index * histogram[index];
    const meanBackground = sumBackground / weightBackground;
    const meanForeground = (sum - sumBackground) / weightForeground;
    const variance =
      weightBackground *
      weightForeground *
      (meanBackground - meanForeground) *
      (meanBackground - meanForeground);

    if (variance > maxVariance) {
      maxVariance = variance;
      threshold = index;
    }
  }

  return threshold;
}

function percentile(values: number[], ratio: number) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.max(0, Math.floor(sorted.length * ratio)))];
}

function getOrderedQrCorners(result: BarcodeDetectionResult) {
  const points =
    result.cornerPoints.length === 4
      ? result.cornerPoints
      : [
          { x: result.boundingBox.x, y: result.boundingBox.y },
          {
            x: result.boundingBox.x + result.boundingBox.width,
            y: result.boundingBox.y,
          },
          {
            x: result.boundingBox.x + result.boundingBox.width,
            y: result.boundingBox.y + result.boundingBox.height,
          },
          {
            x: result.boundingBox.x,
            y: result.boundingBox.y + result.boundingBox.height,
          },
        ];

  const center = {
    x: points.reduce((total, point) => total + point.x, 0) / points.length,
    y: points.reduce((total, point) => total + point.y, 0) / points.length,
  };
  const sorted = [...points].sort(
    (a, b) =>
      Math.atan2(a.y - center.y, a.x - center.x) -
      Math.atan2(b.y - center.y, b.x - center.x),
  );
  const topLeftIndex = sorted.reduce((bestIndex, point, index) => {
    const best = sorted[bestIndex];
    return point.x + point.y < best.x + best.y ? index : bestIndex;
  }, 0);
  const ordered = [...sorted.slice(topLeftIndex), ...sorted.slice(0, topLeftIndex)];

  return {
    topLeft: ordered[0],
    topRight: ordered[1],
    bottomRight: ordered[2],
    bottomLeft: ordered[3],
  };
}

function sourceToImageData(source: DetectionSource) {
  const canvas = document.createElement("canvas");
  canvas.width = getSourceWidth(source);
  canvas.height = getSourceHeight(source);
  const context = canvas.getContext("2d", { willReadFrequently: true });
  if (!context) {
    throw new Error("Could not read image pixels for QR matching.");
  }
  context.drawImage(source, 0, 0);
  return context.getImageData(0, 0, canvas.width, canvas.height);
}

function sampleDetectedQrMatrix(
  imageData: ImageData,
  result: BarcodeDetectionResult,
  size: number,
  sourceQuietModules: number,
) {
  const corners = getOrderedQrCorners(result);
  const luminance: number[] = [];
  const sourceSpan = size + sourceQuietModules * 2;

  for (let row = 0; row < size; row++) {
    for (let col = 0; col < size; col++) {
      const point = interpolateQuad(
        corners,
        (sourceQuietModules + col + 0.5) / sourceSpan,
        (sourceQuietModules + row + 0.5) / sourceSpan,
      );
      luminance.push(readLuminance(imageData, point.x, point.y));
    }
  }

  const threshold = otsuThreshold(luminance);
  const matrix = luminance.map((value) => (value <= threshold ? "1" : "0")).join("");
  const spread = percentile(luminance, 0.85) - percentile(luminance, 0.15);

  return {
    matrix,
    confidence: Math.min(1, Math.max(0.35, spread / 130)),
  };
}

function scoreMatrix(expected: string, sampled: string, confidence: number) {
  const length = Math.min(expected.length, sampled.length);
  let matches = 0;
  for (let index = 0; index < length; index++) {
    if (expected[index] === sampled[index]) {
      matches++;
    }
  }
  return (matches / length) * confidence;
}

function createQrCandidates(payload: string) {
  const levels = ["L", "M", "Q", "H"] as const;
  const candidates = new Map<string, MatrixMatch>();

  for (const errorCorrectionLevel of levels) {
    let baseVersion: number | null = null;
    try {
      baseVersion = QRCode.create(payload, { errorCorrectionLevel }).version;
    } catch {
      continue;
    }

    for (let version = baseVersion; version <= Math.min(40, baseVersion + 8); version++) {
      for (const maskPattern of [0, 1, 2, 3, 4, 5, 6, 7] as const) {
        try {
          const qr = QRCode.create(payload, {
            errorCorrectionLevel,
            maskPattern,
            version,
          });
          const matrix = matrixToString(qr.modules.data);
          candidates.set(`${qr.modules.size}:${matrix}`, {
            matrix,
            size: qr.modules.size,
            score: 0,
          });
        } catch {
          // Some version/error-correction combinations cannot fit the payload.
        }
      }
    }
  }

  return Array.from(candidates.values());
}

function findMatchingQrMatrix(
  source: DetectionSource,
  result: BarcodeDetectionResult,
  payload: string,
): MatrixMatch | null {
  const candidates = createQrCandidates(payload);
  if (!candidates.length) {
    return null;
  }

  const imageData = sourceToImageData(source);
  const sampledBySize = new Map<string, { matrix: string; confidence: number }>();
  let best: MatrixMatch | null = null;

  for (const candidate of candidates) {
    for (const sourceQuietModules of [0, 4]) {
      const cacheKey = `${candidate.size}:${sourceQuietModules}`;
      let sampled = sampledBySize.get(cacheKey);
      if (!sampled) {
        sampled = sampleDetectedQrMatrix(imageData, result, candidate.size, sourceQuietModules);
        sampledBySize.set(cacheKey, sampled);
      }
      const score = scoreMatrix(candidate.matrix, sampled.matrix, sampled.confidence);
      if (!best || score > best.score) {
        best = { ...candidate, score };
      }
    }
  }

  return best;
}

function renderQrMatrix(matrix: string, size: number) {
  const quiet = 4;
  const scale = 10;
  const canvas = document.createElement("canvas");
  canvas.width = (size + quiet * 2) * scale;
  canvas.height = canvas.width;
  const context = canvas.getContext("2d");
  if (!context) throw new Error("Could not verify the preserved QR pattern.");
  context.imageSmoothingEnabled = false;
  context.fillStyle = "#fff";
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.fillStyle = "#000";
  for (let row = 0; row < size; row++) {
    for (let column = 0; column < size; column++) {
      if (matrix[row * size + column] === "1") {
        context.fillRect((column + quiet) * scale, (row + quiet) * scale, scale, scale);
      }
    }
  }
  return canvas;
}

async function verifyQrMatrix(
  detector: BarcodeDetectorInstance,
  match: MatrixMatch,
  payload: string,
) {
  const results = await detector.detect(renderQrMatrix(match.matrix, match.size));
  return results.some((result) => result.format === "qr_code" && result.rawValue === payload);
}

export async function decodeBarcodeFromImage(file: File): Promise<{
  rawValue: string;
  format: string;
  codeType: CodeType;
  visualMatrix: string;
  visualSize: number | undefined;
}> {
  if (!("BarcodeDetector" in window)) {
    throw new Error("This browser cannot decode images yet. Paste the payload manually.");
  }

  const requestedFormats: BarcodeDetectionResult["format"][] = [
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
  ];
  const runtimeFormats = await window.BarcodeDetector.getSupportedFormats?.();
  const formats = runtimeFormats?.length
    ? requestedFormats.filter((format) => runtimeFormats.includes(format))
    : requestedFormats;
  if (!formats.length) {
    throw new Error("This browser does not expose a supported QR or barcode format.");
  }
  const detector = new window.BarcodeDetector({
    formats,
  });

  const imageFile = await normalizeImageFile(file);
  const image = await loadImage(imageFile);
  const { result, source } = await detectAcrossOrientations(detector, image);
  if (!result?.rawValue) {
    throw new Error("No QR or barcode was found. Try a clearer image or paste the value.");
  }

  const format = result.format.toUpperCase();
  const matrixMatch =
    result.format === "qr_code"
      ? findMatchingQrMatrix(source, result, result.rawValue)
      : null;

  const matrixMatchesPhoto = !!matrixMatch && matrixMatch.score >= 0.72;
  const matrixRoundTrips = matrixMatchesPhoto
    ? await verifyQrMatrix(detector, matrixMatch, result.rawValue)
    : false;
  if (!matrixMatch || !matrixMatchesPhoto || !matrixRoundTrips) {
    const debugDetail = import.meta.env.DEV
      ? ` [match=${matrixMatch?.score.toFixed(3) ?? "none"}; roundTrip=${matrixRoundTrips}]`
      : "";
    throw new Error(
      result.format === "qr_code"
        ? `The QR code was read, but its exact pattern could not be verified. Try a clearer image or import it with the iPhone app.${debugDetail}`
        : `The barcode was read, but this browser cannot preserve its exact bars safely. Import it with the iPhone app instead.${debugDetail}`,
    );
  }

  return {
    rawValue: result.rawValue,
    format,
    codeType: result.format === "qr_code" ? "qr" : "barcode",
    visualMatrix: matrixMatch.matrix,
    visualSize: matrixMatch.size,
  };
}
