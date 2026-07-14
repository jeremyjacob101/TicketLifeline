<p align="center">
  <img src="docs/images/logo.png" alt="TicketLifeline icon" width="140">
</p>

<h1 align="center">TicketLifeline</h1>

<p align="center">
  A calm, synchronized safety net for the QR codes and barcodes you cannot afford to lose.
</p>

<p align="center">
  <img alt="App version 1.0" src="https://img.shields.io/badge/App-1.0-0F766E?style=for-the-badge">
  <img alt="iOS 17 or newer" src="https://img.shields.io/badge/iOS-17%2B-111827?style=for-the-badge&logo=apple&logoColor=white">
  <img alt="Swift 5" src="https://img.shields.io/badge/Swift-5-F05138?style=for-the-badge&logo=swift&logoColor=white">
  <img alt="React 19.2.6" src="https://img.shields.io/badge/React-19.2.6-0F172A?style=for-the-badge&logo=react&logoColor=61DAFB">
  <img alt="TypeScript 6.0.2" src="https://img.shields.io/badge/TypeScript-6.0.2-1D4ED8?style=for-the-badge&logo=typescript&logoColor=white">
  <img alt="Vite 8.0.12" src="https://img.shields.io/badge/Vite-8.0.12-111827?style=for-the-badge&logo=vite&logoColor=FBBF24">
  <img alt="Convex 1.39.1" src="https://img.shields.io/badge/Convex-1.39.1-EE342F?style=for-the-badge&logo=convex&logoColor=white">
</p>

> Tickets disappear into photo libraries, confirmation emails, and expired wallet links.
> TicketLifeline keeps the small piece that matters—the scan-ready code—available wherever you need it.

<p align="center">
  <a href="https://ticketlifeline.app/"><strong>Take me there →</strong></a>
</p>

## Overview

TicketLifeline is a shared QR code and barcode vault with two native-feeling clients: a React web app and a SwiftUI iPhone app. Both use one Convex backend, one account, and one synchronized collection of saved passes.

Instead of keeping full ticket screenshots, TicketLifeline extracts and stores the encoded value and a compact digital matrix. The original camera frame or selected image stays on the device; the saved code remains clean, searchable, and ready to scan.

## Why This Exists

A ticket should still work when the original email is buried, the screenshot is cropped, or the source app refuses to load.

TicketLifeline is designed to make that recovery path simple:

- scan a QR code with the iPhone camera
- decode screenshots and photos locally on iOS or in the browser
- save directly from the iOS Share Sheet after taking a screenshot
- jump straight to photo upload or camera scanning from Home Screen quick actions
- save QR codes and common barcodes with useful labels and notes
- regenerate a sharp, scan-ready code instead of preserving a blurry screenshot
- synchronize one private vault across web and iOS
- permanently delete the complete account and its associated data from either client

## Highlights

- Shared username-and-password authentication across web and iOS.
- Per-user Convex data isolation for every pass query and mutation.
- Local image decoding; original photos and camera frames are never uploaded.
- Native iOS photo import through the limited system picker, with no full Photo Library permission.
- One-tap Share Extension imports and Home Screen Upload/Scan quick actions.
- QR, Aztec, Data Matrix, PDF417, Code 39/93/128, EAN, UPC, ITF, and Codabar decoding.
- Compact QR visual-matrix preservation for faithful reconstruction.
- Search across titles, issuers, formats, payloads, links, and notes.
- Native iOS camera scanning with an explicit camera permission description.
- QR tree and barcode city visualizations powered by SwiftUI and Metal.
- Keychain-backed iOS session storage.
- Complete account deletion covering passes, credentials, sessions, refresh tokens, and authentication records.
- App Store-ready 1024×1024 icon plus web favicon, Apple Touch, and PWA icon sets.

## Platform Snapshot

TicketLifeline has three connected layers:

1. **Web** — React 19 + TypeScript + Vite.
2. **iOS** — SwiftUI for iOS 17 and newer, with local Vision decoding, AVFoundation scanning, a Share Extension, Home Screen quick actions, and Metal visualizations.
3. **Backend** — Convex queries, mutations, authentication, and synchronized storage shared by both clients.

```text
Web app ───────┐
               ├── Convex Auth ── Shared user account
iOS app ───────┘       │
                       └── Shared passes and account lifecycle
```

## Privacy by Design

- Camera frames and selected images are decoded locally.
- Share Sheet images are discarded immediately after local decoding and are never uploaded.
- Only the code content and metadata a user chooses to save are sent to Convex.
- No advertising, tracking, or third-party analytics SDKs.
- Passwords are stored as secure hashes rather than plaintext.
- iOS session credentials are stored in Apple’s Keychain.
- Account deletion is available inside both apps and removes associated cloud data.

Read the full [TicketLifeline Privacy Policy](PRIVACY.md).

## Run Locally

### Shared Convex Backend

From the repository root:

```bash
npm install
npm run convex:dev
```

This creates or connects the Convex development deployment and generates the shared API types.

### Web App

```bash
cd "Codebase - TicketLifeline Web"
npm install
npm run dev
```

The Vite app reads `VITE_CONVEX_URL` from its environment configuration.

Build the production bundle:

```bash
npm run build
```

### iOS App

Requirements:

- Xcode 26 or newer
- iOS 17 deployment target or newer
- Apple Metal toolchain

Generate the Xcode project and open it:

```bash
cd "Codebase - TicketLifeline iOS"
xcodegen generate
open TicketLifeline.xcodeproj
```

The app and embedded Share Extension read the same `CONVEX_URL` build setting from `project.yml`, ensuring that both save to the same Convex deployment.

## Shared Account Deletion

Both clients call the same authenticated Convex mutation:

```text
users:deleteAccount
```

The mutation atomically removes:

- saved QR codes and barcodes
- verification codes and password-account records
- sign-in rate-limit records tied to the account
- active sessions, refresh tokens, and session verifiers
- the final user record

Local credentials are cleared only after the server confirms deletion.

## Project Tour

```text
.
├── convex/                              Shared schema, auth, queries, and mutations
├── Codebase - TicketLifeline Web/       React + TypeScript + Vite client
│   ├── public/                          Favicons, PWA icons, and manifest
│   └── src/                             Auth, vault, scanner, and pass UI
├── Codebase - TicketLifeline iOS/       SwiftUI iPhone app
│   ├── TicketLifeline/                  App source and asset catalog
│   ├── TicketLifelineShareExtension/    Native Share Sheet import UI
│   ├── TicketLifelineTests/             Local Vision decoder fixtures and tests
│   ├── TicketLifeline.xcodeproj/        Generated Xcode project
│   └── project.yml                      XcodeGen source of truth
├── docs/images/                         README artwork
├── .github/workflows/                   Repository automation
├── LICENSE.md                            MIT license
├── PRIVACY.md                           Public privacy policy
└── README.md
```

### Key Files

- `convex/schema.ts` defines user, auth, and pass storage.
- `convex/passes.ts` enforces per-user pass access and payload validation.
- `convex/users.ts` implements complete shared account deletion.
- `Codebase - TicketLifeline Web/src/VaultApp.tsx` contains the web vault and account controls.
- `Codebase - TicketLifeline iOS/TicketLifeline/Models.swift` owns iOS authentication and synchronized state.
- `Codebase - TicketLifeline iOS/TicketLifeline/VaultView.swift` contains the native vault and account settings.
- `Codebase - TicketLifeline iOS/TicketLifeline/QRScannerView.swift` handles camera authorization and scanning.
- `Codebase - TicketLifeline iOS/TicketLifeline/CodeImport.swift` owns local Vision decoding and format normalization.
- `Codebase - TicketLifeline iOS/TicketLifelineShareExtension/ShareViewController.swift` imports screenshots directly from the Share Sheet.

## App Store Preparation

- App version: `1.0`
- Build: `1`
- Bundle identifier: `com.ticketlifeline.app`
- Minimum iOS version: `17.0`
- Device family: iPhone
- Camera usage description: included
- Opaque App Store icon: included
- In-app account deletion: included
- In-app privacy-policy access: included
- Home Screen Upload/Scan quick actions: included
- Embedded image Share Extension: included
- Keychain Sharing between app and extension: configured

Before release, upload a signed archive to TestFlight, complete App Privacy responses, provide a reviewer demo account, add screenshots and support metadata, and publish the privacy-policy URL in App Store Connect.

## Current Limitations

- Username/password recovery is not yet available.
- Share Sheet imports intentionally save one selected code per shared image with an automatic title; richer pass metadata editing lives on the web.
- A live Convex connection is required to read or change the synchronized vault.

## Links

- Web app: https://ticketlifeline.app/
- Repository: https://github.com/jeremyjacob101/TicketLifeline
- Privacy policy: https://github.com/jeremyjacob101/TicketLifeline/blob/main/PRIVACY.md
- License: [MIT](LICENSE.md)

## License

TicketLifeline is available under the [MIT License](LICENSE.md). The copyright
year is updated automatically each January while preserving 2026 as the
project's original year.

## Notes for Contributors

- Keep the Convex contract compatible with both clients.
- Treat account deletion as a cross-platform data-lifecycle feature; test it from web and iOS after any auth-schema change.
- Never upload original scan images unless the product and privacy policy are deliberately changed together.
- Regenerate the Xcode project after editing `project.yml` or adding iOS source files.
- Validate UI changes on desktop web, mobile web, and a physical iPhone when camera behavior is involved.
