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

**Shipped: Board, Lines, Favorites, Info.** Map is present in the tab bar as a
"coming soon" placeholder — it's the next thing to build (§10.2), and it needs
work in *both* repos before there's anything to show.

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
      Favorites/                # FavoritesScreen + FavoritesViewModel
      Map/                      # v1: placeholder
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
| **Map**        | map (centre, emphasised) | placeholder |
| **Favorites**  | heart       | ✅ ships    |
| **Info**       | info        | ✅ (settings + about) |

`Favorites` replaced the originally-planned `Stops` (search-by-name) tab — see
§6.4.

Details worth copying from the reference, all implemented:

- The **centre item is visually dominant** — larger, filled, dark. In the
  Lisbon app that's the map; for us the map is the eventual centrepiece too, so
  it keeps the slot even as a placeholder.
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

Rows are **informational, not links**, for the same reason Board's rows are
(§6.1, §6.2): this board already covers up to roughly an hour ahead per line,
live-tracked, so there was nothing further worth drilling into.

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

v1 is **LAN only**. Two setup steps, easy to forget and expensive to debug:

1. The API binds `127.0.0.1:8000`. It must listen on `0.0.0.0` for the phone to
   reach it.
2. iOS blocks cleartext HTTP. `NSAllowsLocalNetworking` in the app's Info.plist
   allows it for the local network broadly (RFC-1918 / `.local`), rather than
   pinning one IP — so the Mac's address can change without an Info.plist edit.
   For a physical device (not the simulator), iOS also separately prompts for
   **Local Network** permission the first time the app makes an LAN request;
   needs `NSLocalNetworkUsageDescription` too.

**The base URL is a stored setting from day one**, even though it points at a
LAN address for now. Ten lines of code that turn "deploy the API" into a
settings change rather than a refactor.

---

## 11. Planned features (post-v1)

### 11.1 Live vehicle map — up next

*(The Lisbon Metro app's moving trains: buses drawn along the route, tap one
for its details.)*

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
- Tap a vehicle → a bottom card: line badge, destination, next stop, ETA.

**This is the next thing to build**, cross-repo: the vehicle-position endpoint
in `porto-bus-api` first, then the MapKit screen here.

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
