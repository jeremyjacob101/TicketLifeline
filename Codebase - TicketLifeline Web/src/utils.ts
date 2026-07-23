export const httpUrlPattern = /https?:\/\/[^\s<>"'`]+/i;
export const bareWebUrlPattern =
  /^(?:www\.)?(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}(?::\d{2,5})?(?:[/?#][^\s<>"'`]*)?$/i;

function cleanUrlCandidate(value: string) {
  return value
    .trim()
    .replace(/^[([{<]+/u, "")
    .replace(/[),.;:!?}\]>]+$/u, "");
}

export function normalizeLaunchUrl(value: string) {
  const trimmed = cleanUrlCandidate(value);
  if (!trimmed) return "";

  const candidate = /^https?:\/\//i.test(trimmed) && !/\s/u.test(trimmed)
    ? trimmed
    : bareWebUrlPattern.test(trimmed)
      ? `https://${trimmed}`
      : "";
  if (!candidate) return "";

  try {
    const url = new URL(candidate);
    return url.protocol === "http:" || url.protocol === "https:" ? url.toString() : "";
  } catch {
    return "";
  }
}

export function inferLaunchUrlFromPayload(payload: string) {
  const directUrl = normalizeLaunchUrl(payload);
  if (directUrl) return directUrl;

  const embeddedUrl = payload.match(httpUrlPattern)?.[0];
  return embeddedUrl ? normalizeLaunchUrl(embeddedUrl) : "";
}

export function isHeicImage(file: File | Blob) {
  const type = file.type.toLowerCase();
  const name = "name" in file ? file.name.toLowerCase() : "";
  return (
    type === "image/heic" ||
    type === "image/heif" ||
    name.endsWith(".heic") ||
    name.endsWith(".heif")
  );
}

export async function normalizeImageFile(file: File): Promise<File | Blob> {
  if (!isHeicImage(file)) {
    return file;
  }

  try {
    const { default: heic2any } = await import("heic2any");
    const converted = await heic2any({
      blob: file,
      toType: "image/jpeg",
      quality: 0.96,
    });
    const blob = Array.isArray(converted) ? converted[0] : converted;
    if (!blob) {
      throw new Error("HEIC conversion returned no image.");
    }
    return blob;
  } catch {
    throw new Error(
      "Could not convert that HEIC/HEIF image in this browser. Try exporting it as JPEG/PNG, or paste the code payload manually.",
    );
  }
}

function isSupportedImageLike(file: File | Blob) {
  const type = file.type.toLowerCase();
  const name = "name" in file ? file.name.toLowerCase() : "";
  return (
    type.startsWith("image/") ||
    name.endsWith(".heic") ||
    name.endsWith(".heif") ||
    name.endsWith(".jpg") ||
    name.endsWith(".jpeg") ||
    name.endsWith(".png") ||
    name.endsWith(".webp")
  );
}

function firstImageFile(files: FileList) {
  return Array.from(files).find(isSupportedImageLike) ?? null;
}

function filenameFromUrl(url: string, fallbackType: string) {
  try {
    const pathname = new URL(url).pathname;
    const name = pathname.split("/").filter(Boolean).at(-1);
    if (name) return name;
  } catch {
    // Fall through to a MIME-based fallback.
  }
  return fallbackType.includes("png") ? "dropped-image.png" : "dropped-image.jpg";
}

export async function getDroppedImageFile(dataTransfer: DataTransfer): Promise<File> {
  const droppedFile = firstImageFile(dataTransfer.files);
  if (droppedFile) {
    return droppedFile;
  }

  for (const item of Array.from(dataTransfer.items)) {
    if (item.kind !== "file") continue;
    const file = item.getAsFile();
    if (file && isSupportedImageLike(file)) {
      return file;
    }
  }

  const droppedUrl =
    dataTransfer
      .getData("text/uri-list")
      .split("\n")
      .find((line) => line && !line.startsWith("#")) ||
    dataTransfer.getData("text/plain");

  if (droppedUrl && /^https?:\/\//i.test(droppedUrl)) {
    try {
      const response = await fetch(droppedUrl);
      const blob = await response.blob();
      if (isSupportedImageLike(blob)) {
        return new File([blob], filenameFromUrl(droppedUrl, blob.type), {
          type: blob.type,
        });
      }
    } catch {
      throw new Error("That dropped image URL could not be read by the browser.");
    }
  }

  throw new Error("Drop a PNG, JPG, HEIC, or HEIF image.");
}
