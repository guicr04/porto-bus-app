# Porto Bus — iOS App Design

A SwiftUI iPhone app on top of [porto-bus-api](../porto-bus-api). Self-contained
repo: the only thing shared between the two is the HTTP contract.

This document is the agreed design, kept in sync with what's actually built. It
records decisions and the reasoning behind them — including ones that were
later reversed — so a choice that looks arbitrary can be re-litigated on its
merits instead of guessed at. Superseded decisions are kept, not deleted, with
a note on why they changed: the reasoning is often as useful as the outcome.

---

## 1. Scope

**Shipped: Board, Lines, Map, Favorites, Info.** Every tab now lands on a real
screen. The Map ships its first two phases — stops on Apple's basemap, tap one
for a stop card grouped by line, tap a line to follow that specific bus: its
route, the stops after yours, and when it reaches each of them (§11.1). Phase 3
(live vehicle positions) is still ahead, and is the only part that needs work in
`porto-bus-api` that hasn't been done.

Two screens from the original plan no longer exist, on purpose:

- **Departures** (one line, combined live+scheduled) — built, then deleted.
  Nothing links to it anymore; see §6.2 for why.
- **Stops** (search by name) — built, then replaced by Favorites. See §6.4.

Platform: **iOS 17+**, iPhone, SwiftUI. Swift 6, strict concurrency.
**No third-party dependencies** — `URLSession` + `async/await` + `Codable`
covers every endpoint. MapKit is first-party and arrives with the Map tab.

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
      Board/                    # BoardView + BoardViewModel; hosts ArrivalTone
      Lines/                    # LinesScreen -> LineStopsView -> StopDetailView
                                #   StopBoardList  — shared stop rows (§6.4)
                                #   LineDetailView — follow one bus (§11.1)
      Favorites/                # FavoritesScreen + FavoritesViewModel
      Map/                      # MapScreen, MapViewModel, MapStopSheet
      Settings/
      Info/
    Design/                     # LineBadge, Color+Hex, FavoriteSwipeButton
    Core/                       # AppServices, AppSettings, FavoritesStore
    Location/
  PortoBusWidget/                # not yet built
```

**Why the package/app split.** It is not ceremony. It buys two concrete things:
the widget target reuses the client without duplicating it, and the entire
Model layer is testable with no simulator and no UI. The boundary is enforced
by `PortoBusKit` importing neither UIKit nor SwiftUI.

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
- `arrival_minutes` / `eta_minutes` / `delay_minutes` / `leave_in_minutes` are
  **`Double`, not `Int`**. They're passed through unrounded from upstream (e.g.
  a real observed `delay_minutes: 0.8`) — modelling them as `Int` decoded fine
  against hand-written test fixtures but broke on the first real API response.
  Round only at display time (`BoardViewModel.etaText`).
- `Line` carries `color` / `text_color` — GTFS's `route_color`/`route_text_color`,
  normalised API-side to `#RRGGBB` (see §7 Colours).
- Every domain model has a **public memberwise `init`**, even though Codable
  synthesises one automatically — Codable's synthesised init isn't `public`
  across module boundaries, so the app target couldn't construct these types
  for mocks/previews without it. Not optional if `PortoBusKit` is going to be
  a real package boundary, not just a namespace.

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
  view work — it should expose the hex string (or a small enum like
  `ArrivalTone`) and let the View map it. This is the test for whether the
  separation is real.
- **ViewModels expose formatted, display-ready values.** `"Arriving"` vs
  `"6 min"` is decided in the ViewModel, not with a ternary inside a `Text`.
- **Shared formatting logic lives on whichever ViewModel owns the concept, and
  other ViewModels call it.** `BoardViewModel.etaText` and
  `BoardViewModel.arrivalTone(forStatus:)` are reused by `StopDetailViewModel`
  and `FavoritesViewModel` rather than each reimplementing the same rounding
  and status-mapping rule. One rule, one place it can drift.
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
construction rather than remembered. §8 explains why the empty case in
particular is load-bearing here.

---

## 5. Navigation — the floating tab bar

Adopted from the Lisbon Metro app: a **floating pill-shaped bar** over the
content rather than a standard `TabView` chrome. It reads as part of the app
instead of part of the OS, and it lets the map run full-bleed underneath.

Five destinations:

| Tab            | Icon        | Status      |
|----------------|-------------|-------------|
| **Board**      | compass     | ✅ ships    |
| **Lines**      | bus         | ✅ ships    |
| **Map**        | map (centre, emphasised) | ✅ ships (Phase 1, §11.1) |
| **Favorites**  | heart       | ✅ ships    |
| **Info**       | info        | ✅ (settings + about) |

`Favorites` replaced the originally-planned `Stops` (search-by-name) tab — see
§6.4.

Details worth copying from the reference, all implemented:

- The **centre item is visually dominant** — larger, filled, dark. In the
  Lisbon app that's the map; for us it now holds real content, which is what
  the slot was always reserved for.
- The **selected tab expands to show its label** while the others stay
  icon-only. Costs nothing, and it makes a five-icon bar legible.
- Content **scrolls under** the bar via a per-screen `.floatingBarInset()`
  modifier (a fixed-height clear spacer applied to each `List`/`ScrollView`).
  Reserving space with a `safeAreaInset` on the *root* view doesn't reach a
  `List` inside a `NavigationStack` two levels down — it has to be applied to
  the scrollable content itself, or the last row renders under the bar.

**Cost, confirmed real:** a custom floating bar means hand-rolling what
`TabView` gives free — selection state, per-tab navigation stacks, and correct
safe-area insets. It took real iteration to get right (see the inset note
above), not just styling.

**v1 navigation model:** each tab is a plain push stack (`Lines` -> a line's
stops -> the shared stop screen). Switching tabs resets that tab's stack —
accepted for now; the alternative (preserving all five stacks) means keeping
every screen's polling alive at once.

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

- **Primary (trailing, large):** `eta_minutes`, coloured by `ArrivalTone` (§7).
  `0` renders as "Arriving".
- **Secondary (below):** `stop_name` and `walk_minutes` — context for the
  rider's judgement, not a directive.
- **Leading:** line badge, filled with the row's `color` / `text_color` (the
  true realtime colour, not the GTFS family colour — see §7).

The **reachability filter still runs**: rows with `catchable: false` are hidden
by default. Buses you provably cannot reach are noise, and that filter is what
makes this a board rather than a list of nearby buses. `leave_in_minutes` is
still doing its job — it just isn't the headline. A toggle reveals unreachable
rows (`include_unreachable=true`).

**Sorting:** by line, the API's default, so a line stays in the same place
between refreshes and it reads like a station board instead of a list that
reshuffles under your thumb. `?sort=eta` offered as a toggle.

**Rows are informational, not links.** Originally each row pushed into a
combined-departures screen for that one line (§6.2). Removed: tapping a Board
row to "see all the buses for that line" duplicated exactly what the Lines tab
already shows for that stop, one tab over. A rider who wants the fuller picture
for a line already has a faster path there than a per-row drill-down.

**Favoriting is a swipe, not a persistent icon.** Board is scanned constantly;
a heart on every row would be visual noise for something used occasionally.
Swiping favourites the **station** the row departs from (`Stop`), not the row's
specific line — see §6.5 for why favourites are stations, not station+line
pairs.

### 6.2 Departures — built, then deleted

*(Historical: kept for the reasoning, since the endpoint it used is still very
much alive and could anchor a future screen.)*

`GET /stops/{code}/departures?line=` merges live + scheduled for one line at
one stop, tagged `source: "realtime" | "scheduled"` per entry — solid pill vs.
faded outline, live ETA vs. scheduled clock time. It was reachable from a Board
row and from a stop's arrival list.

**Removed** once every path leading to it turned out to duplicate a screen the
rider could already reach faster:

- From Board: the Lines tab already shows that stop's full board.
- From a stop's arrival list (`StopDetailView`, §6.3): that screen already
  covers roughly the next hour per line, live-tracked — going deeper into a
  single line's combined view showed nothing genuinely new.

The underlying endpoint, `CombinedDeparture`/`StopLineDepartures` in
`PortoBusKit`, and the client method are all still there — nothing currently
calls them, but they're a real, tested capability if a future screen needs
"everything upcoming for one line, including scheduled fallback beyond what's
tracked."

### 6.3 Lines — every line, then every stop, then everything at that stop

`GET /lines` -> `GET /lines/{line}/stops?direction_id=` -> the shared stop
screen (§6.4).

**`LinesScreen`** — every line, ordered by number (§7), coloured by its
official GTFS `route_color`/`route_text_color`. Tap a line to see its stops.

**`LineStopsView`** — the ordered stop list for one line+direction. A toolbar
button flips `direction_id` 0↔1 — **except on lines 300 and 301**, which are
circular (loop back to their own start) and have no meaningful "other
direction" to invert to.

Tapping a stop pushes into the shared stop screen, not a single-line view —
see §6.4 for why that matters specifically when a stop serves several lines.

**Originally planned differently.** The first sketch of this screen (before it
was built) was an accordion: tap a stop to expand it in place and see its
arrivals inline, load lazily. What actually shipped is plain push navigation
throughout instead — simpler, and it let the stop screen be the same shared
component Favorites also uses, rather than a bespoke inline-expand view.

### 6.4 The shared stop screen — every line serving one stop

`GET /stops/{code}/realtime`. Reached from Lines (via a line's stop list) and
from Favorites (§6.5).

**The whole point of this screen: it is not filtered to the line you drilled in
from.** Real case that drove this: Santa Justa serves lines 701, 702, and 703.
Landing here after tapping through line 701 and seeing *only* 701 would hide
702 and 703 arriving at the exact same physical stop. So this screen always
shows every line currently arriving, sorted by soonest ETA — the trade-off from
§6.1 in reverse: Board is one line, this is one place.

**Superseded: rows used to be informational, not links.** The argument was that
the board already covers roughly an hour ahead per line, so there was nothing
further worth drilling into. That was right about *more of the same* and wrong
about *something else*: "when is the next 701" is answered here, but "where does
this 701 take me, and when do I get there" was not answered anywhere. Rows now
push the line detail (§11.1, Phase 2). Board's rows stay informational — the
reasoning there (§6.1, §6.2) was about the same-line case and still holds.

Rows are also **grouped by line and direction** rather than listed flat: one row
per line, its destination, and the next two ETAs ("6, 21 min"). Grouped by line
*alone* would be wrong — most stops are served in both directions, and merging
those puts a Matosinhos bus and a Cordoaria bus under one heading with
interleaved times.

The rows live in `StopBoardList`, shared by the pushed screen and the Map's
sheet. They had briefly diverged, which quietly made this section's "one screen
in two frames" claim false; a shared view is what keeps it true.

**The toolbar heart favourites the whole station**, not any one line at it —
see §6.5.

### 6.5 Favorites — pinned stations, not pinned lines

Replaced the originally-planned **Stops** tab (search stops by name). Dropped
because it turned out redundant: Board already answers "what's near me," and
Map (once built) will answer "what's around this point" — a free-text name
search didn't earn a tab on top of those. **Known, accepted trade-off:** there
is currently no way to jump straight to a stop by typing its name if you don't
already know a line that serves it or aren't near it. Not solved by Map either
(a map answers "near me," not "type a name") — flagged here rather than
silently dropped, in case it's missed later.

**A favourite's identity is a station (`Stop`), not a station+line pair.** This
was a real course-correction mid-build: the first version favourited
`(stopCode, line)`, with the heart living on the (now-deleted) Departures
screen. Wrong granularity — favouriting is "a place I check," not "a specific
route through it." Fixed by moving the heart to the shared stop screen (§6.4),
favouriting the whole `Stop`, and having `FavoritesStore` persist `[Stop]`
(`Codable`, `UserDefaults`) instead.

**Two entry points, both station-level:**
- Swipe a Board row -> favourites the stop that row departs from.
- Tap the heart on the shared stop screen (§6.4) -> favourites that station.

**The Favorites tab is a preview list, not a full board per station.** Each row
shows the station name and its **single soonest live arrival across every
line** — not every arrival, not one row per line. Tapping a row pushes into the
same shared stop screen (§6.4), which has the full picture. Rationale: N
favourited stations means N parallel `/realtime` calls just to render the tab
(there's no "give me several arbitrary stops at once" endpoint — Board's
server-side multi-stop poll is scoped to stops near *one* origin, not an
arbitrary set); showing one summary line per station keeps that cost bounded
and the list scannable. If it ever proves too slow, or too thin, the fallback
already discussed is a fuller "mini-board" per station — deferred until it's
shown to be needed.

A station that fails to load still appears, with a blank ETA, rather than
disappearing from the list — same "empty isn't the same as broken" principle
as §8.

---

## 7. Colours

Two genuinely different colour sources exist in the API, used deliberately
differently:

- **The realtime feed's colour** (`Arrival.color`, `BoardRow.color`) — the
  *true* per-line colour, only available where there's a live board to ask
  (Board, the shared stop screen). Used for line badges everywhere those
  screens can supply it.
- **GTFS's `route_color`** (`Line.color`, added to the API and to
  `PortoBusKit.Line` this round) — a coarser *family* colour (most city lines
  share `#187EC2`), but it's the only colour available **globally**, with no
  specific stop or live context — exactly the situation the Lines tab is in.
  Confirmed against the real feed: city lines blue (`#187EC2`/white), the
  **M-family is official black** (`#000000`/white — not a fallback, an actual
  GTFS value), and e.g. line 701 red (`#FF0000`/white). A line with no GTFS
  colour at all falls back to a neutral badge rather than rendering black.

  Earlier drafts of this document said the GTFS colour "must not be used for
  badges" — true for Board specifically (where the better, live colour is
  always available), false as a blanket rule once a screen (Lines) has no live
  context to draw from at all.

**ETA colour — `ArrivalTone`, not a live/not-live indicator.** Originally, rows
carried a `realtime: true|false` flag with a green dot + "live" caption for
tracked buses. Removed and replaced with colouring the ETA number itself by
on-time/delayed status (green = `ON_TIME`/`ARRIVING`, red = `DELAYED`, plain
for the rare/theoretical case with no status at all):

- The live/not-live flag turned out to almost never vary — every stop observed
  in practice reports `realtime`, so the dot was static, carrying little
  information turn to turn.
- On-time-vs-delayed visibly *does* vary, row to row, in real data (confirmed
  live: line 507 `DELAYED` +8.3 min and line 703 `ON_TIME`, from the same
  stop, same moment).
- The colour is driven by STCP's own `status` field, **not** a threshold
  re-derived from raw `delay_minutes` — STCP already absorbs sub-minute noise
  into `ON_TIME` (observed: a 0.8-minute delay still reports on-time), so
  inventing our own cutoff risks disagreeing with what STCP's own app shows
  for the same bus. Trust upstream's classification.
- No status caption text ("Delayed 7 min") under the ETA — considered
  (inspired by transit apps that show it), decided against for now: just the
  coloured number.

`BoardViewModel.arrivalTone(forStatus:)` is the one place this rule lives;
Board and the shared stop screen both call it.

---

## 8. Behaviour

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

A one-shot location fix can silently never arrive (notably on the simulator) —
`LocationProvider` times out (~4s) and falls back rather than hanging the board
indefinitely. Found the hard way: the very first simulator run spun on
`.loading` forever with no error, because nothing was timing out the request.

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

### Degraded is not the same as broken

The same principle, one level deeper. The API is gaining a local GTFS store and
will fall back to it when STCP's live feed is unreachable, tagging the response
via the fields the contract already has — `RealtimeStop.data_source`,
`BoardRow.realtime`, `CombinedDeparture.source` (see the API repo's README §2a).

Before that store existed, *every* time-related answer was an upstream call, so
STCP going down blanked every screen in this app simultaneously. Afterwards the
same outage yields today's timetable instead — which is genuinely useful, and
genuinely not live. The app must say which:

- **Live** → today's rendering, unchanged.
- **Fell back to timetable** → the rows, plus a persistent banner: "Live data
  unavailable — showing today's timetable." Not an error state; the content is
  real and worth reading.
- **Feed expired upstream** → treated as an error, not as data. A timetable
  outside its validity window is a guess wearing a schedule's clothes.

The ETA colouring (§7) is the trap here: an on-time/delayed tone implies
tracking that a scheduled row does not have. Scheduled rows render in the
neutral tone regardless of how close they are.

---

## 9. Widget

Small and medium, showing the next few catchable departures with `eta_minutes`.
**Not yet built.**

**Known limitation, accepted:** WidgetKit refreshes on its own budget (roughly
every 15 minutes), so the widget cannot be genuinely live. It is a "before I
leave the house" glance, not a departure board. Combined with the LAN constraint
below, it will be blank away from home until the API is hosted.

---

## 10. Talking to the API

v1 is **LAN only**.

**Correction, verified:** this section used to say the API binds `127.0.0.1` and
must be changed to listen on `0.0.0.0` before a phone can reach it. That is
false. `src/index.js` calls `app.listen(port, callback)` with no host, so Node
binds every interface already — only the startup *log line* prints
`127.0.0.1`, which is what the claim was really based on. Confirmed by curling
the Mac's LAN address: `http://192.168.1.119:8000/health` → 200, no code change.

So there is one setup step, not two:

1. iOS blocks cleartext HTTP. `NSAllowsLocalNetworking` in the app's Info.plist
   allows it for the local network broadly (RFC-1918 / `.local`), rather than
   pinning one IP — so the Mac's address can change without an Info.plist edit.
   For a physical device (not the simulator), iOS also separately prompts for
   **Local Network** permission the first time the app makes an LAN request;
   needs `NSLocalNetworkUsageDescription` too.

**Which URL to put in Settings:**

| Running on | Base URL |
|---|---|
| iOS Simulator | `http://127.0.0.1:8000` — reaches the Mac directly |
| A real iPhone on the same Wi-Fi | `http://<mac-lan-ip>:8000`, e.g. `http://192.168.1.119:8000` |

The LAN address changes with the Mac's DHCP lease. `NSAllowsLocalNetworking`
covers the whole local network, so only the Settings field needs updating —
never the Info.plist.

**Dev note:** `UserDefaults` reads `NSArgumentDomain` at highest precedence, so
the stored base URL can be overridden at launch without touching Settings:

```
xcrun simctl launch <device> com.portobus.app -settings.baseURL "http://127.0.0.1:8001"
```

Worth knowing because the Settings text field cannot be cleared by automation
(no backspace), which makes retargeting a simulator build otherwise painful.

**The base URL is a stored setting from day one**, even though it points at a
LAN address for now. Ten lines of code that turn "deploy the API" into a
settings change rather than a refactor.

### Usage descriptions go in `info.properties`, never `INFOPLIST_KEY_*`

A trap that cost real debugging time, so it is written down rather than
rediscovered.

`project.yml` declared the location and local-network usage strings as
`INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` and friends. Xcode only
merges `INFOPLIST_KEY_*` build settings into the plist when
`GENERATE_INFOPLIST_FILE` is `YES`. This target sets an explicit
`INFOPLIST_FILE` instead, so **every one of those keys was silently dropped** —
no warning, no build error, just a shipped Info.plist without them.

The symptom looked nothing like the cause. Without
`NSLocationWhenInUseUsageDescription`, `requestWhenInUseAuthorization()` is a
**no-op**: no permission alert ever appears, `authorizationStatus` stays
`.notDetermined` forever, the Board silently falls back to home coordinates,
and MapKit's own location manager fails with `kCLErrorDomain Code=1` — which
reads as "the user denied access" when the user was never asked. Chasing it as
a permissions or simulator problem is the natural and wrong move; two clean
simulators reproduced it identically, which is what finally ruled the
environment out.

So both usage strings now live in the `info: properties:` block alongside
`UILaunchScreen` and `NSAppTransportSecurity` — the path already proven to
reach the built plist. **Verify with `plutil -p` on the built `.app`, not on
`project.yml`.**

---

## 11. Planned features (post-v1)

### 11.1 Map — up next, in three phases

The Map tab has been a placeholder since day one. It is next, and it is
**three features stacked**, not one — and the first of them needs no work in
`porto-bus-api` at all.

**Superseded.** This section used to read "Live vehicle map — up next" and said
the map was blocked until the API could serve vehicle positions. The blocker
was real but misattributed: live *vehicles* need a new endpoint, live *stops
and routes* do not. Every coordinate a useful map needs is already served
today. Treating the map as one indivisible feature kept the tab empty for no
reason. The vehicle-inference argument was sound and survives intact as Phase 3.

**MapKit costs nothing.** Native MapKit on iOS — `SwiftUI.Map`, `MKMapView` —
is free and unmetered, and needs no API key. The quotas and billing people run
into belong to **MapKit JS** (web embeds) and the Apple Maps Server API,
neither of which we touch. There is no case for evaluating a third-party map
SDK, and none that would survive the no-dependencies rule anyway.

**Apple's own transit pins are not usable as our data.** Apple Maps knows about
STCP stops, and `selectableMapFeatures` (iOS 16+) makes its POIs tappable — but
a tapped `MKMapFeatureAnnotation` yields a name and a coordinate and no
`stop_code`. Binding one back to our stop means fuzzy name-and-distance
matching that breaks silently whenever Apple's data shifts. So: **our own
annotations on Apple's basemap**, which is what every transit app does. Apple's
`.publicTransport` POIs are then *filtered out* via `pointOfInterestFilter`, so
its pins don't sit beside ours saying something slightly different.

#### Phase 1 — the stops map. **Shipped.**

Full-bleed map under the floating bar; user-location dot and a recentre
button; stop pins; tap a pin for a bottom sheet with that stop's live board.
Built as `Features/Map/` — `MapScreen`, `MapViewModel`, `MapStopSheet`.

Everything it needs is already built on both sides:

| Need                    | Endpoint                        | Client method            |
|-------------------------|---------------------------------|--------------------------|
| stop pins               | `GET /stops` (carries lat/lon)  | `stops(query:limit:)`    |
| tap a pin -> live ETAs  | `GET /stops/{code}/realtime`    | `realtime(stop:)`        |
| "what's around me"      | `GET /board?lat=&lon=`          | `board(lat:lon:)`        |

Reuse, not new code: the sheet is the existing shared stop screen (§6.4) —
`StopDetailViewModel` takes a `Stop` and needs no change — and the favourite
button is the existing `FavoritesStore`. The sheet uses `presentationDetents`
plus `presentationBackgroundInteraction(.enabled)` so the map stays draggable
underneath it, which is the Apple Maps feel and the reason it's a sheet rather
than a push.

Two constraints found while scoping it:

- ~~**`/stops?limit=` clamps at 2000, and Porto has more stops than that.**~~
  Fixed in the API: the clamp was truncating Porto's 2,568 stops, and there is
  now **`GET /stops?bbox=minLon,minLat,maxLon,maxLat`** backed by an index.
  This changes the app side materially — the map asks for what is on screen and
  never holds the network in memory, so no local stop cache is needed for
  Phase 1.
- **Do not hand MapKit ~2500 annotations.** With `bbox` the server bounds the
  set, but the camera still has to drive it: refetch on `onMapCameraChange`
  (debounced), and only past a zoom threshold. Clustering is deliberately not
  the first answer: it exists only on `MKMapView` (`clusteringIdentifier`), not
  on SwiftUI's `Map`, so reaching for it means wrapping a `UIViewRepresentable`.
  Do that if bbox-plus-zoom-threshold proves insufficient, not before.

**SwiftUI `Map`, not `MKMapView`.** The iOS 17 API (`Map(position:)`,
`Annotation`, `MapPolyline`, `MapUserLocationButton`, `onMapCameraChange`)
covers Phases 1 and 2 outright. Clustering is the one known thing it can't do —
see above. Confirmed in practice: Phase 1 needed no `UIViewRepresentable`.

#### Detail arrives in stages, not all at once

Modelled directly on how Apple Maps treats its own transit stops, because the
problem is identical: 2,568 stops cannot say the same amount at every scale.
`MapDetailLevel` picks one of four, keyed on the viewport's latitude span —
a stable proxy for zoom that means the same thing on every device size:

| Level             | Span      | What a stop shows                    |
|-------------------|-----------|--------------------------------------|
| `hidden`          | > 0.075   | nothing — pins would be a smear      |
| `dots`            | ≤ 0.075   | a small coloured dot: "stops exist here" |
| `marks`           | ≤ 0.020   | the app mark on a disc               |
| `marksWithLines`  | ≤ 0.006   | the mark **plus the line numbers**   |

**The thresholds were set by looking, not by feel.** At 0.011 the line badges of
adjacent stops overlap into an unreadable mass in the city centre; at 0.004 they
sit clear of each other. Porto's downtown density is the hard case, so it sets
the number.

**The mark is the app's own logo, drawn as vectors** (`PortoBusMark`), not a
bitmap — it has to work from a 1024pt app icon down to a 26pt map badge. Its
two nodes are stroked rings rather than filled circles with a punched hole, and
the ring's arcs stop at the nodes' outer edges, so the centres stay transparent
and one drawing serves a light disc and a dark one.

The disc behind it is doing real work: the mark has fine negative space, and the
basemap underneath is textured. Without a clean ground it turns to mush at pin
size — which is the honest objection to putting *any* logo on a map pin, and the
reason the roundel exists rather than the bare mark.

**Line numbers cost one request per region, not per stop.** The API derives
`stop_routes` at ingest (API README §2a), so `/stops/lines?bbox=` answers a
whole screen in ~10 ms. Without that this feature would need a round trip per
stop and would not be worth building.

**`Annotation`, not `Marker`.** `Marker` always draws Apple's teardrop balloon
and only takes a tint and a glyph. A stop sits *at* a point rather than pointing
at one, which is why Apple's own transit stops are flat roundels too.

**A trap worth naming.** The annotation's inputs are read while the view's body
evaluates — `MapViewModel.Annotated` bundles each stop with its lines for
exactly this reason. Reading the lines *inside* the `Annotation`'s content
closure looks equivalent and is not: that closure runs outside the body's
observation scope, so an update that changes only the labels — and no stop —
never redraws. The tags silently never appeared, and it read as a data problem
for far longer than it should have.

**What Phase 1 actually does, as built:**

- `onMapCameraChange(frequency: .onEnd)` plus a 250 ms debounce, with the
  in-flight fetch cancelled — a pan fires the camera callback continuously, and
  one request per frame would be both wasteful and out of order.
- Fetches a box **35% larger** than the visible one, and skips the fetch
  entirely when the new region is still inside what's already loaded. Small
  pans are therefore free, with no blank margin filling in a beat later.
- Past the widest threshold it drops all pins and says "Zoom in to see stops",
  and at `dots` it says "Zoom in for stop details". A solid mass of markers
  communicates nothing, and the banner is the honest version of that.
- A failed fetch **keeps the pins already drawn** and says "Couldn't load
  stops". Clearing them would assert "no stops here", which is a different and
  false claim — §8 again.
- The map opens on Aliados before the location fix resolves, rather than on the
  Atlantic while waiting for permission.

#### Phase 2 — the stop sheet and line detail. **Shipped.**

**Superseded.** Phase 2 used to be "draw one line's route polyline on the map,
reached from the Lines tab". That still happens, but as one part of something
larger rather than the whole feature. The replacement is modelled on Apple Maps'
own transit stop card (screenshots reviewed against the London bus network,
where Apple has full TfL data), and it is strictly better: the polyline was
scenery, whereas this answers "which bus, when, and where does it take me".
It also does most of the groundwork for Phase 3.

**The stop sheet** — what a map pin already opens, restructured:

- Departures **grouped by line and direction**, not a flat list. One row per
  line: badge, destination, then the next two ETAs ("6, 21 min"). Grouped by
  line *alone* would be wrong — see §6.4.
- Live ETAs render green; scheduled ones stay neutral. Same `ArrivalTone` rule
  as the Board (§7), same reason — and it needed no new code, because an
  untracked arrival already has a null `status`, which already maps to
  `.unknown`, which already renders neutral.
- No "get there" / directions button. This app answers "what can I catch",
  not "route me somewhere" — that is the `/journey` case, and it isn't built.
- Built as `Features/Lines/StopBoardList.swift`, shared with the pushed stop
  screen. §6.4 has always claimed those two are one screen in two frames;
  restructuring only the sheet would have quietly made that false.

**Tapping a line** opens the line detail (`LineDetailView`):

- The route drawn in the line's colour with its stops, the rider's own a filled
  disc and everything ahead hollow — **on the Map tab's own map**, not on a
  second one inside the card. See below.
- **The stops after theirs**, in order, each with a projected clock time, on a
  vertical rail in the line's colour.
- Every **departure of that line from that stop** as a row of bubbles along the
  top, live ones green and timetable ones neutral. They are a selector, not a
  readout — see below.

##### The route goes on the map that is already there

**Superseded.** The line detail first shipped with its own inline map at the top
of the card. Reached from the Lines tab that is right — there is nothing behind
it. Reached from the Map tab it was plainly wrong: the card is a sheet sitting
*over* a full-screen map, so a second, smaller, worse map appeared on top of the
good one, and the good one showed unrelated stop pins for a neighbourhood
nobody was looking at.

Now the card publishes to `AppServices.route` (a `RouteOverlay`) and the Map tab
renders it, which is the Apple Maps arrangement. Three details make it work:

- **The map re-frames to the route**, fitting it into the *visible* strip rather
  than centring it under the sheet — `MKCoordinateRegion.fitting(_:visibleFraction:)`
  doubles the span and pushes the centre south for that. It re-frames when the
  rider picks a different departure and never on the 20-second refresh; a camera
  that snapped back mid-pan would be unusable.
- **The sheet minimises to 120pt**, making the detents `[120pt, 45%, full]`. The
  small one is the whole point of putting the route on the real map: a route
  drawn across the city is what the rider came to see, and a card pinned over
  the bottom half of it is in the way. With only two detents it was unreachable.
- **The map draws the whole trip's stops, not the ones ahead.** It first drew
  only the journey — the same list the card shows — which put a polyline across
  the length of Porto with dots on the last third of it and read as a data
  error. The *list* stays origin-onward; only the map is the whole line.
- **Three dot weights, following Apple Maps.** The two ends of the line and the
  rider's own stop are filled discs; everything between is a hollow ring, thinly
  stroked. The stroke width is not a detail — at 2.5pt on a 10pt circle it was
  most of the dot, and the route read as a string of heavy blobs rather than as
  a line with stops on it.
- **Stop names are drawn, and MapKit declutters them.** Keeping
  `.annotationTitles(.automatic)` rather than labelling by hand is what makes a
  name per stop viable on a 50-stop route: MapKit drops colliding labels as the
  map zooms, so a city-wide view shows six names and a street-level one shows
  all of them. Hand-rolled labels would mean rebuilding that, worse.
- **Superseded: the stops behind the rider were briefly faded to 40%**, on the
  theory that the part of the route already covered shouldn't compete with the
  part ahead. It just looked like a rendering fault — half the line greyed out
  for no reason a rider could see. The filled termini answer "which way does
  this go" better, and without dimming anything.
- **The stop pins go away while a route is drawn.** They are noise on top of the
  one thing being looked at, and the "Zoom in to see stops" banner goes with
  them — advice about a screen the rider isn't on.
- **The overlay lives on `AppServices`, not on `MapScreen`.** This was found the
  hard way: an `.environment(overlay)` attached partway down the Map tab does
  *not* reach a sheet presented from it, because a sheet is hosted outside the
  presenting view's hierarchy. `AppServices` is injected at the app root, above
  every presentation, so it does. Whether a host map exists is a separate plain
  environment flag, `hostDrawsRoute`, set once by `MapStopSheet` — the same
  mechanism as `floatingBarVisible`, which was already proven to cross that seam.

##### The bubbles are the control, not a footnote

**Superseded.** The row started as "*other* departures", with the bus being
followed filtered out of it. Two things were wrong with that. It hid the one
departure the rider was actually looking at from the row that lists departures.
And it left no way to ask about a different one — the screen could only ever
describe the bus you arrived on.

So the row is now every departure, the followed one included and ringed, and
tapping one follows it: the stops ahead, their times, and the route all
recompute for that departure. Which means the earlier careful work to drop
exactly one duplicate chip is gone — deleted rather than fixed, because the
thing it was solving stopped being a problem once the followed bus belonged in
the row.

**A scheduled bubble has no bus behind it, and that shows.** Its ETA and every
time below it render neutral, never green, because a timetable slot has no
on-time truth to report — the same `ArrivalTone` rule as everywhere else (§7).

**Selecting must not flash "nowhere to follow".** Tapping a bubble drops the
previous trip immediately — leaving it up would show one bus's stops under
another bus's times — so for the length of one request there is genuinely
nothing to draw. Rendering that as the empty-state card made every tap blink an
error that was also false, and read as a broken button. The screen now
distinguishes *empty* from *not yet*: `isResolving` holds the space with a
spinner, and `isEmptyAfterLoading` is the only thing allowed to show the card.
Worth stating as a rule rather than a fix — any screen that clears state before
refetching has this bug available to it.

**Resolving one needed an API addition.** A tapped bubble has to become a trip,
and the scheduled half of `/departures` comes from upstream, which serves times
and headsigns with no `trip_id` to ask by. Two changes, both small:
`CombinedDeparture` now carries `trip_id` where it is known (always on live
rows), and `GET /trips/stops` answers the same question from line + stop +
departure time when it isn't. That is not a new mechanism — it is the `pattern`
rung of the fallback chain that already existed, reached directly instead of
after a failed id lookup.

##### Resolving the live bus to a real trip

The downstream stop times depend on knowing *which specific bus* is coming, then
reading its whole journey. The live board gives `Arrival.trip_id`; the store has
`stop_times` for every trip. In principle that is a join.

**It is not a direct join, and this cost real time to discover.** Live returns
`601_0_1|280|D3|T1|N6`; the store holds `601_0_1|276|D3|T1|N6`. The second
pipe-delimited field is a *feed-version counter* — STCP was serving schedule
`280` while the ingested GTFS zip was `276` — and matching verbatim resolves
nothing at all.

**Measured against the live feed while building this** (2026-08-16, 71 arrivals
across 8 busy stops): **0 of 71** matched verbatim, **71 of 71** matched with the
version field stripped, each to exactly one trip, headsigns agreeing every time.

Two conditions on that join, one of which turned out to be subtler than the
original note here suggested:

- **Strip the version field** on both sides before comparing.
- **Filter to the day's active service.** 5,386 of 12,716 stripped keys collide
  — but *not* uniformly. Every collision is a `UTIL FERIAS` weekday pattern
  reissued as versions 274 / 275 / 276 of itself. So a weekday live id lands on
  a three-way tie and a Saturday one does not, which is exactly why the 71/71
  sample above must not be read as evidence the filter is unnecessary: it landed
  on a Saturday. The service filter is still what makes a weekday unambiguous.

This is a join on an undocumented id format, so it needs a fallback rather than
trust. The API implements the whole chain and **reports which rung answered**, in
`match`: `exact` -> `version` -> `version_latest` -> `pattern`, then a 404. The
app reads it: anything below `version` earns a note saying the bus was matched by
line and destination rather than by id.

**`version_latest` was not in the plan and had to be invented.** The plan assumed
the service filter always narrows the tie. It cannot when the day has *no* active
service at all — which is the state the store is in right now, because the feed
expired on 2026-08-15 and `service_dates` simply stops there. The choice was
between refusing (a screen that works on Tuesday and not Saturday) and picking
deterministically. It picks the newest feed version — the reissue rather than the
superseded copy — and says so, so the app can be less confident about it.

**An expired feed is flagged, not withheld.** Everywhere else in the API an
expired feed disqualifies the store from standing in for live data, because there
it would be impersonating a measurement. Nothing is impersonated here: the caller
already holds the live ETA and wants the stop order and the gaps, which barely
move between reissues. `feed_expired` rides along in the response and the app
turns it into a sentence rather than hiding it.

##### How the downstream ETAs are computed

Once the trip is resolved, `stop_times` gives a scheduled time at every stop on
it, so:

```
ETA(later stop) = live ETA at my stop + (scheduled(later) − scheduled(mine))
```

The live number anchors the sequence; the timetable supplies the gaps between
stops. That is exactly what Apple shows — 08:43, 08:44, 08:46 — where the
spacing is schedule and only the anchor is real.

**Carrying the current delay forward is an assumption, not a measurement.** A
bus four minutes late may make it up. So only the imminent departure is styled
as live; everything downstream renders as scheduled, however confident the
number looks. This is §8 again — the projected part must not dress as the
measured part.

**The anchor has to keep being live, which was a bug before it was a rule.** The
line detail is handed the `Arrival` the rider tapped, and the obvious thing —
holding onto it — makes the whole screen a photograph. "5 min" reads 5 min
forever while every projected clock time below it silently drifts by the same
amount, and nothing about the screen looks wrong.

The first fix re-read the stop's live board each refresh and re-found the same
bus in it. The bubbles then made that machinery redundant: the anchor is just
the selected bubble, and the bubbles come from `/departures`, which is already
refetched every 20 seconds. A bus that has left simply stops appearing there,
which the screen reports as **Departed** — and the projected times go with it,
because the number they were measured from has stopped existing.

`arrival_seconds` in the trip response exists for this arithmetic — doing it on
`"24:35:00"` strings would re-invite the after-midnight bug the API already
solved once.

##### Two smaller things worth writing down

- **Matching the tapped board row to a bubble is fuzzy, and has to be.**
  `/realtime` and `/departures` are separate upstream calls seconds apart, so the
  same bus routinely differs by a minute between them. The initial selection
  therefore matches on `trip_id` when both sides have one and on nearest ETA
  otherwise. After that the selection is keyed on `trip_id ?? clock`, which
  survives refreshes: a scheduled slot's timetable clock doesn't move, and a live
  bus has an id — its *estimated* clock does move, which is exactly why the clock
  isn't the key when an id exists.
- **Direction needs no parameter.** STCP stop codes are per-direction — CARMO
  outbound and CARMO inbound are different codes — so a stop already pins it.
  Confirmed against the live feed: `/stops/CMO/departures?line=601` returns one
  destination, never both. The direction still has to be *known* for
  `/lines/{line}/shape`, and comes from the resolved trip, falling back to the
  one `/departures` detected.

##### What it needed

| Piece | Source | Status |
|---|---|---|
| Departures grouped by line | `/stops/{code}/realtime` | data already there |
| Route + stops on the map | `/lines/{line}/shape`, `/lines/{line}/stops` | endpoints exist |
| Stops after mine, with times | `stop_times` for the resolved trip | **built**: `/trips/{trip_id}/stops` (API README §4c) |
| Every departure, same line + direction | `/stops/{code}/departures?line=` | exists, **plus** `trip_id` on each row |
| The journey behind a *scheduled* departure | pattern match, no id to ask by | **built**: `GET /trips/stops` |

Scoped as one new endpoint; ended up as two, the second one small and only
needed once the bubbles became tappable.

**A note on the sheet-vs-tab seam.** The line detail is reachable two ways — from
the Map's stop sheet and from the Lines tab — and they disagree about two things
the screen cannot work out for itself: whether the floating bar overlaps its
bottom edge, and whether there is already a map behind it. Both are plain
environment flags set once by `MapStopSheet`, `floatingBarVisible` and
`hostDrawsRoute`. Getting either wrong is visible immediately — 60pt of dead
space, or two maps stacked on each other.


#### Phase 3 — live vehicles

*(The Lisbon Metro app's moving trains: buses drawn along the route, tap one
for its details.)*

**This is the part that genuinely needs new API work, and the blocker isn't the
number of buses — it's that the API has no vehicle positions at all.** GTFS is
schedule data, and STCP's live API is stop-centric: it answers "what's arriving
at stop X", never "where is vehicle Y".

It is *inferable*, and one field makes it possible: **`Arrival.trip_id`**. Poll
every stop on a line and the same `trip_id` appears at consecutive stops with
increasing ETAs — which brackets the bus between two known points. Interpolate
along `GET /lines/{line}/shape` and you have a plausible position.

**Phase 2 already did most of this groundwork, and that bet paid off.**
Resolving a live `trip_id` to a real trip with an ordered stop list — the
version-field normalisation, the service-day disambiguation, and the fallback
chain that make the join survive an id format nobody documents — now exists and
is measured, as `GET /trips/{trip_id}/stops`. "Where is the bus now" reduces to
*which pair of stops is it between*, which that stop list already answers.
Doing Phase 2 first was not a detour from the live map; it was the first half
of it.

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

The app side is then small: vehicle annotations on the Phase 2 map, tap one for
a bottom card (line badge, destination, next stop, ETA).

**Order mattered.** Phase 1 shipped a map worth its centre tab slot on its own;
Phase 2 was additive on top of a screen that already worked. Phase 3 stays last
— it is the only one that can't start here.

### 11.2 Also later

- Timetable grid (`/lines/{line}/schedule`) — the trips × timepoints matrix is a
  genuinely tricky UI.
- `/journey?to=` once the API grows it; that's the Siri case.
- Live Activities for a bus you're waiting on — needs a hosted API and push.
- Resurfacing free-text stop search somewhere, if losing it (§6.5) turns out to
  be missed in practice.
- A fuller per-station board on Favorites (every line, not just the soonest),
  if the preview-row design (§6.5) proves too thin.

---

## 12. Open questions

- **Hosting the API** (Fly.io, Railway, a VPS). Until then the app is home-only
  and the widget (once built) is decorative. This is the single biggest unlock.
- ~~**Where the static GTFS data lives.**~~ **Settled.** The API now ingests the
  whole feed into SQLite daily and serves `/stops?bbox=`, so the app queries a
  region rather than caching the network. It also falls back to that store when
  STCP is unreachable — see "Degraded is not the same as broken" in §8 for what
  this app owes the user in that state. Details in the API repo's README §2a.
- **The published feed drifts ahead of the one we hold, and it bites three
  ways now.** STCP serves schedule version `280` while the ingested zip is
  `276`, and the portal has stopped republishing (feed expired 2026-08-15).
  That gap is why live `trip_id`s don't join to stored ones without
  normalisation, why scheduled fallbacks can be subtly stale, and — the third,
  found while building Phase 2 — why the day can have **no active service at
  all**: `service_dates` simply stops at the feed's last valid day, so the
  service filter that disambiguates a trip has nothing to filter with (§11.1).
  Every one of those is survivable, and each is survived by degrading and
  saying so. Any feature that leans on the store agreeing with the live feed
  should assume drift rather than trust it — and should be tested on a day when
  the store has run out, because that state is not hypothetical.
- **Public holidays are wrong in the fallback.** Measured: on 15 Aug 2026 the
  GTFS calendar said Saturday service while STCP said holiday service, and STCP
  was right. The scheduled fallback will therefore be wrong on roughly a dozen
  days a year. Still better than a blank screen, but it argues for keeping the
  banner unmissable rather than subtle.
