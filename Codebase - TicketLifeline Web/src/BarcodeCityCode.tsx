import { Building2, ScanBarcode } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";

type BarcodeCityCodeProps = {
  binary: string;
};

type BarcodeViewMode = "barcode" | "city";
type Point = { x: number; y: number };
type BarRun = {
  start: number;
  width: number;
  index: number;
};
type Building = BarRun & {
  flatX0: number;
  flatX1: number;
  flatTop: number;
  flatBottom: number;
  cityX0: number;
  cityX1: number;
  cityTop: number;
  cityBase: number;
  depthX: number;
  depthY: number;
  spire: number;
  palette: BuildingPalette;
};
type BuildingPalette = {
  front: string;
  shadow: string;
  right: string;
  roof: string;
  edge: string;
  window: string;
  glow: string;
};

const canvasWidth = 360;
const canvasHeight = 310;
const quietModules = 12;
const buildingPalettes: BuildingPalette[] = [
  {
    front: "#1f2937",
    shadow: "#111827",
    right: "#374151",
    roof: "#4b5563",
    edge: "#94a3b8",
    window: "#fbbf24",
    glow: "#fde68a",
  },
  {
    front: "#164e63",
    shadow: "#0f3b49",
    right: "#236b7d",
    roof: "#2f8799",
    edge: "#67e8f9",
    window: "#a7f3d0",
    glow: "#ccfbf1",
  },
  {
    front: "#312e81",
    shadow: "#1e1b4b",
    right: "#4338ca",
    roof: "#5b55d6",
    edge: "#c4b5fd",
    window: "#c4b5fd",
    glow: "#ddd6fe",
  },
  {
    front: "#7c2d12",
    shadow: "#431407",
    right: "#9a3412",
    roof: "#c2410c",
    edge: "#fed7aa",
    window: "#fed7aa",
    glow: "#ffedd5",
  },
];

export function BarcodeCityCode({ binary }: BarcodeCityCodeProps) {
  const [mode, setMode] = useState<BarcodeViewMode>("barcode");

  return (
    <div className="barcode-city-code">
      <div className="qr-mode-toggle" role="group" aria-label="Barcode view">
        <button
          type="button"
          className={mode === "barcode" ? "active" : ""}
          onClick={() => setMode("barcode")}
          title="Top barcode scan view"
          aria-pressed={mode === "barcode"}
        >
          <ScanBarcode size={15} />
          <span>Scan</span>
        </button>
        <button
          type="button"
          className={mode === "city" ? "active" : ""}
          onClick={() => setMode("city")}
          title="3D city street view"
          aria-pressed={mode === "city"}
        >
          <Building2 size={15} />
          <span>City</span>
        </button>
      </div>
      <button
        type="button"
        className={`barcode-artboard ${mode}`}
        onClick={() => setMode((current) => (current === "barcode" ? "city" : "barcode"))}
        aria-label={mode === "barcode" ? "Show 3D city view" : "Show top barcode scan view"}
      >
        <AnimatedBarcodeCityCanvas binary={binary} targetMode={mode} />
      </button>
    </div>
  );
}

function AnimatedBarcodeCityCanvas({
  binary,
  targetMode,
}: BarcodeCityCodeProps & { targetMode: BarcodeViewMode }) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const animationRef = useRef<number | null>(null);
  const progressRef = useRef(targetMode === "city" ? 1 : 0);
  const runs = useMemo(() => createRuns(binary), [binary]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const targetProgress = targetMode === "city" ? 1 : 0;
    let previousTime = performance.now();

    if (animationRef.current) {
      cancelAnimationFrame(animationRef.current);
    }

    function renderFrame(time: number) {
      if (!canvas) return;
      const deltaSeconds = Math.min(0.04, (time - previousTime) / 1000);
      previousTime = time;

      if (reducedMotion) {
        progressRef.current = targetProgress;
      } else {
        progressRef.current +=
          (targetProgress - progressRef.current) * Math.min(1, deltaSeconds * 5.8);
        if (Math.abs(progressRef.current - targetProgress) < 0.002) {
          progressRef.current = targetProgress;
        }
      }

      drawBarcodeCity(canvas, binary, runs, easeInOutCubic(progressRef.current));

      if (progressRef.current !== targetProgress) {
        animationRef.current = requestAnimationFrame(renderFrame);
      }
    }

    animationRef.current = requestAnimationFrame(renderFrame);

    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, [binary, runs, targetMode]);

  return (
    <span className="barcode-city-stage">
      <canvas
        ref={canvasRef}
        className="barcode-city-canvas"
        width={canvasWidth}
        height={canvasHeight}
        aria-hidden="true"
      />
    </span>
  );
}

function drawBarcodeCity(
  canvas: HTMLCanvasElement,
  binary: string,
  runs: BarRun[],
  progress: number,
) {
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.round(canvasWidth * dpr);
  canvas.height = Math.round(canvasHeight * dpr);

  const context = canvas.getContext("2d");
  if (!context) return;

  context.setTransform(dpr, 0, 0, dpr, 0, 0);
  context.clearRect(0, 0, canvasWidth, canvasHeight);
  context.imageSmoothingEnabled = false;

  const metrics = createBarcodeMetrics(binary.length);
  drawBarcodeBackdrop(context, progress, metrics);

  const cityOpacity = smoothstep(0.02, 0.22, progress);
  if (cityOpacity > 0) {
    context.save();
    context.globalAlpha = cityOpacity;
    drawCityScene(context, runs, metrics, progress);
    context.restore();
  }

  const flatOpacity = 1 - smoothstep(0.08, 0.38, progress);
  if (flatOpacity > 0) {
    context.save();
    context.globalAlpha = flatOpacity;
    drawFlatBarcode(context, binary, metrics, progress);
    context.restore();
  }
}

function drawBarcodeBackdrop(
  context: CanvasRenderingContext2D,
  progress: number,
  metrics: ReturnType<typeof createBarcodeMetrics>,
) {
  const gradient = context.createLinearGradient(0, 0, 0, canvasHeight);
  gradient.addColorStop(0, mixColor("#ffffff", "#f7fbff", progress));
  gradient.addColorStop(0.56, mixColor("#ffffff", "#eef5f2", progress));
  gradient.addColorStop(1, mixColor("#f8fafc", "#d9ddd7", progress));
  context.fillStyle = gradient;
  context.fillRect(0, 0, canvasWidth, canvasHeight);

  if (progress <= 0.04) return;

  context.save();
  context.globalAlpha = smoothstep(0.05, 0.62, progress);

  const horizon = 196;
  context.fillStyle = "#d8dfdc";
  context.fillRect(0, horizon, canvasWidth, canvasHeight - horizon);

  const road = [
    { x: metrics.flatX - 16, y: metrics.cityBaseLeft + 16 },
    { x: metrics.flatX + metrics.flatWidth + 22, y: metrics.cityBaseRight + 10 },
    { x: canvasWidth + 42, y: canvasHeight },
    { x: -42, y: canvasHeight },
  ];
  context.fillStyle = "#48515f";
  drawPolygon(context, road, false);

  context.strokeStyle = "rgba(255, 255, 255, 0.52)";
  context.lineWidth = 2;
  for (let index = 0; index < 7; index++) {
    const x = metrics.flatX + 10 + index * 48;
    context.beginPath();
    context.moveTo(x, 259 - index * 1.8);
    context.lineTo(x + 20, 269 + index * 2.4);
    context.stroke();
  }

  const sidewalk = [
    { x: metrics.flatX - 5, y: metrics.cityBaseLeft + 4 },
    { x: metrics.flatX + metrics.flatWidth + 3, y: metrics.cityBaseRight - 4 },
    { x: metrics.flatX + metrics.flatWidth + 20, y: metrics.cityBaseRight + 14 },
    { x: metrics.flatX - 18, y: metrics.cityBaseLeft + 22 },
  ];
  context.fillStyle = "#c6beb0";
  drawPolygon(context, sidewalk, false);
  context.strokeStyle = "rgba(67, 56, 45, 0.24)";
  context.lineWidth = 1;
  context.beginPath();
  context.moveTo(sidewalk[0].x, sidewalk[0].y);
  context.lineTo(sidewalk[1].x, sidewalk[1].y);
  context.stroke();

  context.restore();
}

function drawFlatBarcode(
  context: CanvasRenderingContext2D,
  binary: string,
  metrics: ReturnType<typeof createBarcodeMetrics>,
  progress: number,
) {
  context.save();
  context.shadowColor = `rgba(15, 23, 42, ${0.13 * (1 - progress)})`;
  context.shadowBlur = 20 * (1 - progress);
  context.shadowOffsetY = 10 * (1 - progress);
  context.fillStyle = "#ffffff";
  drawRoundedRect(
    context,
    metrics.flatX,
    metrics.flatY,
    metrics.flatWidth,
    metrics.flatHeight,
    7,
  );
  context.restore();

  context.fillStyle = "#ffffff";
  context.fillRect(
    metrics.barX - quietModules * metrics.module,
    metrics.barY,
    metrics.flatWidth,
    metrics.barHeight,
  );

  context.fillStyle = "#111827";
  for (let index = 0; index < binary.length; index++) {
    if (binary[index] !== "1") continue;
    const x = metrics.barX + index * metrics.module;
    context.fillRect(x, metrics.barY, Math.max(metrics.module, 0.55), metrics.barHeight);
  }

  context.strokeStyle = "rgba(15, 23, 42, 0.08)";
  context.lineWidth = 1;
  drawRoundedRect(
    context,
    metrics.flatX + 0.5,
    metrics.flatY + 0.5,
    metrics.flatWidth - 1,
    metrics.flatHeight - 1,
    7,
    true,
  );
}

function drawCityScene(
  context: CanvasRenderingContext2D,
  runs: BarRun[],
  metrics: ReturnType<typeof createBarcodeMetrics>,
  progress: number,
) {
  const buildings = runs.map((run) => createBuilding(run, metrics));

  context.save();
  context.globalAlpha *= smoothstep(0.12, 0.72, progress) * 0.34;
  for (const building of buildings) {
    drawBuildingShadow(context, building, progress);
  }
  context.restore();

  buildings
    .sort((a, b) => a.cityBase - b.cityBase || a.cityX0 - b.cityX0)
    .forEach((building) => drawBuilding(context, building, progress));
}

function createBuilding(
  run: BarRun,
  metrics: ReturnType<typeof createBarcodeMetrics>,
): Building {
  const centerModule = run.start + run.width / 2;
  const norm = centerModule / Math.max(1, metrics.bitLength);
  const palette = buildingPalettes[run.index % buildingPalettes.length];
  const laneBase = lerp(metrics.cityBaseLeft, metrics.cityBaseRight, norm);
  const rawFootprintWidth = run.width * metrics.cityModule;
  const footprintWidth = Math.max(3.2, rawFootprintWidth * 1.16);
  const centerX = metrics.cityBarX + centerModule * metrics.cityModule;
  const height =
    (68 + run.width * 8.5 + pseudoRandom(run.index, run.width, 3) * 72) *
    (1.04 - norm * 0.13);
  const depth = (9 + Math.min(22, footprintWidth * 1.55)) * (0.92 + norm * 0.24);
  const spire =
    height > 104 && pseudoRandom(run.index, run.width, 71) > 0.62
      ? 5 + pseudoRandom(run.index, run.width, 73) * 9
      : 0;

  return {
    ...run,
    flatX0: metrics.barX + run.start * metrics.module,
    flatX1: metrics.barX + (run.start + run.width) * metrics.module,
    flatTop: metrics.barY,
    flatBottom: metrics.barY + metrics.barHeight,
    cityX0: centerX - footprintWidth / 2,
    cityX1: centerX + footprintWidth / 2,
    cityTop: Math.max(34, laneBase - height),
    cityBase: laneBase,
    depthX: depth,
    depthY: -7 - norm * 7,
    spire,
    palette,
  };
}

function drawBuildingShadow(
  context: CanvasRenderingContext2D,
  building: Building,
  progress: number,
) {
  const x0 = lerp(building.flatX0, building.cityX0, progress);
  const x1 = lerp(building.flatX1, building.cityX1, progress);
  const base = lerp(building.flatBottom, building.cityBase, progress);
  const length = (18 + building.width * 4) * progress;

  context.fillStyle = "#111827";
  context.beginPath();
  context.moveTo(x0 - 1, base + 1);
  context.lineTo(x1 + 1, base + 1);
  context.lineTo(x1 + length, base + 14 + length * 0.16);
  context.lineTo(x0 + length * 0.44, base + 11 + length * 0.12);
  context.closePath();
  context.fill();
}

function drawBuilding(
  context: CanvasRenderingContext2D,
  building: Building,
  progress: number,
) {
  const front = getBuildingFrontPoints(building, progress);
  const offset = {
    x: building.depthX * smoothstep(0.14, 1, progress),
    y: building.depthY * smoothstep(0.14, 1, progress),
  };
  const palette = building.palette;

  context.strokeStyle = `rgba(8, 13, 23, ${0.08 + progress * 0.12})`;
  context.lineWidth = 0.65;

  if (progress > 0.12) {
    const sideGradient = context.createLinearGradient(
      front[1].x,
      front[1].y,
      front[1].x + offset.x,
      front[1].y + offset.y,
    );
    sideGradient.addColorStop(0, palette.shadow);
    sideGradient.addColorStop(1, palette.right);
    context.fillStyle = sideGradient;
    drawPolygon(context, [
      front[1],
      { x: front[1].x + offset.x, y: front[1].y + offset.y },
      { x: front[2].x + offset.x, y: front[2].y + offset.y },
      front[2],
    ]);

    const roofGradient = context.createLinearGradient(
      front[0].x,
      front[0].y,
      front[1].x + offset.x,
      front[1].y + offset.y,
    );
    roofGradient.addColorStop(0, palette.edge);
    roofGradient.addColorStop(0.34, palette.roof);
    roofGradient.addColorStop(1, palette.shadow);
    context.fillStyle = roofGradient;
    drawPolygon(context, [
      front[0],
      { x: front[0].x + offset.x, y: front[0].y + offset.y },
      { x: front[1].x + offset.x, y: front[1].y + offset.y },
      front[1],
    ]);
    drawRoofLines(context, front, offset, building, progress);
  }

  const frontGradient = context.createLinearGradient(front[0].x, front[0].y, front[3].x, front[3].y);
  frontGradient.addColorStop(0, mixColor("#111827", palette.front, progress));
  frontGradient.addColorStop(0.68, mixColor("#111827", palette.front, progress));
  frontGradient.addColorStop(1, mixColor("#111827", palette.shadow, progress));
  context.fillStyle = frontGradient;
  drawPolygon(context, front);
  drawFacadeDetails(context, building, front, offset, progress);
}

function drawRoofLines(
  context: CanvasRenderingContext2D,
  front: Point[],
  offset: Point,
  building: Building,
  progress: number,
) {
  const detailOpacity = smoothstep(0.36, 0.9, progress);
  if (detailOpacity <= 0) return;

  context.save();
  context.globalAlpha *= detailOpacity;
  context.strokeStyle = colorWithAlpha(building.palette.edge, 0.44);
  context.lineWidth = 0.7;
  context.beginPath();
  context.moveTo(front[0].x + offset.x * 0.24, front[0].y + offset.y * 0.24);
  context.lineTo(front[1].x + offset.x * 0.24, front[1].y + offset.y * 0.24);
  context.moveTo(front[1].x + offset.x * 0.52, front[1].y + offset.y * 0.52);
  context.lineTo(front[1].x, front[1].y);
  context.stroke();

  if (building.spire > 0) {
    const roofCenterX = (front[0].x + front[1].x + offset.x) / 2;
    const roofCenterY = (front[0].y + front[1].y + offset.y) / 2;
    context.strokeStyle = colorWithAlpha(building.palette.shadow, 0.72);
    context.lineWidth = 1.1;
    context.beginPath();
    context.moveTo(roofCenterX, roofCenterY);
    context.lineTo(roofCenterX + 1.3, roofCenterY - building.spire * progress);
    context.stroke();
  }

  context.restore();
}

function drawFacadeDetails(
  context: CanvasRenderingContext2D,
  building: Building,
  front: Point[],
  offset: Point,
  progress: number,
) {
  const opacity = smoothstep(0.38, 0.92, progress);
  if (opacity <= 0) return;

  const width = front[1].x - front[0].x;
  const height = front[2].y - front[1].y;
  if (width < 2 || height < 28) return;

  context.save();
  context.globalAlpha *= opacity;

  context.strokeStyle = colorWithAlpha(building.palette.edge, 0.42);
  context.lineWidth = 0.8;
  context.beginPath();
  context.moveTo(front[1].x - 0.5, front[1].y + 2);
  context.lineTo(front[2].x - 0.5, front[2].y - 3);
  context.stroke();

  const columns = Math.max(1, Math.min(3, Math.floor(width / 4.6)));
  const rows = Math.max(3, Math.min(10, Math.floor(height / 12)));
  const padX = Math.max(0.8, width * 0.18);
  const padTop = Math.max(8, height * 0.1);
  const usableWidth = Math.max(1, width - padX * 2);
  const cellW = Math.max(0.85, Math.min(2.6, usableWidth / Math.max(1, columns * 1.7)));
  const cellH = Math.max(1.5, Math.min(3, height / 45));

  context.fillStyle = building.palette.window;
  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < columns; col++) {
      if (pseudoRandom(building.index + col, row, 31) < 0.2) continue;
      const x = front[0].x + padX + col * (usableWidth / columns);
      const y = front[0].y + padTop + row * ((height - padTop - 10) / rows);
      context.fillRect(x, y, cellW, cellH);
    }
  }

  drawSideWindows(context, building, front, offset, height);
  drawVerticalMullions(context, building, front, width, height);

  if (width > 5.5 && pseudoRandom(building.index, building.width, 37) > 0.46) {
    context.globalAlpha *= 0.7;
    context.fillStyle = building.palette.glow;
    context.fillRect(front[0].x + width * 0.18, front[2].y - 12, width * 0.44, 5);
  }

  context.restore();
}

function drawSideWindows(
  context: CanvasRenderingContext2D,
  building: Building,
  front: Point[],
  offset: Point,
  height: number,
) {
  if (offset.x < 4 || height < 42) return;

  const rows = Math.max(3, Math.min(8, Math.floor(height / 15)));
  context.save();
  context.globalAlpha *= 0.62;
  context.strokeStyle = colorWithAlpha(building.palette.glow, 0.7);
  context.lineWidth = 0.85;

  for (let row = 0; row < rows; row++) {
    if (pseudoRandom(building.index, row, 89) < 0.26) continue;
    const y = front[1].y + 11 + row * ((height - 22) / rows);
    context.beginPath();
    context.moveTo(front[1].x + offset.x * 0.22, y + offset.y * 0.12);
    context.lineTo(front[1].x + offset.x * 0.82, y + offset.y * 0.34);
    context.stroke();
  }

  context.restore();
}

function drawVerticalMullions(
  context: CanvasRenderingContext2D,
  building: Building,
  front: Point[],
  width: number,
  height: number,
) {
  if (width < 4.8 || height < 52) return;

  const mullions = Math.min(2, Math.floor(width / 6));
  context.save();
  context.globalAlpha *= 0.26;
  context.strokeStyle = building.palette.shadow;
  context.lineWidth = 0.7;

  for (let index = 1; index <= mullions; index++) {
    const x = front[0].x + (width * index) / (mullions + 1);
    context.beginPath();
    context.moveTo(x, front[0].y + 7);
    context.lineTo(x, front[3].y - 5);
    context.stroke();
  }

  context.restore();
}

function getBuildingFrontPoints(building: Building, progress: number): Point[] {
  const x0 = lerp(building.flatX0, building.cityX0, progress);
  const x1 = lerp(building.flatX1, building.cityX1, progress);
  const top = lerp(building.flatTop, building.cityTop, progress);
  const bottom = lerp(building.flatBottom, building.cityBase, progress);

  return [
    { x: x0, y: top },
    { x: x1, y: top },
    { x: x1, y: bottom },
    { x: x0, y: bottom },
  ];
}

function createBarcodeMetrics(bitLength: number) {
  const flatWidth = Math.min(316, canvasWidth - 44);
  const flatHeight = 136;
  const totalModules = bitLength + quietModules * 2;
  const module = flatWidth / totalModules;
  const cityWidth = Math.min(304, canvasWidth - 56);
  const cityModule = cityWidth / totalModules;

  return {
    bitLength,
    flatWidth,
    flatHeight,
    flatX: (canvasWidth - flatWidth) / 2,
    flatY: (canvasHeight - flatHeight) / 2,
    module,
    barX: (canvasWidth - flatWidth) / 2 + quietModules * module,
    barY: (canvasHeight - flatHeight) / 2 + 24,
    barHeight: flatHeight - 48,
    cityModule,
    cityBarX: (canvasWidth - cityWidth) / 2 + quietModules * cityModule,
    cityBaseLeft: 235,
    cityBaseRight: 215,
  };
}

function createRuns(binary: string): BarRun[] {
  const runs: BarRun[] = [];
  let index = 0;

  while (index < binary.length) {
    const dark = binary[index] === "1";
    const start = index;
    while (index < binary.length && binary[index] === binary[start]) {
      index++;
    }

    if (dark) {
      runs.push({
        start,
        width: index - start,
        index: runs.length,
      });
    }
  }

  return runs;
}

function drawPolygon(
  context: CanvasRenderingContext2D,
  points: Point[],
  stroke = true,
) {
  context.beginPath();
  context.moveTo(points[0].x, points[0].y);
  for (const point of points.slice(1)) {
    context.lineTo(point.x, point.y);
  }
  context.closePath();
  context.fill();
  if (stroke) {
    context.stroke();
  }
}

function drawRoundedRect(
  context: CanvasRenderingContext2D,
  x: number,
  y: number,
  width: number,
  height: number,
  radius: number,
  stroke = false,
) {
  context.beginPath();
  context.moveTo(x + radius, y);
  context.lineTo(x + width - radius, y);
  context.quadraticCurveTo(x + width, y, x + width, y + radius);
  context.lineTo(x + width, y + height - radius);
  context.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
  context.lineTo(x + radius, y + height);
  context.quadraticCurveTo(x, y + height, x, y + height - radius);
  context.lineTo(x, y + radius);
  context.quadraticCurveTo(x, y, x + radius, y);
  context.closePath();
  if (stroke) {
    context.stroke();
  } else {
    context.fill();
  }
}

function easeInOutCubic(value: number) {
  return value < 0.5 ? 4 * value * value * value : 1 - Math.pow(-2 * value + 2, 3) / 2;
}

function smoothstep(edge0: number, edge1: number, value: number) {
  const t = Math.max(0, Math.min(1, (value - edge0) / (edge1 - edge0)));
  return t * t * (3 - 2 * t);
}

function lerp(start: number, end: number, amount: number) {
  return start + (end - start) * amount;
}

function mixColor(start: string, end: string, amount: number) {
  const from = hexToRgb(start);
  const to = hexToRgb(end);
  return `rgb(${Math.round(lerp(from.r, to.r, amount))}, ${Math.round(
    lerp(from.g, to.g, amount),
  )}, ${Math.round(lerp(from.b, to.b, amount))})`;
}

function colorWithAlpha(value: string, alpha: number) {
  const color = hexToRgb(value);
  return `rgba(${color.r}, ${color.g}, ${color.b}, ${alpha})`;
}

function hexToRgb(value: string) {
  const hex = value.replace("#", "");
  return {
    r: Number.parseInt(hex.slice(0, 2), 16),
    g: Number.parseInt(hex.slice(2, 4), 16),
    b: Number.parseInt(hex.slice(4, 6), 16),
  };
}

function pseudoRandom(col: number, row: number, seed: number) {
  const value = Math.sin((col + 1) * 91.73 + (row + 1) * 57.31 + seed * 19.19) * 10000;
  return value - Math.floor(value);
}
