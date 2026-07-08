/// <reference types="vite/client" />

type BarcodeDetectorFormat =
  | "aztec"
  | "code_128"
  | "code_39"
  | "code_93"
  | "codabar"
  | "data_matrix"
  | "ean_13"
  | "ean_8"
  | "itf"
  | "pdf417"
  | "qr_code"
  | "upc_a"
  | "upc_e";

type BarcodeDetectorResult = {
  boundingBox: DOMRectReadOnly;
  cornerPoints: ReadonlyArray<{ x: number; y: number }>;
  format: BarcodeDetectorFormat;
  rawValue: string;
};

declare global {
  interface Window {
    BarcodeDetector: {
      new (options?: {
        formats?: BarcodeDetectorFormat[];
      }): {
        detect(image: CanvasImageSource): Promise<BarcodeDetectorResult[]>;
      };
      getSupportedFormats?: () => Promise<BarcodeDetectorFormat[]>;
    };
  }
}

export {};
