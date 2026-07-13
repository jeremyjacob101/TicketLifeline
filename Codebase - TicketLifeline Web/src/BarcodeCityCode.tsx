import { useEffect, useMemo, useRef, useState } from "react";

type BarcodeCityCodeProps = {
  binary: string;
};

type BarcodeViewMode = "barcode" | "city";
type RunKind = "quiet" | "street" | "building";
type Direction = "cross" | "avenue";
type Point = { x: number; y: number };
type Point3 = { x: number; y: number; z: number };
type Palette = {
  front: string;
  side: string;
  roof: string;
  window: string;
};
type BarcodeRun = {
  kind: RunKind;
  index: number;
  palette: number;
  flatCenter: number;
  flatWidth: number;
  cityCenter: number;
  cityWidth: number;
  cityHeight: number;
};
type Street = { x: number; width: number };
type CityProp = {
  x: number;
  z: number;
  streetWidth: number;
  kind: "car" | "signal";
  palette: number;
  direction: Direction;
};
type BarcodeLayout = {
  runs: BarcodeRun[];
  props: CityProp[];
  streetWidth: number;
  cityHalfWidth: number;
};
type RunGeometry = {
  x0: number;
  x1: number;
  z0: number;
  z1: number;
  height: number;
};

const canvasWidth = 360;
const canvasHeight = 310;
const quietModules = 8;
const flatSpan = 1.55;
const flatDepth = 0.56;
const citySpan = 1.78;
const cityStreetModules = 18;
const cityBuildingMultiplier = 5;
const roadCenter = 0.09;
const asphalt = "#868e96";
const paleBarcode = "#eef1f4";
const whiteMarking = "#f5f7fa";
const buildingPalettes: Palette[] = [
  { front: "#1f2937", side: "#37404d", roof: "#4b5563", window: "#ebc75f" },
  { front: "#164e63", side: "#143b49", roof: "#2f8799", window: "#a7f3d0" },
  { front: "#312e81", side: "#1e1b4b", roof: "#5b55d6", window: "#ebc75f" },
  { front: "#7c2d12", side: "#431407", roof: "#c2410d", window: "#fed7aa" },
];
const carColors = ["#eb4a31", "#29aaa0", "#476dee", "#f28724"];

export function BarcodeCityCode({ binary }: BarcodeCityCodeProps) {
  const [mode, setMode] = useState<BarcodeViewMode>("barcode");

  return (
    <div className="barcode-city-code">
      <button
        type="button"
        className={`barcode-artboard ${mode}`}
        onClick={() => setMode((current) => (current === "barcode" ? "city" : "barcode"))}
        aria-label={mode === "barcode" ? "Show barcode streetscape" : "Show scannable barcode"}
        aria-pressed={mode === "city"}
        title="Tap to switch between the barcode and streetscape"
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
  const layout = useMemo(() => createBarcodeLayout(binary), [binary]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const drawingCanvas = canvas;

    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const targetProgress = targetMode === "city" ? 1 : 0;
    let previousTime = performance.now();

    if (animationRef.current !== null) {
      cancelAnimationFrame(animationRef.current);
    }

    drawBarcodeCity(drawingCanvas, layout, easeInOutCubic(progressRef.current));

    function renderFrame(time: number) {
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

      drawBarcodeCity(drawingCanvas, layout, easeInOutCubic(progressRef.current));

      if (progressRef.current !== targetProgress) {
        animationRef.current = requestAnimationFrame(renderFrame);
      }
    }

    animationRef.current = requestAnimationFrame(renderFrame);

    return () => {
      if (animationRef.current !== null) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, [layout, targetMode]);

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

function createBarcodeLayout(binary: string): BarcodeLayout {
  const sourceRuns: Array<{ width: number; dark: boolean; quiet: boolean }> = [
    { width: quietModules, dark: false, quiet: true },
  ];
  let cursor = 0;

  while (cursor < binary.length) {
    const start = cursor;
    const dark = binary[cursor] === "1";
    while (cursor < binary.length && binary[cursor] === binary[start]) cursor++;
    sourceRuns.push({ width: cursor - start, dark, quiet: false });
  }
  sourceRuns.push({ width: quietModules, dark: false, quiet: true });

  const totalModules = binary.length + quietModules * 2;
  const flatScale = flatSpan / Math.max(1, totalModules);
  const cityWeight = sourceRuns.reduce((total, run) => {
    if (run.quiet) return total;
    return total + (run.dark ? run.width * cityBuildingMultiplier : cityStreetModules);
  }, 0);
  const cityScale = citySpan / Math.max(1, cityWeight);
  const streetWidth = cityStreetModules * cityScale;
  const streets: Street[] = [];
  const runs: BarcodeRun[] = [];
  let flatCursor = -flatSpan / 2;
  let cityCursor = -citySpan / 2;
  let buildingIndex = 0;

  for (const source of sourceRuns) {
    const kind: RunKind = source.quiet ? "quiet" : source.dark ? "building" : "street";
    const flatWidth = source.width * flatScale;
    const cityWidth = source.quiet
      ? 0.0001
      : (source.dark ? source.width * cityBuildingMultiplier : cityStreetModules) * cityScale;
    const cityCenter = source.quiet
      ? cityCursor
      : cityCursor + cityWidth / 2;
    const palette = source.dark ? buildingIndex % buildingPalettes.length : 0;
    const cityHeight = source.dark
      ? 0.31 + Math.min(0.3, flatWidth * 6) + pseudoRandom(buildingIndex, source.width, 17) * 0.23
      : kind === "street"
        ? 0.012
        : 0.001;

    runs.push({
      kind,
      index: source.dark ? buildingIndex : runs.length,
      palette,
      flatCenter: flatCursor + flatWidth / 2,
      flatWidth,
      cityCenter,
      cityWidth,
      cityHeight,
    });

    flatCursor += flatWidth;
    if (!source.quiet) cityCursor += cityWidth;
    if (kind === "street") streets.push({ x: cityCenter, width: cityWidth });
    if (source.dark) buildingIndex++;
  }

  return {
    runs,
    props: createCityProps(streets, streetWidth),
    streetWidth,
    cityHalfWidth: citySpan / 2,
  };
}

function createCityProps(streets: Street[], streetWidth: number) {
  const props: CityProp[] = [];
  const carCount = Math.min(8, streets.length);

  for (let slot = 0; slot < carCount; slot++) {
    const street = streets[Math.min(streets.length - 1, Math.floor((slot * streets.length) / carCount))];
    props.push({
      x: street.x,
      z: 0.145 + (slot % 3) * 0.078,
      streetWidth: street.width,
      kind: "car",
      palette: slot % carColors.length,
      direction: "cross",
    });
    if (slot % 2 === 0) {
      props.push({
        x: street.x,
        z: roadCenter + street.width * 0.16,
        streetWidth: street.width,
        kind: "signal",
        palette: 0,
        direction: "cross",
      });
    }
  }

  for (let slot = 0; slot < 3; slot++) {
    props.push({
      x: -citySpan * 0.27 + slot * citySpan * 0.27,
      z: roadCenter + (slot % 2 === 0 ? -1 : 1) * streetWidth * 0.16,
      streetWidth,
      kind: "car",
      palette: (slot + 1) % carColors.length,
      direction: "avenue",
    });
  }

  if (streets.length >= 3) {
    for (let fraction = 1; fraction <= 2; fraction++) {
      const street = streets[Math.min(streets.length - 1, Math.floor((fraction * streets.length) / 3))];
      props.push({
        x: street.x,
        z: roadCenter,
        streetWidth,
        kind: "signal",
        palette: 0,
        direction: "avenue",
      });
    }
  }

  return props;
}

function drawBarcodeCity(canvas: HTMLCanvasElement, layout: BarcodeLayout, progress: number) {
  const context = prepareCanvas(canvas);
  if (!context) return;

  context.fillStyle = "#ffffff";
  context.fillRect(0, 0, canvasWidth, canvasHeight);

  if (progress < 0.001) {
    drawExactFlatBarcode(context, layout);
    return;
  }

  // Keep the avenue behind the still-flat bars so it cannot flash across the
  // scannable endpoint. Once the city has risen, blend a foreground pass in
  // so the nearer avenue correctly meets every cross street and facade.
  drawAvenue(context, layout, progress);

  const roadRuns = layout.runs.filter((run) => run.kind !== "building");
  for (const run of roadRuns) {
    drawRunSurface(context, run, layout, progress);
  }
  for (const run of roadRuns) {
    if (run.kind === "street") drawCrossStreetMarkings(context, run, layout, progress);
  }

  const buildings = layout.runs.filter((run) => run.kind === "building").reverse();
  for (const run of buildings) {
    drawBuilding(context, run, layout, progress);
  }

  const foregroundRoadAmount = smoothstep(0.66, 0.94, progress);
  if (foregroundRoadAmount > 0) {
    context.save();
    context.globalAlpha = foregroundRoadAmount;
    drawAvenue(context, layout, progress);
    context.restore();
  }

  drawProps(context, layout, progress);
}

function prepareCanvas(canvas: HTMLCanvasElement) {
  const dpr = window.devicePixelRatio || 1;
  const width = Math.round(canvasWidth * dpr);
  const height = Math.round(canvasHeight * dpr);
  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
  }

  const context = canvas.getContext("2d");
  if (!context) return null;
  context.setTransform(dpr, 0, 0, dpr, 0, 0);
  context.clearRect(0, 0, canvasWidth, canvasHeight);
  context.imageSmoothingEnabled = false;
  return context;
}

function drawExactFlatBarcode(context: CanvasRenderingContext2D, layout: BarcodeLayout) {
  const scaleX = 196;
  const scaleY = 185;
  const left = canvasWidth / 2 - (flatSpan * scaleX) / 2;
  const top = canvasHeight / 2 - (flatDepth * scaleY) / 2;
  const height = flatDepth * scaleY;

  context.fillStyle = paleBarcode;
  context.fillRect(Math.floor(left), Math.floor(top), Math.ceil(flatSpan * scaleX), Math.ceil(height));

  for (const run of layout.runs) {
    if (run.kind !== "building") continue;
    const x = canvasWidth / 2 + (run.flatCenter - run.flatWidth / 2) * scaleX;
    context.fillStyle = buildingPalettes[run.palette].front;
    context.fillRect(Math.floor(x), Math.floor(top), Math.ceil(run.flatWidth * scaleX), Math.ceil(height));
  }
}

function drawAvenue(
  context: CanvasRenderingContext2D,
  layout: BarcodeLayout,
  progress: number,
) {
  const roadVisibility = smoothstep(0.34, 0.78, progress);
  if (roadVisibility <= 0) return;
  const roadAmount = smoothstep(0.25, 0.9, progress);
  const roadHeight = lerp(0, 0.012, smoothstep(0.28, 0.82, progress));
  const halfStreet = layout.streetWidth / 2;

  context.save();
  context.globalAlpha *= roadVisibility;
  drawWorldQuad(
    context,
    [
      { x: -layout.cityHalfWidth, y: roadHeight, z: roadCenter - halfStreet },
      { x: layout.cityHalfWidth, y: roadHeight, z: roadCenter - halfStreet },
      { x: layout.cityHalfWidth, y: roadHeight, z: roadCenter + halfStreet },
      { x: -layout.cityHalfWidth, y: roadHeight, z: roadCenter + halfStreet },
    ],
    progress,
    mixColor("#ffffff", asphalt, roadAmount),
  );

  const markingAmount = smoothstep(0.52, 0.92, progress);
  if (markingAmount > 0) {
    context.globalAlpha *= markingAmount;
    const lineHalfWidth = layout.streetWidth * 0.13;
    for (let x = -layout.cityHalfWidth; x < layout.cityHalfWidth; x += 0.15) {
      drawWorldQuad(
        context,
        [
          { x, y: roadHeight + 0.001, z: roadCenter - lineHalfWidth },
          { x: Math.min(layout.cityHalfWidth, x + 0.075), y: roadHeight + 0.001, z: roadCenter - lineHalfWidth },
          { x: Math.min(layout.cityHalfWidth, x + 0.075), y: roadHeight + 0.001, z: roadCenter + lineHalfWidth },
          { x, y: roadHeight + 0.001, z: roadCenter + lineHalfWidth },
        ],
        progress,
        whiteMarking,
      );
    }
  }
  context.restore();
}

function drawRunSurface(
  context: CanvasRenderingContext2D,
  run: BarcodeRun,
  layout: BarcodeLayout,
  progress: number,
) {
  const geometry = getRunGeometry(run, layout, progress);
  const roadAmount = smoothstep(0.25, 0.9, progress);
  const fill = run.kind === "quiet"
    ? mixColor(paleBarcode, "#ffffff", progress)
    : mixColor(paleBarcode, asphalt, roadAmount);

  drawWorldQuad(
    context,
    [
      { x: geometry.x0, y: geometry.height, z: geometry.z0 },
      { x: geometry.x1, y: geometry.height, z: geometry.z0 },
      { x: geometry.x1, y: geometry.height, z: geometry.z1 },
      { x: geometry.x0, y: geometry.height, z: geometry.z1 },
    ],
    progress,
    fill,
  );
}

function drawCrossStreetMarkings(
  context: CanvasRenderingContext2D,
  run: BarcodeRun,
  layout: BarcodeLayout,
  progress: number,
) {
  const markingAmount = smoothstep(0.52, 0.92, progress);
  if (markingAmount <= 0) return;
  const geometry = getRunGeometry(run, layout, progress);
  const lineHalfWidth = (geometry.x1 - geometry.x0) * 0.13;
  const centerX = (geometry.x0 + geometry.x1) / 2;

  context.save();
  context.globalAlpha = markingAmount;
  for (let z = geometry.z0 + layout.streetWidth * 0.72; z < geometry.z1; z += 0.15) {
    drawWorldQuad(
      context,
      [
        { x: centerX - lineHalfWidth, y: geometry.height + 0.001, z },
        { x: centerX + lineHalfWidth, y: geometry.height + 0.001, z },
        { x: centerX + lineHalfWidth, y: geometry.height + 0.001, z: Math.min(geometry.z1, z + 0.075) },
        { x: centerX - lineHalfWidth, y: geometry.height + 0.001, z: Math.min(geometry.z1, z + 0.075) },
      ],
      progress,
      whiteMarking,
    );
  }
  context.restore();
}

function drawBuilding(
  context: CanvasRenderingContext2D,
  run: BarcodeRun,
  layout: BarcodeLayout,
  progress: number,
) {
  const geometry = getRunGeometry(run, layout, progress);
  const palette = buildingPalettes[run.palette];
  const topNearLeft = projectPoint({ x: geometry.x0, y: geometry.height, z: geometry.z0 }, progress);
  const topNearRight = projectPoint({ x: geometry.x1, y: geometry.height, z: geometry.z0 }, progress);
  const topFarRight = projectPoint({ x: geometry.x1, y: geometry.height, z: geometry.z1 }, progress);
  const topFarLeft = projectPoint({ x: geometry.x0, y: geometry.height, z: geometry.z1 }, progress);
  const baseNearLeft = projectPoint({ x: geometry.x0, y: 0, z: geometry.z0 }, progress);
  const baseNearRight = projectPoint({ x: geometry.x1, y: 0, z: geometry.z0 }, progress);
  const baseFarLeft = projectPoint({ x: geometry.x0, y: 0, z: geometry.z1 }, progress);
  const cityAmount = smoothstep(0.08, 0.72, progress);

  context.strokeStyle = `rgba(7, 12, 20, ${0.04 + cityAmount * 0.1})`;
  context.lineWidth = 0.55;
  drawPolygon(context, [topFarLeft, topNearLeft, baseNearLeft, baseFarLeft], mixColor(palette.front, palette.side, cityAmount), true);
  drawPolygon(context, [topNearLeft, topNearRight, baseNearRight, baseNearLeft], palette.front, true);
  drawPolygon(context, [topNearLeft, topNearRight, topFarRight, topFarLeft], mixColor(palette.front, palette.roof, cityAmount), true);

  if (progress > 0.34) {
    drawWindows(context, run, topNearLeft, topNearRight, baseNearLeft, progress);
  }
}

function drawWindows(
  context: CanvasRenderingContext2D,
  run: BarcodeRun,
  topLeft: Point,
  topRight: Point,
  bottomLeft: Point,
  progress: number,
) {
  const width = topRight.x - topLeft.x;
  const height = bottomLeft.y - topLeft.y;
  if (width < 2.4 || height < 24) return;
  const palette = buildingPalettes[run.palette];
  const columns = Math.max(1, Math.min(3, Math.floor(width / 4.4)));
  const rows = Math.max(3, Math.min(11, Math.floor(height / 10)));
  const cellWidth = Math.max(0.7, Math.min(1.8, width / Math.max(3, columns * 2.5)));

  context.save();
  context.globalAlpha = smoothstep(0.34, 0.9, progress) * 0.78;
  context.fillStyle = palette.window;
  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < columns; col++) {
      if (pseudoRandom(run.index + col, row, 31) < 0.28) continue;
      const x = topLeft.x + width * ((col + 1) / (columns + 1)) - cellWidth / 2;
      const y = topLeft.y + 9 + row * Math.max(5, (height - 16) / rows);
      context.fillRect(x, y, cellWidth, 1.6);
    }
  }
  context.restore();
}

function getRunGeometry(run: BarcodeRun, layout: BarcodeLayout, progress: number): RunGeometry {
  const xCenter = lerp(run.flatCenter, run.cityCenter, progress);
  const width = lerp(run.flatWidth, run.cityWidth, progress);
  const avenueRearEdge = roadCenter + layout.streetWidth / 2;
  const cityZ0 = run.kind === "quiet" ? 0.28 : avenueRearEdge;
  const cityZ1 = run.kind === "street" ? 0.49 : run.kind === "building" ? 0.45 : 0.281;
  const z0 = lerp(-flatDepth / 2, cityZ0, progress);
  const z1 = lerp(flatDepth / 2, cityZ1, progress);
  const height = lerp(0.006, run.cityHeight, progress);

  return {
    x0: xCenter - width / 2,
    x1: xCenter + width / 2,
    z0,
    z1,
    height,
  };
}

function drawProps(context: CanvasRenderingContext2D, layout: BarcodeLayout, progress: number) {
  const visibility = smoothstep(0.38, 0.9, progress);
  if (visibility <= 0) return;
  for (const prop of layout.props) {
    if (prop.kind === "car") drawCar(context, prop, progress, visibility);
    else drawTrafficSignal(context, prop, progress, visibility);
  }
}

function drawCar(
  context: CanvasRenderingContext2D,
  prop: CityProp,
  progress: number,
  visibility: number,
) {
  const lane = Math.max(prop.streetWidth, 0.018);
  const avenue = prop.direction === "avenue";
  const bodySize = avenue
    ? { x: lane * 1.46, y: 0.034, z: lane * 0.64 }
    : { x: lane * 0.64, y: 0.034, z: lane * 1.46 };
  const roofSize = avenue
    ? { x: lane * 0.72, y: 0.024, z: lane * 0.46 }
    : { x: lane * 0.46, y: 0.024, z: lane * 0.72 };
  drawWorldCuboid(
    context,
    { x: prop.x, y: 0.029, z: prop.z },
    scaleSize(bodySize, visibility),
    progress,
    carColors[prop.palette % carColors.length],
  );
  drawWorldCuboid(
    context,
    { x: prop.x, y: 0.058, z: prop.z },
    scaleSize(roofSize, visibility),
    progress,
    mixColor(carColors[prop.palette % carColors.length], "#ffffff", 0.2),
  );
}

function drawTrafficSignal(
  context: CanvasRenderingContext2D,
  prop: CityProp,
  progress: number,
  visibility: number,
) {
  const lane = Math.max(prop.streetWidth, 0.018);
  const avenue = prop.direction === "avenue";
  const poleBase = avenue
    ? { x: prop.x, y: 0.012, z: prop.z + lane * 0.32 }
    : { x: prop.x + lane * 0.32, y: 0.012, z: prop.z };
  const poleTop = { ...poleBase, y: 0.143 * visibility };
  const signalTop = { x: prop.x, y: 0.143 * visibility, z: prop.z };
  const signal = { x: prop.x, y: 0.092 * visibility, z: prop.z };

  context.save();
  context.strokeStyle = "#292f38";
  context.lineCap = "square";
  context.lineWidth = Math.max(0.8, visibility * 1.35);
  drawWorldLine(context, poleBase, poleTop, progress);
  drawWorldLine(context, poleTop, signalTop, progress);
  drawWorldLine(context, signalTop, signal, progress);
  const projected = projectPoint(signal, progress);
  context.fillStyle = "#ffc429";
  context.fillRect(projected.x - 1.5 * visibility, projected.y - 2.2 * visibility, 3 * visibility, 4.4 * visibility);
  context.restore();
}

function drawWorldCuboid(
  context: CanvasRenderingContext2D,
  center: Point3,
  size: Point3,
  progress: number,
  color: string,
) {
  const x0 = center.x - size.x / 2;
  const x1 = center.x + size.x / 2;
  const y0 = center.y - size.y / 2;
  const y1 = center.y + size.y / 2;
  const z0 = center.z - size.z / 2;
  const z1 = center.z + size.z / 2;
  const top = [
    projectPoint({ x: x0, y: y1, z: z0 }, progress),
    projectPoint({ x: x1, y: y1, z: z0 }, progress),
    projectPoint({ x: x1, y: y1, z: z1 }, progress),
    projectPoint({ x: x0, y: y1, z: z1 }, progress),
  ];
  const nearBase = [
    projectPoint({ x: x0, y: y0, z: z0 }, progress),
    projectPoint({ x: x1, y: y0, z: z0 }, progress),
  ];

  drawPolygon(context, [top[0], top[1], nearBase[1], nearBase[0]], mixColor(color, "#111827", 0.22), true);
  drawPolygon(context, top, mixColor(color, "#ffffff", 0.16), true);
}

function scaleSize(size: Point3, amount: number): Point3 {
  return { x: size.x * amount, y: size.y * amount, z: size.z * amount };
}

function drawWorldLine(
  context: CanvasRenderingContext2D,
  from: Point3,
  to: Point3,
  progress: number,
) {
  const start = projectPoint(from, progress);
  const end = projectPoint(to, progress);
  context.beginPath();
  context.moveTo(start.x, start.y);
  context.lineTo(end.x, end.y);
  context.stroke();
}

function drawWorldQuad(
  context: CanvasRenderingContext2D,
  points: Point3[],
  progress: number,
  fill: string,
) {
  drawPolygon(context, points.map((point) => projectPoint(point, progress)), fill);
}

function projectPoint(point: Point3, progress: number): Point {
  const yaw = lerp(0, 0.245, progress);
  const pitch = lerp(-Math.PI / 2, -0.575, progress);
  const cosYaw = Math.cos(yaw);
  const sinYaw = Math.sin(yaw);
  const cosPitch = Math.cos(pitch);
  const sinPitch = Math.sin(pitch);
  const rotatedX = point.x * cosYaw - point.z * sinYaw;
  const rotatedZ = point.x * sinYaw + point.z * cosYaw;
  const rotatedY = point.y * cosPitch - rotatedZ * sinPitch;
  const scaleX = lerp(196, 180, progress);
  const scaleY = lerp(185, 225, progress);
  const horizontalOffset = lerp(0, 0.068, progress);
  const centerY = lerp(canvasHeight / 2, 236, progress);

  return {
    x: canvasWidth / 2 + (rotatedX + horizontalOffset) * scaleX,
    y: centerY - rotatedY * scaleY,
  };
}

function drawPolygon(
  context: CanvasRenderingContext2D,
  points: Point[],
  fill: string,
  stroke = false,
) {
  if (points.length === 0) return;
  context.beginPath();
  context.moveTo(points[0].x, points[0].y);
  for (const point of points.slice(1)) context.lineTo(point.x, point.y);
  context.closePath();
  context.fillStyle = fill;
  context.fill();
  if (stroke) context.stroke();
}

function easeInOutCubic(value: number) {
  return value < 0.5 ? 4 * value * value * value : 1 - Math.pow(-2 * value + 2, 3) / 2;
}

function smoothstep(edge0: number, edge1: number, value: number) {
  const amount = Math.max(0, Math.min(1, (value - edge0) / (edge1 - edge0)));
  return amount * amount * (3 - 2 * amount);
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

function hexToRgb(value: string) {
  const hex = value.replace("#", "");
  return {
    r: Number.parseInt(hex.slice(0, 2), 16),
    g: Number.parseInt(hex.slice(2, 4), 16),
    b: Number.parseInt(hex.slice(4, 6), 16),
  };
}

function pseudoRandom(column: number, row: number, seed: number) {
  const value = Math.sin((column + 1) * 91.73 + (row + 1) * 57.31 + seed * 19.19) * 10000;
  return value - Math.floor(value);
}
