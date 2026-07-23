import { useEffect, useRef } from "react";

export function MatrixCode({ matrix, width, height }: { matrix: string; width: number; height: number }) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || width < 1 || height < 1 || matrix.length !== width * height) return;
    const context = canvas.getContext("2d");
    if (!context) return;
    // Keep a large integer-pixel backing store so wide formats such as PDF417
    // never collapse or crop when the canvas is scaled down for display.
    const displayWidth = 1080;
    const displayHeight = 930;
    canvas.width = displayWidth;
    canvas.height = displayHeight;
    context.setTransform(1, 0, 0, 1, 0, 0);
    context.imageSmoothingEnabled = false;
    context.fillStyle = "#fff";
    context.fillRect(0, 0, displayWidth, displayHeight);

    const quiet = 4;
    const cell = Math.max(
      1,
      Math.floor(Math.min((displayWidth - 24) / (width + quiet * 2), (displayHeight - 24) / (height + quiet * 2))),
    );
    const symbolWidth = (width + quiet * 2) * cell;
    const symbolHeight = (height + quiet * 2) * cell;
    const originX = Math.floor((displayWidth - symbolWidth) / 2) + quiet * cell;
    const originY = Math.floor((displayHeight - symbolHeight) / 2) + quiet * cell;
    context.fillStyle = "#000";
    for (let row = 0; row < height; row++) {
      for (let column = 0; column < width; column++) {
        if (matrix[row * width + column] === "1") {
          context.fillRect(originX + column * cell, originY + row * cell, cell, cell);
        }
      }
    }
  }, [height, matrix, width]);

  return (
    <span className="matrix-code-stage">
      <canvas ref={canvasRef} className="matrix-code-canvas" width={1080} height={930} aria-label="Scannable code" />
    </span>
  );
}
