/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as auth from "../auth.js";
import type * as emailVerification from "../emailVerification.js";
import type * as http from "../http.js";
import type * as passes from "../passes.js";
import type * as sessionMaintenance from "../sessionMaintenance.js";
import type * as sessionPolicy from "../sessionPolicy.js";
import type * as users from "../users.js";
import type * as visualMatrix from "../visualMatrix.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  auth: typeof auth;
  emailVerification: typeof emailVerification;
  http: typeof http;
  passes: typeof passes;
  sessionMaintenance: typeof sessionMaintenance;
  sessionPolicy: typeof sessionPolicy;
  users: typeof users;
  visualMatrix: typeof visualMatrix;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
