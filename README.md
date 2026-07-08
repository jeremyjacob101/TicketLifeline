# TicketLifeline

A lightweight QR and barcode vault built with React, Vite, TypeScript, and Convex.

The app does not store full uploaded screenshots. Images are decoded in the browser with
`BarcodeDetector`, then the encoded payload, pass metadata, and, for QR codes, a compact
digital module matrix are saved to Convex. When the photographed QR pattern can be matched,
the saved matrix is rendered as a crisp digital QR that resembles the scanned original;
otherwise the QR is regenerated from the payload as a fallback.

## Local setup

```bash
npm install
npm run convex:dev
npm run dev
```

`npm run convex:dev` links the repo to a Convex project and writes the local Convex URL
to `.env.local`.
