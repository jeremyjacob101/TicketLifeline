# TicketLifeline

A lightweight QR and barcode vault built with React, Vite, TypeScript, and Convex.

The app does not store uploaded screenshots. A screenshot is decoded in the browser with
`BarcodeDetector`, then only the small encoded payload and pass metadata are saved to
Convex. The QR code or barcode is regenerated on demand from that stored text.

## Local setup

```bash
npm install
npm run convex:dev
npm run dev
```

`npm run convex:dev` links the repo to a Convex project and writes the local Convex URL
to `.env.local`.
