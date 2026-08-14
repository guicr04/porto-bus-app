# Porto Bus — iOS App Design

A SwiftUI iPhone app on top of [porto-bus-api](../porto-bus-api). Self-contained
repo: the only thing shared between the two is the HTTP contract.

This document is the agreed design, written **before** any code. It records
decisions and the reasoning behind them, so a choice that looks arbitrary later
can be re-litigated on its merits instead of guessed at.

---

## 1. Scope

**v1 ships three screens** — Board, Departures, Stops — plus a Home Screen
widget.

The **navigation shell is built for five tabs from day one** (see §5), because
retrofitting a tab bar is disruptive and the two extra destinations are already
designed. Tabs for Lines and Map are present but lead to a "coming soon" state
in v1.

Deliberately later, with reasons, in §10: the Line screen, the live vehicle map,
the timetable grid, and the journey planner.

Platform: **iOS 17+**, iPhone, SwiftUI. Swift 6, strict concurrency.
**No third-party dependencies** — `URLSession` + `async/await` + `Codable`
covers every endpoint. Nothing here needs Alamofire. MapKit is first-party and
arrives with the Map tab.

---

## 2. Repo layout

```
porto-bus-app/
  DESIGN.md
  README.md
  PortoBusApp.xcodeproj
  PortoBusKit/                  # local Swift package — the Model layer
    Package.swift
    Sources/PortoBusKit/
      Models/                   # port of porto-bus-api/types/domain.d.ts
      PortoBusClient.swift      # one method per endpoint
      Endpoints.swift           # URL construction + query encoding
      APIError.swift
    Tests/PortoBusKitTests/
      Fixtures/                 # recorded JSON from the live API
  PortoBusApp/                  # app target — View + ViewModel layers
    PortoBusApp.swift
    Navigation/                 # tab bar, routing
    Features/
      Board/                    # BoardView + BoardViewModel
      Departures/
      Stops/
      Lines/                    # v1: placeholder
      Map/                      # v1: placeholder
      Settings/
    Design/                     # LineBadge, colors, typography
    Location/
  PortoBusWidget/
```

**Why the package/app split.** It is not ceremony. It buys two concrete things:
the widget target reuses the client without duplicating it, and the entire Model
layer is testable with no simulator and no UI. The boundary is enforced by
`PortoBusKit` importing neither UIKit nor SwiftUI.

---

## 3. The contract

`PortoBusKit/Models` is a near-mechanical port of `types/domain.d.ts`. Same
names, same nullability. When the API's contract changes, the diff should be
obvious on both sides.

Rules:

- `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`. The API is
  consistently snake_case, so per-field `CodingKeys` would be noise.
- **One exception:** `ShapePoint.lng` needs an explicit `CodingKey` — snake_case
  conversion doesn't rename it, and everything else in the API says `lon`.
  Bites as soon as the Map tab lands.
- Nullable in the `.d.ts` stays `Optional` in Swift. Do **not** default a
  missing value to zero: a missing `eta_minutes` must render as "—", not as a
  confident `0 min` that sends someone running for a bus that isn't coming.
- `source: 'realtime' | 'scheduled'` becomes a `String`-backed enum with an
  unknown case, so an upstream addition degrades instead of failing to decode.
  Same for `ArrivalStatus`, which the `.d.ts` already types as an open union.

---

## 4. Architecture — MVVM

Three layers, strictly separated.

### Model — `PortoBusKit`

Pure data and networking. `Codable` structs mirroring the domain contract, plus
`PortoBusClient`. No UI, no state, no knowledge that an app exists. Value types
throughout.

### ViewModel — one per screen, `@Observable`

```swift
@Observable
final class BoardViewModel {
    private(set) var state: LoadState<[BoardRow]> = .idle
    private let client: PortoBusClient
    ...
    func load() async { ... }
}
```

Rules that keep this honest:

- **ViewModels own all state and all async work.** A View never calls the
  client, never touches `URLSession`, never owns a `Task` that fetches.
- **ViewModels import no SwiftUI.** If a ViewModel needs `Color`, it's doing
  view work — it should expose the hex string and let the View map it. This is
  the test for whether the separation is real.
- **ViewModels expose formatted, display-ready values.** `"Arriving"` vs
  `"6 min"` is decided in the ViewModel, not with a ternary inside a `Text`.
- `@MainActor` on the ViewModel; the client is `nonisolated` and does its work
  off-main.
- **The client is a protocol.** A live implementation and a mock both conform,
  injected through the SwiftUI environment, so previews and tests run with no
  server and no network.

### View — SwiftUI, as dumb as it can be

Renders the ViewModel's state and forwards user intent back to it. No business
logic, no formatting decisions, no networking.

### `LoadState`

```swift
enum LoadState<T> { case idle, loading, loaded(T), failed(Error) }
```

One enum, used by every screen, so loading / empty / error states are handled by
construction rather than remembered. §7 explains why the empty case in
particular is load-bearing here.

---

## 5. Navigation — the floating tab bar

Adopted from the Lisbon Metro app: a **floating pill-shaped bar** over the
content rather than a standard `TabView` chrome. It reads as part of the app
instead of part of the OS, and it lets the map run full-bleed underneath.

Five destinations:

| Tab          | Icon           | v1        |
|--------------|----------------|-----------|
| **Board**    | compass        | ✅ ships  |
| **Lines**    | bus            | placeholder |
| **Map**      | map (centre, emphasised) | placeholder |
| **Stops**    | pin            | ✅ ships  |
| **Info**     | info           | ✅ (settings + about) |

Details worth copying from the reference:

- The **centre item is visually dominant** — larger, filled, dark. In the Lisbon
  app that's the map; for us the map is the eventual centrepiece too, so it
  keeps the slot.
- The **selected tab expands to show its label** while the others stay
  icon-only. Costs nothing, and it makes a five-icon bar legible.
- Content **scrolls under** the bar with bottom safe-area padding, never behind
  it permanently.

**Cost to be aware of:** a custom floating bar means hand-rolling what `TabView`
gives free — selection state, per-tab navigation stacks, and correct safe-area
insets. Budget real time for it; it is not just a styled `TabView`.

Detail screens (Departures, a stop, a line) push onto the **current tab's**
`NavigationStack` and keep the bar visible, so context is never lost.

---

## 6. Screens

### 6.1 Board — the root screen

Answers "what can I catch from here". `GET /board?lat=&lon=`.

**The primary number on each row is `eta_minutes` — when the bus reaches the
stop.** This was debated and settled deliberately.

The alternative was `leave_in_minutes` ("get up in 4 min"), which is more
directly actionable. It was rejected because it is *derived from a guess*: the
API's walking model is straight-line distance × 1.35 ÷ 75 m/min, explicitly
pessimistic, and it cannot know that you walk fast, that the lift is slow, or
that you're already halfway to the stop. Presenting a computed estimate as the
headline gives it authority it hasn't earned.

The bus's arrival is a *fact from the feed*. Show the fact; let the rider apply
their own knowledge of how long they take to get there.

```
 305   Cordoaria                      6 min
       CARMO · 4 min walk
```

- **Primary (trailing, large):** `eta_minutes`. `0` renders as "Arriving".
- **Secondary (below):** `stop_name` and `walk_minutes` — context for the
  rider's judgement, not a directive.
- **Leading:** line badge, filled with the row's `color` / `text_color`.

The **reachability filter still runs**: rows with `catchable: false` are hidden
by default. Buses you provably cannot reach are noise, and that filter is what
makes this a board rather than a list of nearby buses. `leave_in_minutes` is
still doing its job — it just isn't the headline. A toggle reveals unreachable
rows (`include_unreachable=true`).

**Sorting:** by line, the API's default, so a line stays in the same place
between refreshes and it reads like a station board instead of a list that
reshuffles under your thumb. `?sort=eta` offered as a toggle.

**Live vs projected:** rows carry `realtime: true | false`. Tracked rows get a
subtle live indicator. Per the API README every stop observed so far reports
`realtime`, so in practice everything shows as live — the styling exists so the
day it flips, it reads as information rather than a bug.

### 6.2 Departures — one line at one stop

Pushed from a Board row or from a stop. `GET /stops/{code}/departures?line=`.

The endpoint's whole value is that every entry is tagged `source`, so the two
must be **unmissably different**:

- `realtime` → solid pill in the line colour, showing `eta_minutes`, plus
  `status` / `delay_minutes` when late.
- `scheduled` → faded outline, showing the `HH:MM` clock time.

If those ever look similar, the screen has failed at its one job.

The API already handles the hard part (deduping a late bus against its own
timetable slot by subtracting `delay_minutes`), so the app renders the list as
given and does no merging of its own.

### 6.3 Stops — search

`GET /stops?q=` → tap a stop → its realtime board → tap a line → **the same
Departures screen**. One destination, two routes in. Search debounced ~300 ms;
results are GTFS-static and cache freely.

---

## 7. Behaviour

### Refresh

On appear, pull-to-refresh, and **auto every 20s while foregrounded only**.

The API caches live arrivals for 15s (`REALTIME_TTL_MS`), so polling faster
returns identical bytes and burns battery. Section 7 of the API README is
explicit about staying gentle on stcp.pt — an always-on client across a dozen
stops is exactly the traffic pattern that gets an undocumented endpoint closed.
Timers stop on background.

### Location

CoreLocation, `whenInUse` → `/board?lat=&lon=`. If denied or unavailable, fall
back to home coordinates saved in Settings so the app still works rather than
showing a permissions dead end. Needs `NSLocationWhenInUseUsageDescription`.

### Empty is not the same as broken

The board response carries `stops_polled[].ok` and `stops_truncated`. The UI
must distinguish:

- **No departures, everything polled fine** → "Nothing running from here right
  now."
- **Some stops failed** → the rows we have, plus a note that some stops were
  unavailable.
- **`stops_truncated`** → a note that not every nearby stop was checked.

Rendering a blank "no buses" when the app actually failed to look is the worst
outcome on this screen, and it is the easy mistake to make.

### Colours

Line colours come from the board rows, which come from the realtime feed — the
true line colour. The routes endpoints return a coarse family colour (`#187EC2`
for essentially every city line) and **must not** be used for badges. Contrast
is checked against `text_color`; a neutral fallback covers a null colour.

---

## 8. Widget

Small and medium, showing the next few catchable departures with `eta_minutes`.

**Known limitation, accepted:** WidgetKit refreshes on its own budget (roughly
every 15 minutes), so the widget cannot be genuinely live. It is a "before I
leave the house" glance, not a departure board. Combined with the LAN constraint
below, it will be blank away from home until the API is hosted.

---

## 9. Talking to the API

v1 is **LAN only**. Two setup steps, easy to forget and expensive to debug:

1. The API binds `127.0.0.1:8000`. It must listen on `0.0.0.0` for the phone to
   reach it.
2. iOS blocks cleartext HTTP. Add an ATS exception for the Mac's LAN IP in
   Info.plist (`NSAppTransportSecurity` → `NSExceptionDomains`).

**The base URL is a stored setting from day one**, even though it points at a
LAN address for now. Ten lines of code that turn "deploy the API" into a
settings change rather than a refactor.

---

## 10. Planned features (post-v1)

Inspired by the Lisbon Metro app. Recorded now because they shape the navigation
shell, even though they don't ship in v1.

### 10.1 Line screen — ordered stops with per-stop ETAs

*(The reference app's station list: a line's stops down the page, tap one to
expand and see the next arrivals.)*

**Fully supported by the existing API.** No backend work needed.

- `GET /lines` → the line picker.
- `GET /lines/{line}/stops?direction_id=` → the ordered stop list, with a
  direction segmented control.
- On expanding a stop → `GET /stops/{code}/departures?line=` for that stop's
  next arrivals, rendered with the same live/scheduled treatment as §6.2.

**Load lazily, on expand only.** A line has 30–50 stops; fetching every stop's
departures up front would be dozens of upstream calls to render a screen where
the rider cares about one stop. Expanded state collapses on scroll-away.

This is the strongest post-v1 candidate: high value, no new endpoints, and it
reuses the Departures rendering already built for v1.

### 10.2 Live vehicle map — the hard one

*(The reference app's moving trains: buses drawn along the route, tap one for
its details.)*

**Not directly possible today, and the blocker isn't the number of buses — it's
that the API has no vehicle positions at all.** GTFS is schedule data, and
STCP's live API is stop-centric: it answers "what's arriving at stop X", never
"where is vehicle Y".

It is *inferable*, and one field makes it possible: **`Arrival.trip_id`**. Poll
every stop on a line and the same `trip_id` appears at consecutive stops with
increasing ETAs — which brackets the bus between two known points. Interpolate
along `GET /lines/{line}/shape` and you have a plausible position.

**This belongs in the API, not the app.** Reasons:

- It costs one upstream call **per stop** — 30–50 per line, per refresh. Doing
  that from every client instance is precisely what the API README's "be a good
  citizen" section rules out. Server-side it happens once and is cached for
  everyone.
- The interpolation is real logic that wants unit tests, and the API repo
  already has the shape data, the stop ordering and the test harness.

Sketch: a `GET /lines/{line}/vehicles?direction_id=` endpoint returning inferred
positions with an **explicit confidence/staleness field**, so the app can render
an uncertain bus differently from a fresh one. Honesty about precision matters
here — a smoothly gliding dot implies GPS we do not have.

What the app would then build:
- Full-bleed MapKit map, route polyline from `/lines/{line}/shape` in the line
  colour, stop markers along it.
- Vehicle annotations from `/lines/{line}/vehicles`.
- Tap a vehicle → a bottom card: line badge, destination, next stop, ETA —
  mirroring the reference app's "Comboio 22C" card.

Worth doing. Worth doing *properly*, in the right repo, and not before the Line
screen — which delivers much of the same value for a fraction of the work.

### 10.3 Also later

- Timetable grid (`/lines/{line}/schedule`) — the trips × timepoints matrix is a
  genuinely tricky UI.
- `/journey?to=` once the API grows it; that's the Siri case.
- Live Activities for a bus you're waiting on — needs a hosted API and push.

---

## 11. Open questions

- **Hosting the API** (Fly.io, Railway, a VPS). Until then the app is home-only
  and the widget is decorative. This is the single biggest unlock.
- Whether the Map tab keeps the centre slot in v1 while it's a placeholder, or
  Board takes it temporarily.
