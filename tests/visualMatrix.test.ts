import assert from "node:assert/strict";
import test from "node:test";
import { assertVisualMatrix } from "../convex/visualMatrix.ts";

test("matrix validation accepts verified square and rectangular matrices", () => {
  assert.doesNotThrow(() => assertVisualMatrix("0".repeat(21 * 21), 21, 21, 21));
  assert.doesNotThrow(() => assertVisualMatrix("0".repeat(23 * 23), 23, 23, 23));
  assert.doesNotThrow(() => assertVisualMatrix("0".repeat(47 * 47), 47, 47, 47));
  assert.doesNotThrow(() => assertVisualMatrix("0".repeat(23 * 23), 23, undefined, undefined));
  assert.doesNotThrow(() => assertVisualMatrix("010101", undefined, 6, 1));
});

test("matrix validation rejects incomplete or inconsistent data", () => {
  assert.throws(
    () => assertVisualMatrix("0", undefined, undefined, undefined),
    /incomplete/,
  );
  assert.throws(
    () => assertVisualMatrix("0".repeat(24), 5, 5, 5),
    /do not match/,
  );
  assert.throws(
    () => assertVisualMatrix("0".repeat(25), 5, 5, 4),
    /Legacy matrix size/,
  );
  assert.throws(
    () => assertVisualMatrix("000x", undefined, 2, 2),
    /data is invalid/,
  );
});

test("matrix validation enforces the 40,000-cell limit", () => {
  assert.doesNotThrow(() =>
    assertVisualMatrix("0".repeat(40_000), undefined, 200, 200),
  );
  assert.throws(
    () => assertVisualMatrix("0".repeat(40_200), undefined, 201, 200),
    /dimensions are invalid/,
  );
});
