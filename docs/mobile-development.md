# FreeBeamer mobile app

Connects to a vehicle's MHD/ENET WiFi adapter, reads live MHD monitor data
over a from-scratch Dart port of `pkg/doip`/`pkg/mhd`, and relays it to a
`freebeamer-relay` instance using the same wire contract `pkg/telemetry`
defines. See `https://github.com/freebeamer/core/blob/main/docs/freebeamer-relay-v0-plan.md` and
`https://github.com/freebeamer/core/blob/main/docs/mhd-live-monitor-v0-plan.md`.

Status: `flutter analyze` is clean, all 78 tests pass, and **the full
pipeline has been proven live end-to-end on a real Android emulator**
(Pixel 10 Pro XL, API 37): the app connected over real DoIP to a mock
ECU, decoded live values correctly (RPM climbing tick by tick, `LOAD`
decoding as a genuine negative number — proving signed 16-bit fields
work), showed "buffered — no connection to relay" correctly when no
relay was configured, and — once pointed at a real `freebeamer-relay
serve` instance with a real `client add`-issued API key — switched to
"Streaming (live)" and successfully delivered samples that an
independent Go WebSocket client verified arriving at the relay's `GET
/v1/live` feed in real time, correct backfill-then-live sequencing
included. It was originally written blind (no toolchain available) and
reviewed by hand/script — that review caught one bug; installing the
toolchain and running `flutter analyze`/`flutter test` caught three more
(an `ambiguous_import` against Flutter's own built-in `ConnectionState`,
a `const`-initialized-from-non-const compile error, and a genuine
runtime bug in the socket byte-reassembly buffer); building and running
live on a real emulator, against both a mock ECU and a real relay,
surfaced none further. **Deep-link auto-connect is also proven live**:
firing a real `freebeamer://connect?...` intent at a cold-stopped app
navigates straight to `StatusScreen` with zero manual entry and reaches
"Streaming (live)" on its own — that same test caught and fixed a real
concurrency bug (see "Known gaps" below). See git log for details on all
of it. What's still outstanding: a real MHD adapter and a real vehicle,
and iOS (no Mac/Xcode available to build or run it).

**Phase 3b (reliable acquisition/upload, see below) also validated live on
the same emulator**, against a real `freebeamer-relay` and the mock DoIP
adapter. `flutter analyze`/`flutter test` were clean before the device run,
but the live run still caught **a genuine concurrency bug neither `-race`-equivalent
static analysis nor any unit test surfaced**: `TelemetryLocalDataSourceImpl`'s
`readLines` did an exists-check then a separate read, and the spool-writer
and uploader loops — two independent async loops sharing one file, an
interleaving pattern this app had never had before Phase 3b — could race
such that the uploader's `rewrite([])` (which deletes an emptied spool
file) ran between the spool-writer's check and its read, throwing an
unhandled `PathNotFoundException` and crashing the app after roughly two
and a half minutes of continuous streaming. Fixed with an async mutex
(`_AsyncMutex` in `telemetry_upload_service.dart`) serializing every spool
file operation between the two loops — the Dart analogue of
`pkg/telemetry.Spool`'s `sync.Mutex`, needed because Dart's single-isolate
cooperative scheduling only prevents interleaving within a span of code
with no `await`, and file I/O always awaits. After the fix: over three
minutes of continuous live streaming with zero crashes, samples arriving
at the relay within a second of "now" throughout, and backgrounding the
app (`WidgetsBindingObserver`) stopped delivery within the same second
with no crash or hang. This is a second concrete example (after the
DoIP/`BytesBuilder` bug found the same way) of a real, non-static-analyzable
bug this project's practice of real-device verification exists to catch —
worth remembering for any future concurrent-loops-over-shared-mutable-state
design here, in either language.

## Telemetry compatibility

The acquisition loop now negotiates the relay's client-authenticated
`GET /v1/capabilities` endpoint before connecting. Compatible relays receive v2
samples with a new session ID per connection and increasing sequence numbers.
Explicitly legacy relays keep the legacy sample shape. Offline or uncertain
capabilities retain v2 samples locally; upload rechecks support before sending,
including buffered replay. Stored v2 records are never downgraded to legacy.
See [the wire contract and rollout](https://github.com/freebeamer/core/blob/main/docs/telemetry-v2-contract.md).

## Reliable acquisition and upload (Phase 3b)

`ConnectionCubit`'s read loop no longer `await`s delivery — mirroring
`cmd/freebeamer/command_mhd.go`'s Phase 3a redesign, so a slow or
unreachable relay can never stall the next scheduled DoIP read. See
[live data and vehicle mapping plan](https://github.com/freebeamer/core/blob/main/docs/live-data-and-vehicle-mapping-plan.md)'s
Phase 3 section for the full rationale.

- `lib/core/telemetry/acquisition_queue.dart` — a small bounded in-memory
  handoff (default capacity 32, drop-oldest-and-counted on overflow) the
  Cubit's `enqueue` call is synchronous against.
- `lib/core/telemetry/telemetry_upload_service.dart` —
  `ITelemetryUploadService`/`TelemetryUploadServiceImpl`: two independent
  async loops (no `Isolate` — the work is I/O-bound, and Dart's
  single-isolate cooperative scheduling already decouples it as long as
  acquisition itself never awaits network/disk) draining the queue into a
  durable spool file, then draining that spool over HTTP with cached
  capability negotiation (5-minute TTL) and bounded-delay retry/backoff
  (1s → 60s, ×2, ±20% jitter — never gives up on a spooled sample).
- `lib/data/datasources/telemetry_local_data_source.dart`'s `append` gained
  a byte cap (`defaultSpoolMaxBytes`, 20 MiB — smaller than the Go CLI's
  50 MiB default, since mobile storage is more quota-constrained) and an
  overflow policy (`drop`/`stop`).
- `lib/core/telemetry/destination_identity.dart` — `destinationId` (SHA-256
  of endpoint+apiKey, mirroring the relay's own key-hashing convention) and
  `resolveSpoolPath` isolate the buffer file per relay/client destination,
  so reprovisioning to a different relay (the deep-link flow above) can
  never flush old buffered samples under new credentials. A pre-existing
  buffer file from before this scoping existed is quarantined once
  (renamed to `<path>.legacy-unknown-destination`, never deleted) the
  first time `buildTelemetryConfig` runs after upgrading.
- The app now enforces its already-documented foreground-only design
  (see "Known gaps" below): `StatusScreen` stops the session via
  `WidgetsBindingObserver` when the app is backgrounded, rather than only
  documenting that as out of scope.
- `stop()` cancels both loops promptly and does **not** wait for the spool
  to fully drain (no CLI-style `--drain-timeout` equivalent) — a
  deliberate difference from the Go CLI: unlike its bounded `--count`
  runs, a mobile session's stop is user- or backgrounding-driven with no
  natural finite endpoint to wait against, and anything undelivered stays
  safely spooled for the next session, matching this app's existing
  fire-and-forget-across-sessions design.
- The old `UploadSample` use case is gone (superseded by
  `TelemetryUploadService.enqueue`); `ITelemetryRepository.send`/
  `flushBuffer` remain as unused-but-tested low-level primitives, mirroring
  the Go side keeping `Uploader.Send`/`FlushBuffer` unchanged.

## Architecture

Clean architecture, three layers:

- **`lib/domain/`** — `repositories/` (abstract interfaces only:
  `IVehicleRepository`, `ITelemetryRepository`, `IProvisioningRepository`,
  `IDeepLinkRepository`) and `usecases/` (one class per action:
  `ConnectToVehicle`, `ReadLiveSample`, `NegotiateTelemetry`,
  `SaveProvisioning`, `LoadProvisioning`, `ParseProvisioningLink`,
  `ListenForDeepLinks`, `DisconnectFromVehicle`).
- **`lib/data/`** — `models/` (plain data classes), `datasources/`
  (interface + `...Impl` pairs doing actual I/O: sockets, HTTP, files,
  secure storage), `repositories/` (interface implementations composing
  one or more data sources).
- **`lib/core/telemetry/`** — `ITelemetryUploadService`/
  `TelemetryUploadServiceImpl`, `AcquisitionQueue`, `destinationId`/
  `resolveSpoolPath`: the Phase 3b acquisition/spool/upload pipeline (see
  above), sitting alongside but independent of the `domain`/`data`
  repository layers it drives.
- **`lib/presentation/`** — `cubits/` (flutter_bloc `Cubit`s calling use
  cases, exposing `Equatable` state classes) and `screens/` (the two v0
  screens: connect, status).
- **`lib/doip/`** — the low-level DoIP wire-protocol codec (header
  pack/parse, constants) — pure functions/data, no I/O, used internally by
  `data/datasources/doip_data_source.dart`.
- **`lib/core/di/service_locator.dart`** — the only place any `...Impl`
  class is referenced outside its own file and its own tests; everywhere
  else resolves dependencies as `sl<ISomething>()` (GetIt).

## First-time setup

This repo doesn't include `android/`/`ios/` platform folders — those are
ordinary `flutter create` output and are more reliably generated by the
tool itself than hand-written blind. From the repository root:

```sh
flutter create --platforms=android,ios --org com.freebeamer .
flutter pub get
```

Then add the manifest entries `flutter create` doesn't add by default:

- **Android** (`android/app/src/main/AndroidManifest.xml`): add
  `<uses-permission android:name="android.permission.INTERNET"/>` (not
  included by default, needed for the telemetry uploader) and
  `<uses-permission android:name="android.permission.CAMERA"/>` (needed
  for QR-code provisioning scanning, `mobile_scanner`). Also add a
  `VIEW`/`BROWSABLE` intent-filter on `MainActivity` for the
  `freebeamer://connect` scheme (see "Provisioning" below).
- **iOS** (`ios/Runner/Info.plist`): add an `NSCameraUsageDescription` key
  (e.g. "Used to scan a FreeBeamer relay provisioning QR code") and a
  `CFBundleURLTypes` entry registering the `freebeamer` URL scheme.

## Provisioning: one deep link, tapped or scanned

`freebeamer-relay client add --public-url https://<relay-domain>` prints a
`freebeamer://connect?relay_url=...&api_key=...` link alongside the raw API
key. That one link is the entire provisioning story:

- **Tapped** (SMS, email, a webpage — the real customer flow): the OS
  routes it straight to the app via the `VIEW`/`BROWSABLE` intent-filter
  (Android) / `CFBundleURLTypes` (iOS); `DeepLinkListener`
  (`lib/presentation/widgets/deep_link_listener.dart`) parses it, saves
  the relay URL/API key, and navigates straight to `StatusScreen` —
  streaming starts with no manual entry at all.
- **Scanned**: the same string, delivered by camera instead of a tap —
  `ConnectScreen`'s "Scan provisioning QR code" button feeds the scanned
  text through the identical `ParseProvisioningLink` use case.
- **Manual entry** on `ConnectScreen` still exists as a fallback (typing
  a relay URL/API key by hand, or a raw `am start -d '...'` intent while
  testing without a QR image — see below).

`freebeamer://` is a **custom URI scheme, not a verified Android App
Link / iOS Universal Link** — it works today without a live domain, but
unlike a real `https://` link it isn't auto-linkified by every SMS/email/
messaging client. Use your own relay hostname. When deploying a verified HTTPS provisioning domain, the intended
upgrade is switching the scheme in `ProvisioningPayload` to
`https://<domain>/connect` (same query parameters) plus the platform
verification files (`.well-known/assetlinks.json` /
`apple-app-site-association`) hosted there — everything else (parsing,
the listener, the use case) stays the same.

**Testing the deep link without a QR image**: trigger it directly via
adb — note the required quoting, since `adb shell`'s argument
reconstruction lets the *device's* shell interpret an unescaped `&` as a
job-control operator and silently truncates the URL at the first one:

```sh
LINK='freebeamer://connect?relay_url=http%3A%2F%2F10.0.2.2%3A8091%2Fv1%2Ftelemetry&api_key=fh_live_...&host=10.0.2.2&port=13400'
adb shell "am start -a android.intent.action.VIEW -d '$LINK'"
```

(`host`/`port` are optional overrides for the adapter address — useful
for pointing at a mock adapter during testing; a real customer's link
omits them and the app defaults to MHD's own standard
`192.168.4.1:13400`.)

## Running the test suite

```sh
flutter test
```

`test/data/datasources/mhd_data_source_test.dart` decodes a crafted 38-byte
monitor reply using the **same raw/expected values as
`https://github.com/freebeamer/core/blob/main/pkg/mhd/livemonitor_test.go`** — if this app's `decodeMonitorReply`
and the Go reference's `DecodeMonitorReply` ever disagree, this is where
it'll show up. `test/data/datasources/doip_data_source_test.dart` runs a
mock DoIP server over a real loopback TCP socket, the same testing
approach `pkg/doip/client_test.go` uses.

## Trying it against the existing mock adapter/relay scripts

The same throwaway mock-DoIP-adapter Go program used to smoke-test the
Go CLI this session (`freebeamer mhd monitor`) works here too — point this
app's "Adapter IP" field at wherever that mock server is listening (e.g.
your machine's LAN IP if testing from a physical phone, or an emulator's
host-loopback address) instead of a real MHD adapter, and a
`freebeamer-relay serve` instance for the relay URL, before ever touching
real hardware.

## Known gaps

- No real-hardware validation yet (a real MHD adapter, a real vehicle) —
  same caveat the Go side carries in `https://github.com/freebeamer/core/blob/main/docs/mhd-live-monitor-v0-plan.md`.
  The emulator run only proves the app against a mock ECU, the same one
  `freebeamer mhd monitor` was smoke-tested against.
- iOS hasn't been built or run at all (no Mac/Xcode in this environment).
- Background/headless streaming is out of scope for v0 (`wakelock_plus`
  keeps the screen on; the app must stay foregrounded during a session) —
  see the mobile app plan's "Background operation" section for why.
- The stylus/handwriting IME suggestion this particular AVD image shows
  on first text entry (unrelated to the app) can intermittently hijack
  `adb shell input text` during scripted UI testing — if you hit it,
  `adb shell settings put secure stylus_handwriting_enabled 0` or just
  dismissing it with the back button works. Not an app bug.
- `DeepLinkListener` guards against `package:app_links` delivering the
  same cold-start link through both `getInitialLink()` and `linkStream`
  (a documented quirk of the plugin, not a one-off) — without the guard,
  a cold start via deep link fired two concurrent `connect()` attempts
  against the shared `IDoipDataSource` singleton and corrupted both. If
  a future app_links upgrade changes this behavior, the dedup guard is
  harmless to keep either way.
