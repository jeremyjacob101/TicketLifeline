import { getAuthUserId } from "@convex-dev/auth/server";
import { v } from "convex/values";
import { mutation, query } from "./_generated/server";

const maxPayloadLength = 20_000;
const maxLaunchUrlLength = 2_000;
const maxVisualMatrixLength = 40_000;

async function requireUserId(ctx: Parameters<typeof getAuthUserId>[0]) {
  const userId = await getAuthUserId(ctx);
  if (!userId) {
    throw new Error("Not authenticated");
  }
  return userId;
}

function assertPayloadSize(value: string) {
  if (value.length > maxPayloadLength) {
    throw new Error("This code payload is too large to store lightweightly.");
  }
}

function normalizeLaunchUrl(value: string | undefined) {
  const trimmed = value?.trim();
  if (!trimmed) {
    return undefined;
  }
  if (trimmed.length > maxLaunchUrlLength) {
    throw new Error("This scan URL is too long.");
  }

  try {
    const url = new URL(trimmed);
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      throw new Error("Scan URLs must start with http:// or https://.");
    }
    return url.toString();
  } catch {
    throw new Error("Scan URL must be a valid http:// or https:// URL.");
  }
}

function assertVisualMatrix(value: string | undefined, size: number | undefined) {
  if (!value && size === undefined) {
    return;
  }
  if (!value || size === undefined) {
    throw new Error("QR matrix data is incomplete.");
  }
  if (!Number.isInteger(size) || size < 21 || size > 177 || (size - 17) % 4 !== 0) {
    throw new Error("QR matrix size is invalid.");
  }
  if (value.length !== size * size || value.length > maxVisualMatrixLength) {
    throw new Error("This QR matrix is too large to store lightweightly.");
  }
  if (!/^[01]+$/.test(value)) {
    throw new Error("QR matrix data is invalid.");
  }
}

export const list = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    return await ctx.db
      .query("passes")
      .withIndex("by_owner_updated", (q) => q.eq("ownerId", userId))
      .order("desc")
      .collect();
  },
});

export const create = mutation({
  args: {
    title: v.string(),
    issuer: v.optional(v.string()),
    codeType: v.union(v.literal("qr"), v.literal("barcode")),
    format: v.optional(v.string()),
    encodedValue: v.string(),
    launchUrl: v.optional(v.string()),
    visualMatrix: v.optional(v.string()),
    visualSize: v.optional(v.number()),
    eventDate: v.optional(v.string()),
    notes: v.optional(v.string()),
    color: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const now = Date.now();
    assertPayloadSize(args.encodedValue);
    assertVisualMatrix(args.visualMatrix, args.visualSize);
    const launchUrl = normalizeLaunchUrl(args.launchUrl);

    return await ctx.db.insert("passes", {
      ownerId: userId,
      title: args.title.trim() || "Untitled pass",
      issuer: args.issuer?.trim() || undefined,
      codeType: args.codeType,
      format: args.format?.trim() || undefined,
      encodedValue: args.encodedValue,
      launchUrl,
      visualMatrix: args.visualMatrix,
      visualSize: args.visualSize,
      eventDate: args.eventDate || undefined,
      notes: args.notes?.trim() || undefined,
      color: args.color,
      createdAt: now,
      updatedAt: now,
    });
  },
});

export const update = mutation({
  args: {
    id: v.id("passes"),
    title: v.string(),
    issuer: v.optional(v.string()),
    codeType: v.union(v.literal("qr"), v.literal("barcode")),
    format: v.optional(v.string()),
    encodedValue: v.string(),
    launchUrl: v.optional(v.string()),
    visualMatrix: v.optional(v.string()),
    visualSize: v.optional(v.number()),
    eventDate: v.optional(v.string()),
    notes: v.optional(v.string()),
    color: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const existing = await ctx.db.get(args.id);
    if (!existing || existing.ownerId !== userId) {
      throw new Error("Pass not found");
    }
    assertPayloadSize(args.encodedValue);
    assertVisualMatrix(args.visualMatrix, args.visualSize);
    const launchUrl = normalizeLaunchUrl(args.launchUrl);

    await ctx.db.patch(args.id, {
      title: args.title.trim() || "Untitled pass",
      issuer: args.issuer?.trim() || undefined,
      codeType: args.codeType,
      format: args.format?.trim() || undefined,
      encodedValue: args.encodedValue,
      launchUrl,
      visualMatrix: args.visualMatrix,
      visualSize: args.visualSize,
      eventDate: args.eventDate || undefined,
      notes: args.notes?.trim() || undefined,
      color: args.color,
      updatedAt: Date.now(),
    });
  },
});

export const remove = mutation({
  args: { id: v.id("passes") },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const existing = await ctx.db.get(args.id);
    if (!existing || existing.ownerId !== userId) {
      throw new Error("Pass not found");
    }
    await ctx.db.delete(args.id);
  },
});

export const markOpened = mutation({
  args: { id: v.id("passes") },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const existing = await ctx.db.get(args.id);
    if (!existing || existing.ownerId !== userId) {
      return;
    }
    await ctx.db.patch(args.id, { lastOpenedAt: Date.now() });
  },
});
