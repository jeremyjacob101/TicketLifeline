import { defineSchema, defineTable } from "convex/server";
import { authTables } from "@convex-dev/auth/server";
import { v } from "convex/values";

const { users: _authUsers, ...restAuthTables } = authTables;
void _authUsers;

export default defineSchema({
  ...restAuthTables,
  users: defineTable({
    name: v.optional(v.string()),
    image: v.optional(v.string()),
    email: v.optional(v.string()),
    username: v.optional(v.string()),
    emailVerificationTime: v.optional(v.number()),
    phone: v.optional(v.string()),
    phoneVerificationTime: v.optional(v.number()),
    isAnonymous: v.optional(v.boolean()),
  })
    .index("email", ["email"])
    .index("username", ["username"])
    .index("phone", ["phone"]),
  passes: defineTable({
    ownerId: v.id("users"),
    title: v.string(),
    issuer: v.optional(v.string()),
    codeType: v.union(v.literal("qr"), v.literal("barcode")),
    format: v.optional(v.string()),
    encodedValue: v.string(),
    eventDate: v.optional(v.string()),
    notes: v.optional(v.string()),
    color: v.optional(v.string()),
    createdAt: v.number(),
    updatedAt: v.number(),
    lastOpenedAt: v.optional(v.number()),
  })
    .index("by_owner_updated", ["ownerId", "updatedAt"])
    .index("by_owner_created", ["ownerId", "createdAt"]),
});
