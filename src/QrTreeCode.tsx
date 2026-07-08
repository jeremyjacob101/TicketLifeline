import { ScanQrCode, TreePine } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";

type QrTreeCodeProps = {
  matrix: string;
  size: number;
};

type QrViewMode = "qr" | "tree";
type GroundType = "path" | "grass" | "trunk" | "petal";
type BlockType = "grass" | "trunk" | "blossom";
type Point = { x: number; y: number };
type SceneMatrix = { matrix: string; size: number };
type Block = {
  col: number;
  row: number;
  base: number;
  height: number;
  type: BlockType;
  depth: number;
};

const canvasWidth = 360;
const canvasHeight = 310;
const quietModules = 4;
const maxSceneSize = 53;
const blockPalettes: Record<
  BlockType,
  { top: string; left: string; right: string; front: string }
> = {
  trunk: {
    top: "#9a6a43",
    left: "#5e3d2b",
    right: "#714c33",
    front: "#7d5235",
  },
  grass: {
    top: "#71a652",
    left: "#3f6b38",
    right: "#568742",
    front: "#4a783d",
  },
  blossom: {
    top: "#ffd2dc",
    left: "#c87890",
    right: "#e99bad",
    front: "#d6889d",
  },
};
const flatBlossomPixels = ["#8f3f5a", "#a54b66", "#b85d77", "#c46c84"];

export function QrTreeCode({ matrix, size }: QrTreeCodeProps) {
  const [mode, setMode] = useState<QrViewMode>("qr");

  return (
    <div className="qr-tree-code">
      <div className="qr-mode-toggle" role="group" aria-label="QR view">
        <button
          type="button"
          className={mode === "qr" ? "active" : ""}
          onClick={() => setMode("qr")}
          title="Overhead QR view"
          aria-pressed={mode === "qr"}
        >
          <ScanQrCode size={15} />
          <span>QR</span>
        </button>
        <button
          type="button"
          className={mode === "tree" ? "active" : ""}
          onClick={() => setMode("tree")}
          title="3D tree view"
          aria-pressed={mode === "tree"}
        >
          <TreePine size={15} />
          <span>Tree</span>
        </button>
      </div>
      <button
        type="button"
        className={`qr-artboard ${mode}`}
        onClick={() => setMode((current) => (current === "qr" ? "tree" : "qr"))}
        aria-label={mode === "qr" ? "Show 3D tree view" : "Show overhead QR view"}
      >
        <AnimatedQrTreeCanvas matrix={matrix} size={size} targetMode={mode} />
      </button>
    </div>
  );
}

function AnimatedQrTreeCanvas({
  matrix,
  size,
  targetMode,
}: QrTreeCodeProps & { targetMode: QrViewMode }) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const animationRef = useRef<number | null>(null);
  const progressRef = useRef(targetMode === "tree" ? 1 : 0);
  const sceneMatrix = useMemo(() => createSceneMatrix(matrix, size), [matrix, size]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const targetProgress = targetMode === "tree" ? 1 : 0;
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
          (targetProgress - progressRef.current) * Math.min(1, deltaSeconds * 5.5);
        if (Math.abs(progressRef.current - targetProgress) < 0.002) {
          progressRef.current = targetProgress;
        }
      }

      drawQrTree(canvas, matrix, size, sceneMatrix, easeInOutCubic(progressRef.current));

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
  }, [matrix, sceneMatrix, size, targetMode]);

  return (
    <span className="qr-tree-stage">
      <canvas
        ref={canvasRef}
        className="qr-tree-canvas"
        width={canvasWidth}
        height={canvasHeight}
        aria-hidden="true"
      />
    </span>
  );
}

function drawQrTree(
  canvas: HTMLCanvasElement,
  matrix: string,
  size: number,
  sceneMatrix: SceneMatrix,
  progress: number,
) {
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.round(canvasWidth * dpr);
  canvas.height = Math.round(canvasHeight * dpr);
  canvas.style.width = `${canvasWidth}px`;
  canvas.style.height = `${canvasHeight}px`;

  const context = canvas.getContext("2d");
  if (!context) return;

  context.setTransform(dpr, 0, 0, dpr, 0, 0);
  context.clearRect(0, 0, canvasWidth, canvasHeight);
  context.imageSmoothingEnabled = false;
  drawBackdrop(context, progress);

  const flatOpacity = 1 - smoothstep(0.06, 0.34, progress);
  const sceneOpacity = smoothstep(0.02, 0.22, progress);

  if (sceneOpacity > 0) {
    context.save();
    context.globalAlpha = sceneOpacity;
    drawProjectedScene(context, sceneMatrix, progress);
    context.restore();
  }

  if (flatOpacity > 0) {
    context.save();
    context.globalAlpha = flatOpacity;
    drawFlatColoredQr(context, matrix, size);
    context.restore();
  }
}

function drawBackdrop(context: CanvasRenderingContext2D, progress: number) {
  const gradient = context.createLinearGradient(0, 0, 0, canvasHeight);
  gradient.addColorStop(0, mixColor("#f8f6ef", "#eef5f2", progress));
  gradient.addColorStop(0.62, mixColor("#fbfaf5", "#f9faf4", progress));
  gradient.addColorStop(1, mixColor("#f1eee5", "#e7efe4", progress));
  context.fillStyle = gradient;
  context.fillRect(0, 0, canvasWidth, canvasHeight);

  context.save();
  context.globalAlpha = 0.1 + progress * 0.12;
  context.fillStyle = "#1d3f35";
  context.beginPath();
  context.ellipse(182, 258, 116, 26, 0, 0, Math.PI * 2);
  context.fill();
  context.restore();
}

function drawFlatColoredQr(context: CanvasRenderingContext2D, matrix: string, size: number) {
  const totalSize = size + quietModules * 2;
  const squareSize = Math.min(286, canvasWidth - 58, canvasHeight - 36);
  const cell = squareSize / totalSize;
  const originX = (canvasWidth - squareSize) / 2;
  const originY = (canvasHeight - squareSize) / 2;

  context.fillStyle = "#f8f6ef";
  context.fillRect(originX, originY, squareSize, squareSize);

  for (let row = -quietModules; row < size + quietModules; row++) {
    for (let col = -quietModules; col < size + quietModules; col++) {
      const x = originX + (col + quietModules) * cell;
      const y = originY + (row + quietModules) * cell;
      const dark = isDarkModule(matrix, size, col, row);
      const fill = dark
        ? getFlatModuleFill(col, row, size)
        : getLightTileFill(col, row, 0);

      context.fillStyle = fill;
      context.fillRect(Math.floor(x), Math.floor(y), Math.ceil(cell), Math.ceil(cell));
    }
  }
}

function drawProjectedScene(
  context: CanvasRenderingContext2D,
  sceneMatrix: SceneMatrix,
  progress: number,
) {
  const totalSize = sceneMatrix.size + quietModules * 2;
  const metrics = createProjectionMetrics(totalSize);
  const blocks: Block[] = [];

  for (let row = -quietModules; row < sceneMatrix.size + quietModules; row++) {
    for (let col = -quietModules; col < sceneMatrix.size + quietModules; col++) {
      const dark = isDarkModule(sceneMatrix.matrix, sceneMatrix.size, col, row);
      const type = classifyGround(col, row, sceneMatrix.size, dark);
      const gridCol = col + quietModules;
      const gridRow = row + quietModules;
      drawGroundCell(context, gridCol, gridRow, type, progress, metrics);

      const ornamentalBlossom =
        !dark && progress > 0.24 && shouldAddOrnamentalBlossom(col, row, sceneMatrix.size);

      if ((!dark && !ornamentalBlossom) || progress < 0.04) continue;

      const block = createBlock(col, row, sceneMatrix.size, ornamentalBlossom);
      if (block) {
        blocks.push({
          ...block,
          col: gridCol,
          row: gridRow,
          base: block.base * progress,
          height: block.height * smoothstep(0.06, 1, progress),
          depth: gridCol + gridRow + block.base / 90,
        });
      }
    }
  }

  blocks
    .sort((a, b) => a.depth - b.depth)
    .forEach((block) => drawCuboid(context, block, progress, metrics));

  if (progress > 0.72) {
    drawPetalSpecks(context, progress);
  }
}

function drawGroundCell(
  context: CanvasRenderingContext2D,
  col: number,
  row: number,
  type: GroundType,
  progress: number,
  metrics: ReturnType<typeof createProjectionMetrics>,
) {
  const points = [
    projectPoint(col, row, 0, progress, metrics),
    projectPoint(col + 1, row, 0, progress, metrics),
    projectPoint(col + 1, row + 1, 0, progress, metrics),
    projectPoint(col, row + 1, 0, progress, metrics),
  ];

  context.fillStyle = getGroundFill(type, col, row, progress);
  context.strokeStyle = `rgba(44, 58, 46, ${0.03 + progress * 0.1})`;
  context.lineWidth = 0.45;
  drawPolygon(context, points);

  if (type === "grass" && progress > 0.72 && pseudoRandom(col, row, 41) > 0.47) {
    drawGrassTuft(context, points, progress);
  }
}

function drawCuboid(
  context: CanvasRenderingContext2D,
  block: Block,
  progress: number,
  metrics: ReturnType<typeof createProjectionMetrics>,
) {
  const base = block.base;
  const top = block.base + block.height;
  const c = block.col;
  const r = block.row;
  const topPoints = [
    projectPoint(c, r, top, progress, metrics),
    projectPoint(c + 1, r, top, progress, metrics),
    projectPoint(c + 1, r + 1, top, progress, metrics),
    projectPoint(c, r + 1, top, progress, metrics),
  ];
  const basePoints = [
    projectPoint(c, r, base, progress, metrics),
    projectPoint(c + 1, r, base, progress, metrics),
    projectPoint(c + 1, r + 1, base, progress, metrics),
    projectPoint(c, r + 1, base, progress, metrics),
  ];
  const palette = getBlockPalette(block.type);

  context.strokeStyle = `rgba(42, 39, 35, ${0.06 + progress * 0.08})`;
  context.lineWidth = 0.45;
  context.fillStyle = palette.left;
  drawPolygon(context, [topPoints[3], topPoints[2], basePoints[2], basePoints[3]]);
  context.fillStyle = palette.right;
  drawPolygon(context, [topPoints[1], topPoints[2], basePoints[2], basePoints[1]]);
  context.fillStyle = palette.front;
  drawPolygon(context, [topPoints[0], topPoints[1], basePoints[1], basePoints[0]]);
  context.fillStyle = palette.top;
  drawPolygon(context, topPoints);
}

function createProjectionMetrics(totalSize: number) {
  const flatSquare = Math.min(286, canvasWidth - 58, canvasHeight - 36);
  const flatCell = flatSquare / totalSize;
  const isoTileW = Math.min(8.5, (canvasWidth - 54) / totalSize);
  const isoTileH = isoTileW * 0.56;
  const expectedTreeHeight = Math.min(108, Math.max(88, totalSize * 1.72));
  const projectedBaseHeight = totalSize * isoTileH;
  const centeredIsoOriginY =
    canvasHeight * 0.5 - (projectedBaseHeight - expectedTreeHeight) / 2;

  return {
    flatCell,
    flatX: (canvasWidth - flatSquare) / 2,
    flatY: (canvasHeight - flatSquare) / 2,
    isoOriginX: canvasWidth / 2,
    isoOriginY: centeredIsoOriginY,
    isoTileW,
    isoTileH,
  };
}

function projectPoint(
  col: number,
  row: number,
  elevation: number,
  progress: number,
  metrics: ReturnType<typeof createProjectionMetrics>,
) {
  const flatX = metrics.flatX + col * metrics.flatCell;
  const flatY = metrics.flatY + row * metrics.flatCell;
  const isoX = metrics.isoOriginX + (col - row) * (metrics.isoTileW / 2);
  const isoY = metrics.isoOriginY + (col + row) * (metrics.isoTileH / 2) - elevation;

  return {
    x: lerp(flatX, isoX, progress),
    y: lerp(flatY, isoY, progress),
  };
}

function createBlock(
  col: number,
  row: number,
  size: number,
  ornamentalBlossom = false,
): Block | null {
  const center = (size - 1) / 2;
  const distance = distanceFromCenter(col, row, center);
  const trunkRadius = Math.max(1.8, size * 0.07);
  const canopyRadius = size * 0.47;

  if (distance < trunkRadius) {
    return {
      col,
      row,
      base: 0,
      height: 42 + pseudoRandom(col, row, 5) * 8,
      type: "trunk",
      depth: 0,
    };
  }

  if (distance < canopyRadius) {
    const fullness = 1 - distance / canopyRadius;
    if (!ornamentalBlossom && fullness < 0.24 && pseudoRandom(col, row, 29) < 0.34) {
      return null;
    }

    return {
      col,
      row,
      base: 34 + fullness * 25 + pseudoRandom(col, row, 7) * 10,
      height:
        7 +
        fullness * 31 +
        pseudoRandom(col, row, ornamentalBlossom ? 43 : 11) * 11,
      type: "blossom",
      depth: 0,
    };
  }

  if (pseudoRandom(col, row, 13) > 0.36) {
    return {
      col,
      row,
      base: 0,
      height: 4 + pseudoRandom(col, row, 17) * 5,
      type: "grass",
      depth: 0,
    };
  }

  return null;
}

function shouldAddOrnamentalBlossom(col: number, row: number, size: number) {
  const center = (size - 1) / 2;
  const distance = distanceFromCenter(col, row, center);
  const canopyRadius = size * 0.43;
  if (distance >= canopyRadius) return false;

  const fullness = 1 - distance / canopyRadius;
  return pseudoRandom(col, row, 61) > 0.88 - fullness * 0.22;
}

function classifyGround(col: number, row: number, size: number, dark: boolean): GroundType {
  if (!dark) return "path";

  const center = (size - 1) / 2;
  const distance = distanceFromCenter(col, row, center);
  if (distance < Math.max(1.8, size * 0.07)) return "trunk";
  if (distance < size * 0.47) return "petal";
  return "grass";
}

function getGroundFill(
  type: GroundType,
  col: number,
  row: number,
  progress: number,
) {
  if (type === "path") {
    return getLightTileFill(col, row, progress);
  }
  if (type === "trunk") {
    return mixColor(getFlatModuleFill(col, row, 21), "#7a5639", progress);
  }
  if (type === "petal") {
    return mixColor(getFlatModuleFill(col, row, 21), blockPalettes.blossom.left, progress * 0.72);
  }
  return mixColor(getFlatModuleFill(col, row, 21), "#4f873e", progress * 0.6);
}

function getLightTileFill(col: number, row: number, progress: number) {
  const colors = ["#f8f6ef", "#eeeadd", "#e6e0d2", "#f4f1e7"];
  const flat = colors[Math.floor(pseudoRandom(col, row, 3) * colors.length)];
  return mixColor(flat, "#e9e7dc", progress * 0.45);
}

function getFlatModuleFill(col: number, row: number, size: number) {
  const type = classifyGround(col, row, size, true);

  if (type === "petal") {
    return flatBlossomPixels[Math.floor(pseudoRandom(col, row, 23) * flatBlossomPixels.length)];
  }

  const center = (size - 1) / 2;
  const distance = distanceFromCenter(col, row, center);
  if (distance < Math.max(1.8, size * 0.07)) return blockPalettes.trunk.front;

  const colors = [
    blockPalettes.grass.left,
    blockPalettes.grass.right,
    blockPalettes.grass.front,
    blockPalettes.grass.top,
  ];
  return colors[Math.floor(pseudoRandom(col, row, 23) * colors.length)];
}

function getBlockPalette(type: BlockType) {
  return blockPalettes[type];
}

function drawGrassTuft(
  context: CanvasRenderingContext2D,
  points: Point[],
  progress: number,
) {
  const center = {
    x: (points[0].x + points[1].x + points[2].x + points[3].x) / 4,
    y: (points[0].y + points[1].y + points[2].y + points[3].y) / 4,
  };
  const height = 4 * progress;

  context.save();
  context.globalAlpha *= progress;
  context.strokeStyle = "#71a652";
  context.lineWidth = 0.9;
  context.beginPath();
  context.moveTo(center.x - 2, center.y + 1);
  context.lineTo(center.x - 1, center.y - height);
  context.moveTo(center.x, center.y + 1);
  context.lineTo(center.x + 1, center.y - height * 1.15);
  context.moveTo(center.x + 2, center.y + 1);
  context.lineTo(center.x + 2.5, center.y - height * 0.8);
  context.stroke();
  context.restore();
}

function drawPetalSpecks(context: CanvasRenderingContext2D, progress: number) {
  context.save();
  context.globalAlpha = (progress - 0.72) / 0.28;

  for (let index = 0; index < 28; index++) {
    const x = 55 + pseudoRandom(index, 4, 80) * 250;
    const y = 176 + pseudoRandom(index, 9, 81) * 82;
    context.fillStyle = index % 3 === 0 ? "#ffd2dc" : "#e99bad";
    context.beginPath();
    context.ellipse(x, y, 1.7, 0.9, pseudoRandom(index, 1, 82) * Math.PI, 0, Math.PI * 2);
    context.fill();
  }

  context.restore();
}

function drawPolygon(context: CanvasRenderingContext2D, points: Point[]) {
  context.beginPath();
  context.moveTo(points[0].x, points[0].y);
  for (const point of points.slice(1)) {
    context.lineTo(point.x, point.y);
  }
  context.closePath();
  context.fill();
  context.stroke();
}

function createSceneMatrix(matrix: string, size: number): SceneMatrix {
  if (size <= maxSceneSize) {
    return { matrix, size };
  }

  let value = "";
  const scale = size / maxSceneSize;

  for (let row = 0; row < maxSceneSize; row++) {
    const startRow = Math.floor(row * scale);
    const endRow = Math.max(startRow + 1, Math.floor((row + 1) * scale));

    for (let col = 0; col < maxSceneSize; col++) {
      const startCol = Math.floor(col * scale);
      const endCol = Math.max(startCol + 1, Math.floor((col + 1) * scale));
      let dark = 0;
      let total = 0;

      for (let sourceRow = startRow; sourceRow < Math.min(size, endRow); sourceRow++) {
        for (let sourceCol = startCol; sourceCol < Math.min(size, endCol); sourceCol++) {
          total++;
          if (matrix[sourceRow * size + sourceCol] === "1") {
            dark++;
          }
        }
      }

      value += dark / Math.max(1, total) > 0.44 ? "1" : "0";
    }
  }

  return { matrix: value, size: maxSceneSize };
}

function isDarkModule(matrix: string, size: number, col: number, row: number) {
  return col >= 0 && row >= 0 && col < size && row < size
    ? matrix[row * size + col] === "1"
    : false;
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

function hexToRgb(value: string) {
  const hex = value.replace("#", "");
  return {
    r: Number.parseInt(hex.slice(0, 2), 16),
    g: Number.parseInt(hex.slice(2, 4), 16),
    b: Number.parseInt(hex.slice(4, 6), 16),
  };
}

function distanceFromCenter(col: number, row: number, center: number) {
  const dx = col - center;
  const dy = row - center;
  return Math.sqrt(dx * dx + dy * dy);
}

function pseudoRandom(col: number, row: number, seed: number) {
  const value = Math.sin((col + 1) * 91.73 + (row + 1) * 57.31 + seed * 19.19) * 10000;
  return value - Math.floor(value);
}
