# TicketLifeline iOS

The native SwiftUI app currently supports a device-local account, QR-only camera scanning,
and a local vault of regenerated digital QR codes.

## Run

Open `TicketLifeline.xcodeproj` in Xcode, select an iPhone, choose your signing team, and run
the `TicketLifeline` scheme. A physical iPhone is required to scan with the camera.

If the project needs to be regenerated after editing `project.yml`, run this folder's command:

```bash
xcodegen generate
```
