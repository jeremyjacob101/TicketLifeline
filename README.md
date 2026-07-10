# TicketLifeline

TicketLifeline keeps its two apps side by side while sharing a single Convex backend at the
repository root:

- [`convex`](./convex) — shared schema, authentication, queries, and mutations.
- [`Codebase - TicketLifeline Web`](./Codebase%20-%20TicketLifeline%20Web) — React, Vite, and TypeScript client.
- [`Codebase - TicketLifeline iOS`](./Codebase%20-%20TicketLifeline%20iOS) — native SwiftUI client.

Run the shared backend from the repository root:

```bash
npm install
npm run convex:dev
```

The web and iOS apps use the same Convex user accounts and pass records. Each client has its
own run instructions in its folder.
