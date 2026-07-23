const maxVisualMatrixLength = 40_000;

export function assertVisualMatrix(
  value: string | undefined,
  size: number | undefined,
  width: number | undefined,
  height: number | undefined,
) {
  if (!value && size === undefined && width === undefined && height === undefined) {
    return;
  }

  const resolvedWidth = width ?? size;
  const resolvedHeight = height ?? size;
  if (!value || resolvedWidth === undefined || resolvedHeight === undefined) {
    throw new Error("Code matrix data is incomplete.");
  }
  if (
    !Number.isInteger(resolvedWidth) ||
    !Number.isInteger(resolvedHeight) ||
    resolvedWidth < 1 ||
    resolvedHeight < 1 ||
    resolvedHeight > maxVisualMatrixLength ||
    resolvedWidth > Math.floor(maxVisualMatrixLength / resolvedHeight)
  ) {
    throw new Error("Code matrix dimensions are invalid.");
  }

  // visualSize is the legacy square-dimension field. It describes the stored
  // matrix; it is not proof of a QR version and may include a preserved border
  // from an older verified client.
  if (size !== undefined) {
    if (!Number.isInteger(size) || size < 1) {
      throw new Error("Legacy matrix size is invalid.");
    }
    if (resolvedWidth !== size || resolvedHeight !== size) {
      throw new Error("Legacy matrix size does not match the code matrix dimensions.");
    }
  }

  if (value.length !== resolvedWidth * resolvedHeight) {
    throw new Error("Code matrix dimensions do not match its data.");
  }
  if (!/^[01]+$/.test(value)) {
    throw new Error("Code matrix data is invalid.");
  }
}
