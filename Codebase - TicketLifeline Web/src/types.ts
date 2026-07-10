import type { Doc } from "../../convex/_generated/dataModel";

export type Pass = Doc<"passes">;
export type CodeType = "qr" | "barcode";
export type DetectionSource = HTMLImageElement | HTMLCanvasElement;
export type BarcodeDetectorInstance = InstanceType<Window["BarcodeDetector"]>;
export type BarcodeDetectionResult = Awaited<
  ReturnType<BarcodeDetectorInstance["detect"]>
>[number];
export type MatrixMatch = {
  matrix: string;
  size: number;
  score: number;
};
