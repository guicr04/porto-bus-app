# Porto Bus — iOS App

A SwiftUI iPhone app for Porto's STCP buses, built on top of the
[porto-bus-api](../porto-bus-api). It answers one question first: **what can I
catch on foot from where I am?**

The full design and the reasoning behind every decision live in
[DESIGN.md](DESIGN.md). This README is how to build and run it.

## What's here

```
porto-bus-app/
  DESIGN.md              # the agreed design + rationale (read this first)
  project.yml            # XcodeGen project spec — the project file is generated
  PortoBusKit/           # local Swift package: models + API client (the Model layer)
  PortoBusApp/           # the SwiftUI app (View + ViewModel layers)
```

- **PortoBusKit** — a faithful Swift port of the API's `types/domain.d.ts`, plus
  `PortoBusClient` (one method per endpoint) over `URLSession`. No UI. Builds and
  tests on its own from the command line.
- **PortoBusApp** — MVVM. `@Observable` ViewModels own all state and networking;
  Views are dumb; the client is injected so previews and tests need no server.

Architecture, the MVVM rules, and the screen-by-screen intent are all in
[DESIGN.md](DESIGN.md) (§4–§7).

## Requirements

- Xcode 26+ with an installed iOS Simulator runtime
- [XcodeGen](https://github.com/yonwoo9/XcodeGen) (`brew install xcodegen`) —
  the `.xcodeproj` is generated, not checked in

## Build & run

```bash
# 1. Generate the Xcode project from project.yml
xcodegen generate

# 2. Open and run (⌘R), or from the command line:
xcodebuild -project PortoBusApp.xcodeproj -scheme PortoBusApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Re-run `xcodegen generate` after adding or removing source files.

## Test the package

`PortoBusKit` is verified independently of the app and the simulator:

```bash
cd PortoBusKit && swift test
```

Decoding tests pin the contract port against representative JSON fixtures;
endpoint tests pin the query encoding (notably `service_id` → `%20`, never `+`).

## Pointing the app at the API

The API listens on `127.0.0.1:8000` by default. The app's base URL is set in
**Settings** (gear icon on the Board, or the Info tab) and persists.

- **iOS Simulator** — `http://127.0.0.1:8000` reaches the Mac directly.
- **A real iPhone** — use the Mac's LAN address, e.g. `http://192.168.1.20:8000`,
  and start the API bound to all interfaces so the phone can reach it. The API
  currently binds `127.0.0.1`; it needs to listen on `0.0.0.0` for a device to
  connect (see DESIGN.md §9).

Cleartext HTTP to the local network is allowed via `NSAllowsLocalNetworking` in
the app's Info.plist — a LAN-only concession to be removed once the API is
hosted over HTTPS.

## Status

**Board, Lines, and Favorites are built and running against the live API.**
Map is a placeholder tab (DESIGN.md §11.1) — it's next, and needs a new
endpoint in `porto-bus-api` before there's anything to render. The Home Screen
widget hasn't been started.

Two screens from the original plan were built and then removed once real usage
showed they were redundant — a combined single-line Departures view, and a
Stops-by-name search tab (now Favorites instead). See DESIGN.md §6.2 and §6.5
for why.
