# Codex Sidecar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for native task-by-task execution, or superpowers:subagent-driven-development if the project owner explicitly chooses delegation. Steps use checkbox syntax for tracking.

**Goal:** Build a passive macOS companion with correct observed completed-response
accounting, shared manual chat selection in a menu-bar panel and companion window,
and independent source-backed account quotas.

**Architecture:** A selective rollout decoder feeds a pure owned-ledger reducer.
Incremental read-only file providers and a separately owned stdio quota provider
publish immutable presentation snapshots to one shared store for two native
surfaces. No database or
transcript retention is required.

**Tech Stack:** Swift 6, macOS 14+, SwiftUI, Foundation, XCTest, SwiftPM; no
third-party runtime dependencies.

**Spec:** [SPEC.md](SPEC.md), dated 2026-10-07.

Status: **Stages 1–5 implemented; Stage 6 validation/documentation performed, native UI acceptance incomplete**, with dated evidence and unresolved gates in
[docs/validation.md](docs/validation.md). Stage 6 has no release/publication
authorization. A plan checkbox is not proof of full application acceptance.

The owner approved macOS-first delivery and Swift/SwiftUI on 2026-10-07.
Windows is a possible later phase, not a first-release deliverable. This updated
plan includes the discussed menu-bar panel and chat selection in both surfaces.

## Global constraints

- All repository documentation, product UI, code names/comments, tests, and public artifacts are in English.
- Collaboration with the project owner is in Russian.
- Swift 6, macOS 14+, SwiftUI, Foundation, XCTest, SwiftPM; no third-party runtime dependencies and no database.
- Source files and Codex configuration remain read-only; no copied credentials.
- Count unique owned completed responses, not user messages/tasks/tools/snapshots.
- Preserve missing values; cached input and reasoning are subsets, not additive costs.
- Exact current context is unavailable for the validated metrics-only profile.
- Manual session selection is reliable; recent-activity suggestions are heuristic.
- The menu-bar panel and companion window share selection, one reader and one quota provider; closing a surface does not quit the app.
- Windows/Linux, autostart and custom Dock visibility behavior are outside MVP.
- Follow `AGENTS.md`: start each requested stage on its named branch from current `main`; create later branches only after prerequisites are accepted and merged. Local Conventional Commits are allowed; push/merge/publication require separate owner instructions.
- No inference, thread modifications, login/logout, reset redemption, private quota HTTP, telemetry, or publication.
- Quota polling: 60 seconds; stale threshold: 120 seconds; request timeout: 20 seconds; retry delays: 60, 120, 300 seconds capped at 300.
- Selected-file stat fallback: 1 second; directory reconciliation: 5 seconds.
- Read chunk: at most 64 KiB; maximum buffered line: 8 MiB; visible request rows: at most 100 with earlier rows loadable.
- Appended record visibility target: 2 seconds; new-session discovery target: 6 seconds at idle host load.

## Review focus

The following realistic failures must be pinned by the owning stage's tests:

1. Old/foreign history in a selected file must not become that thread's own usage
   (stage 2 ownership and positive-baseline cases).
2. A newer child/concurrent chat must not steal a manually selected root session
   (stage 3 pinned-selection case).
3. Missing usage breakdown must not yield a complete-looking cache rate, and
   configured model must not become actual-model attribution (stages 1, 2 and 5).
4. An old quota reply arriving after account change must not overwrite current
   account limits (stage 4 generation and single-flight cases).
5. A large transcript-bearing or malformed record must not freeze the UI or appear
   in diagnostics (stages 1, 3 and 6 size/privacy cases).

## Proposed file map and module boundaries

These paths are planned, not existing application files. Keep units small and
avoid allowing views to perform arithmetic or read raw logs.

| Path | Responsibility |
| --- | --- |
| `Package.swift` | Library `SidecarCore`, executable `CodexSidecar`, tests; Swift 6, macOS 14, no remote dependencies |
| `Sources/SidecarCore/Metrics.swift` | Optional counter fields, availability/provenance, identity and normalized event types |
| `Sources/SidecarCore/RolloutDecoder.swift` | Selectively decode one complete JSONL record and discard transcript fields |
| `Sources/SidecarCore/SessionReducer.swift` | Own response dedupe, conflict quarantine, totals/task grouping |
| `Sources/SidecarCore/Reconciliation.swift` | Native baselines/epochs and conservative legacy snapshots |
| `Sources/SidecarCore/ToolAssociator.swift` | Call identity/status and order-based association/ambiguity |
| `Sources/SidecarCore/ContextState.swift` | Source window/configured model/last footprint; unavailable exact occupancy |
| `Sources/SidecarCore/LineFramer.swift` | Bounded byte framing, partial/oversized/UTF-8 behavior |
| `Sources/SidecarCore/SessionCatalog.swift` | Root resolution, safe file enumeration, minimal descriptors |
| `Sources/SidecarCore/SessionReader.swift` | Incremental selected-file reading/rebuild and immutable snapshots |
| `Sources/SidecarCore/SessionSelection.swift` | Manual pinning and visibly heuristic recent-root suggestion |
| `Sources/SidecarCore/QuotaModels.swift` | Buckets/windows, independent freshness/error state |
| `Sources/SidecarCore/QuotaRPC.swift` | Allowlisted stdio protocol, request correlation/timeouts/process lifecycle |
| `Sources/SidecarCore/QuotaProvider.swift` | Capability/account generation, single-flight refresh/backoff/offline |
| `Sources/CodexSidecar/SidecarApp.swift` | MenuBarExtra, companion and Settings scenes, shared store and app lifecycle |
| `Sources/CodexSidecar/SidecarStore.swift` | Main-actor immutable presentation state and commands |
| `Sources/CodexSidecar/CompanionView.swift` | Session/limits/context/totals/request detail UI |
| `Sources/CodexSidecar/MenuBarView.swift` | Compact account/session summary, chat selection, Open window, Refresh, Settings and Quit |
| `Sources/CodexSidecar/SettingsView.swift` | Local root/executable overrides, offline mode and selection settings |
| `scripts/package-app.sh` | Local `.app` bundle from release executable; no install/autostart/signing/upload |
| `Resources/Info.plist` | English app identity and declared minimum OS |
| `Tests/SidecarCoreTests/Fixtures/` | Entirely synthetic JSONL/RPC fixtures; no real captures |
| `Tests/SidecarCoreTests/Fixture.swift` | Resource loading and synthetic identities, not production code |
| `Tests/SidecarCoreTests/*Tests.swift` | Focused parser/reducer/reader/provider tests described below |
| `docs/validation.md` | Dated numeric acceptance, capability gaps, privacy and platform results |

Normalized types to define in stage 1:

- `TokenUsage`: optional `Int64` fields `input`, `cachedInput`, `cacheWriteInput`,
  `output`, `reasoning`, `total`; checked validity and sum operations.
- `SourcePosition`: logical file identity and byte offset, never raw text.
- `RequestKey`: `threadID: String`, `responseID: String`.
- `UsageRecord`: key, `runtimeSessionID`, `taskID`, `rootTaskID`, timestamp, usage,
  task cumulative, thread cumulative, source position.
- `MetricEvent`: `.header`, `.taskStarted`, `.taskFinished`, `.taskInterrupted`,
  `.configuredModel`, `.usageRecord`, `.usageSnapshot`, `.toolCall`, `.toolOutput`,
  `.checkpoint`, `.unknown`; associated values contain only allowlisted metadata.
- `SanitizedDiagnostic`: stable category, optional line/offset, occurrence count.
- `DecodeResult`: optional normalized event and diagnostics, without raw bytes.

Stage 2 defines `DerivedSession`: `requests`, `tasks`, optional-field `totals`,
`cacheHitPercent: Double?`, reconciliation state/reported cumulative, configured
model/window/last-footprint state, unattributed tools, diagnostics. Its
`ObservedRequest` exposes key, usage, task, timestamp, `tools` and model provenance.
All types crossing workers must be Sendable value snapshots.

## Stage 1 — Synthetic fixtures and selective parser correctness

**Deliverable:** A buildable/testable core package with no UI or live provider;
selective decoder with explicit availability and validation.

**Files:** Create `Package.swift`, `Metrics.swift`, `RolloutDecoder.swift`,
`Fixture.swift`, `RolloutDecoderTests.swift`, `TokenUsageTests.swift`, and fixture
resources in the file map above. Do not create a UI target implementation yet.

**Interfaces:**

```swift
// SidecarCore
func decodeLine(_ bytes: Data, at: SourcePosition) -> DecodeResult
// RolloutDecoder method; only newline-complete bytes are passed here.

// Test-only helper, using Bundle.module resources.
static func lines(_ name: String) throws -> [Data] // Fixture.lines
static let threadID: String // invented owning UUID in Fixture
```

Define a decoder type `RolloutDecoder` exposing the shown `decodeLine` method.
SourcePosition's initializer is `init(fileID: String, byteOffset: Int64)`.
Fixture names below are extensionless arguments referring to `.jsonl` resources.

- [x] **Step 1: Confirm the build gate.** Check `swift --version` and
  `xcrun --show-sdk-path`; record versions only. Create a Swift 6 library/test
  package with `.macOS(.v14)`, library/test targets only at this stage, and
  `.process("Fixtures")` resources. No remote dependencies. If the installed SDK
  cannot compile a core test, stop and report the precise build gate before UI
  work; do not silently install Xcode or change stack.
- [x] **Step 2: Write synthetic cases before decoder implementation.** Add
  `native-two-requests.jsonl` using the invented identities/numbers in SPEC §9,
  with a header, one task, configured model `example-model`, a tool call, two
  native records and mirrored snapshots. Add `unknown-and-sensitive.jsonl`
  containing invented message/arguments/output marker `PRIVATE_MARKER`, unknown
  events and fields, plus a native usage record with that marker in an ignored
  extra field and the same invented 120-token usage as the first native record. Add `malformed.jsonl` with a bad complete JSON line followed
  by a valid record. Never transform a real local log into a fixture.
- [x] **Step 3: Pin tests for counters and discard behavior.** Example assertions:

```swift
func testSelectiveDecoderKeepsUsageAndDropsText() throws {
    let decoder = RolloutDecoder()
    let line = try Fixture.lines("unknown-and-sensitive").first {
        String(decoding: $0, as: UTF8.self).contains("token_usage_record")
    }!
    XCTAssertTrue(String(decoding: line, as: UTF8.self).contains("PRIVATE_MARKER"))
    let result = decoder.decodeLine(
        line, at: SourcePosition(fileID: "fixture", byteOffset: 0))
    guard case .usageRecord(let record) = result.event else {
        return XCTFail("Expected native usage")
    }
    XCTAssertEqual(record.usage.total, 120)
    XCTAssertEqual(record.usage.cachedInput, 60)
    XCTAssertEqual(record.usage.reasoning, 5)
    XCTAssertFalse(String(describing: result).contains("PRIVATE_MARKER"))
}
```

  Add `usage-missing-fields.jsonl`, `usage-invalid.jsonl` and tests for null vs
  explicit zero, input/output missing with valid total, cached > input,
  reasoning > output, negative values, non-integral counters, contradictory total,
  Int64 overflow, absent required request IDs and unsupported envelopes. Invalid
  arithmetic yields a sanitized category; missing breakdown remains optional.
- [x] **Step 4: Run `swift test --filter RolloutDecoderTests` and
  `swift test --filter TokenUsageTests`.** Record expected failure from missing
  decoder/validation, then implement minimal selective Decodable structures.
  Decode payloads by envelope/type; never keep a generic raw JSON tree as
  normalized state. Normalize schema variants only when tested. Re-run both
  filters and the full `swift test`; all must pass before stage 2.
- [x] **Step 5: Review the public fixture boundary.** Search fixtures for private
  paths/identities/text, confirm every value was authored synthetically, and list
  the validated native profile in `docs/validation.md`. Suggested local commit
  if a Git repository has been authorized/initialized: `test: establish synthetic
  rollout schema and accounting primitives`. No push.

**Acceptance:** A2 subset/availability basics, A10 malformed/unknown-event privacy;
core builds with installed tools. No request reconstruction inferred yet.

## Stage 2 — Model requests and derived session state

**Deliverable:** Pure deterministic replay of metrics into owned completed
requests, task grouping, tools, reconciliation and honest context state.

**Files:** Create `SessionReducer.swift`, `Reconciliation.swift`,
`ToolAssociator.swift`, `ContextState.swift`, `SessionReducerTests.swift`,
`ReconciliationTests.swift`, `ToolAssociatorTests.swift`, `ContextStateTests.swift`.
Extend fixtures; extend `Fixture` with `events(_ name: String) throws -> [MetricEvent]`
using stage 1 decoding, failing on unexpected fixture diagnostics.

**Interfaces:**

```swift
struct SessionReducer {
    static func reduce(_ events: [MetricEvent], owningThreadID: String)
        -> DerivedSession
}
// ToolAssociator, ContextState and Reconciliation are pure internal reducers.
// DerivedSession and ObservedRequest match the file-map contract above.
```

- [x] **Step 1: Write failing dedupe/accounting tests.** Core example:

```swift
func testNativeRequestsStayDistinctFromTaskAndSnapshots() throws {
    let events = try Fixture.events("native-two-requests")
    let state = SessionReducer.reduce(events, owningThreadID: Fixture.threadID)
    XCTAssertEqual(state.requests.count, 2)
    XCTAssertEqual(state.tasks.count, 1)
    XCTAssertEqual(state.totals.total, 180)
    XCTAssertEqual(state.totals.input, 150)
    XCTAssertEqual(state.totals.cachedInput, 100)
    XCTAssertEqual(state.totals.output, 30)
    XCTAssertEqual(state.totals.reasoning, 7)
    XCTAssertEqual(try XCTUnwrap(state.cacheHitPercent), 66.6666667,
                   accuracy: 0.0001)
    let replay = SessionReducer.reduce(events + events,
                                       owningThreadID: Fixture.threadID)
    XCTAssertEqual(replay.requests.count, 2)
    XCTAssertEqual(replay.totals.total, 180)
}
```

  Add `equal-values-distinct-ids`, `conflicting-response-id`, `foreign-history`,
  `native-zero-usage`, `partial-native-usage`, and `missing-task-start` fixtures.
  Conflicting ID must quarantine that request and degrade reconciliation; a
  missing task start creates an incomplete task group without discarding valid
  owned response usage. Equal-valued IDs must both count.
- [x] **Step 2: Write failing epoch/coverage tests.** Add `positive-baseline`
  (first request 120, reported cumulative 620 → observed 120, earlier baseline
  500, partial history), `native-counter-reset`, `legacy-only`,
  `legacy-to-native`, `resume-replay`, `compaction-checkpoint`, and
  `context-full-snapshot`. Assert that the legacy/full-window/checkpoint values
  never create a native row, native sums do not reset at compaction, a counter
  decrease invalidates continuity, and source-reported total remains separate.
  Replaying the same checkpoint must not change observed totals.
- [x] **Step 3: Write failing tool/context tests.** Add `tools-ordered`,
  `tools-orphaned`, `tools-late-output`, `tools-task-boundary`, `tools-concurrent`,
  `model-window-change`, and `interrupted-no-usage`. Use invented call IDs; same
  call in response_item/item_completed counts once. A late output updates its
  existing call; a cross-task/orphan ambiguous call stays unattributed. Assert
  `functions.exec` remains one tool, even when its ignored synthetic input text
  mentions several reads. Exact current occupancy is unavailable throughout;
  a model change without window must not reuse the prior window.
- [x] **Step 4: Run the four named test classes and observe failures.** Implement
  owned-key dictionary reduction, conflict quarantine/retraction, checked sums,
  optional-field aggregate propagation, continuous-epoch reconciliation, and
  order-segment tool association. Use native record boundaries only for request
  rows; configured model is a labeled task context. Re-run `swift test` until
  stage scenarios pass. Do not “fix” missing fixtures by inserting zero values.
- [x] **Step 5: Review invariant coverage and record results.** Verify A2–A7
  explicitly in `docs/validation.md`. Suggested local commit:
  `feat: reconstruct owned completed model requests`.

**Acceptance:** Source snapshots never inflate totals; replay is deterministic;
strictly observed usage and incomplete history remain distinct. Accounting must
pass before any UI work.

## Stage 3 — Incremental reading, discovery and selection

**Deliverable:** Read-only live session provider whose restart/replacement replay
matches stage 2; manual pinning with heuristic suggestions.

**Files:** Create `LineFramer.swift`, `SessionCatalog.swift`, `SessionReader.swift`,
`SessionSelection.swift`, `LineFramerTests.swift`, `SessionCatalogTests.swift`,
`SessionReaderTests.swift`, `SessionSelectionTests.swift`.

**Interfaces:**

```swift
struct LineFramer {
    mutating func append(_ bytes: Data) -> [Data] // newline-complete bounded lines
    mutating func reset()
}
struct SessionDescriptor: Sendable {
    let id: String
    let sourceURLs: [URL]
    let projectName: String?
    let cliVersion: String?
    let lastActivity: Date?
    let parentThreadID: String?
}
actor SessionCatalog {
    func discover(root: URL) async -> [SessionDescriptor]
}
actor SessionReader {
    func select(_ session: SessionDescriptor) async
    func refresh() async
    func snapshots() -> AsyncStream<DerivedSession>
    func stop() async
}
// Selection state holds pinned ID separately from mostRecentSuggestion.
```

  LineFramer additionally exposes sanitized oversized-line diagnostics. Session
  descriptors retain local URLs for reads only, not diagnostic/log export.

- [x] **Step 1: Write byte-framing tests.** Split a synthetic record at every
  byte offset and split a multibyte UTF-8 character; assert one identical decode
  after newline. Test CRLF, multiple complete lines, empty lines, incomplete EOF,
  malformed complete line followed by valid data, and >8 MiB line dropped to
  newline with bounded buffering. Use generated synthetic data for oversized
  cases rather than committing megabytes of fixtures.
- [x] **Step 2: Write temporary-directory discovery tests.** Use test-owned
  directories for explicit root/env/default precedence, archived directory
  absent/present, unreadable root, symlink escape, duplicate headers/files,
  child/root provenance, and newest-child vs root ordering. No test reads the
  real home. Assert an existing pinned root remains selected when a newer child
  or concurrent root appears. Equal recent timestamps do not pretend foreground
  identity. Rename a source from sessions to archive and discover one session.
- [x] **Step 3: Write incremental/rebuild tests.** Example:

```swift
func testChunkedReadEqualsWholeReplay() throws {
    let lines = try Fixture.lines("native-two-requests")
    let bytes = lines.reduce(into: Data()) { data, line in
        data.append(line); data.append(0x0A)
    }
    var framer = LineFramer()
    var decoded: [MetricEvent] = []
    let decoder = RolloutDecoder()
    for byte in bytes {
        for line in framer.append(Data([byte])) {
            if let event = decoder.decodeLine(line,
                at: SourcePosition(fileID: "fixture", byteOffset: 0)).event {
                decoded.append(event)
            }
        }
    }
    let state = SessionReducer.reduce(decoded, owningThreadID: Fixture.threadID)
    XCTAssertEqual(state.requests.count, 2)
    XCTAssertEqual(state.totals.total, 180)
}
```

  Add filesystem tests for append, partial newline completion, truncation,
  replacement with equal size, missed watcher signal caught by stat fallback,
  deletion while selected, archive move, duplicate file, restart rebuild and
  selection switch while a read is pending. Obsolete selected-session updates
  must never appear in the new selection.
- [x] **Step 4: Run these tests and observe failures, then implement.** Open source
  handles read-only, frame before decoding, and read ≤64 KiB chunks off UI actor.
  Maintain file identity/offset/buffer and sanitized diagnostics. Watchers are
  hints; 1-second selected-file stat and 5-second catalog reconciliation recover
  missed signals. For replacement/truncation rebuild the affected contribution
  from current originals and re-derive; never add old and replacement totals.
  Discard an asynchronous result if selection generation changed.
- [x] **Step 5: Run `swift test` and synthetic latency check.** Generate 10,000
  owned request records in a temporary file; measure parse/replay and bounded
  append detection with injected timers or an explicit integration harness.
  Confirm 2-second append and 6-second discovery targets on idle test host,
  responsive worker cancellation, and no main-thread scan. Record host/limits in
  validation; do not claim a benchmark on every platform. Suggested commit:
  `feat: follow selected rollout files incrementally`.

**Acceptance:** A1, A3, A10, A11; selected-session ownership, replay and privacy
invariants remain intact through filesystem changes.

## Stage 4 — Separate quota provider and availability states

**Deliverable:** An allowlisted quota client with deterministic state-machine
coverage, no direct auth/private HTTP code, and a passive installed-profile check.

**Files:** Create `QuotaModels.swift`, `QuotaRPC.swift`, `QuotaProvider.swift`,
`QuotaModelsTests.swift`, `QuotaRPCTests.swift`, `QuotaProviderTests.swift`;
synthetic JSON RPC resources `weekly-only.json`, `multiple-buckets.json`,
`legacy-null-map.json`, `empty-map.json`, `malformed-quota.json`.

**Interfaces:**

```swift
protocol QuotaTransport: Sendable {
    func request(method: String, params: Data?) async throws -> Data
    func notifications() -> AsyncStream<Data>
    func stop() async
}
struct QuotaDecoder {
    static func decodeRead(_ bytes: Data, receivedAt: Date) throws -> QuotaSnapshot
}
actor QuotaProvider {
    func refresh(now: Date) async
    func setOffline(_ enabled: Bool) async
    func accountChanged() async
    func snapshots() -> AsyncStream<QuotaState>
    func stop() async
}
```

  Define `QuotaSnapshot.buckets`, `QuotaBucket.windows`,
  `QuotaWindow.durationMinutes: Int64?`, `usedPercent: Double?`,
  `remainingPercent: Double?`, `resetAt: Date?`, `label: String`, source slot and
  identity. `QuotaState` represents loading/available/unavailable/stale/error,
  retains last receipt time and sanitized reason. Inject transport and a
  controllable scheduler into provider construction for tests; no live sleeps.

- [x] **Step 1: Write failing mapping tests.** Weekly-only synthetic fixture has
  used 25, duration 10080, reset 1800000000; it must show 75% remaining and no 5h.

```swift
func testWeeklyPrimaryDoesNotBecomeFiveHours() throws {
    let raw = try Fixture.data("weekly-only", ext: "json")
    let snapshot = try QuotaDecoder.decodeRead(raw,
        receivedAt: Date(timeIntervalSince1970: 1799999000))
    let bucket = try XCTUnwrap(snapshot.buckets.first)
    let window = try XCTUnwrap(bucket.windows.first)
    XCTAssertEqual(window.label, "Weekly")
    XCTAssertEqual(window.durationMinutes, 10080)
    XCTAssertEqual(window.remainingPercent, 75)
    XCTAssertEqual(window.resetAt, Date(timeIntervalSince1970: 1800000000))
    XCTAssertFalse(bucket.windows.contains { $0.durationMinutes == 300 })
}
```

  Add `Fixture.data(_ name: String, ext: String) throws -> Data` resource
  loading. Test map precedence including empty map;
  null/absent fallback; unknown/null durations; null percentage/reset;
  out-of-range percentages; duplicate-duration slots; multiple buckets with
  independent percentages and optional `normalModelSlug`; unrecognized fields.
  Add a full two-bucket snapshot followed by a sparse one-bucket notification
  with null metadata: other buckets/metadata must survive, no unrelated freshness
  is extended, and one eligible coalesced full read follows. Only a subsequent
  full read can authoritatively remove a window/bucket. Nullable ordinary permission
  must not be inferred from percent.
- [x] **Step 2: Write failing provider tests using fake transport/scheduler.**
  Test single-flight overlap, interleaved notification/response IDs, missing
  executable, init failure, auth missing/API key, timeout at 20 seconds, process
  death, malformed JSON, 120-second freshness expiry, transient retained-good
  state, retry schedule 60/120/300, manual refresh, wake and past reset.
  Start a fake pending read, change account generation, complete old read and
  assert old values never publish. Clear values on auth loss. Offline must stop
  the child and issue zero transport/network requests; a later enable refreshes.
- [x] **Step 3: Write transport allowlist/privacy tests.** Assert exactly the
  permitted initialize/initialized/account-read/rate-limits operations and no
  turn, thread resume, auth-token export, logout/reset, or approval actions.
  Unknown server requests get a sanitized unsupported response. Fake stderr
  containing `PRIVATE_MARKER` must never reach diagnostics. Fill stdout/stderr
  pipes concurrently and confirm they drain; cancel/exit closes only the owned
  process. Request protocol does not go through a shell or a public socket.
- [x] **Step 4: Run quota test classes, observe failures, implement minimal RPC
  and state reducer, then re-run `swift test`.** Use matching installed initialize
  capabilities, use `excludeResetCreditDetails: true` for background reads and
  omit `supportsLunaReserve`, disable analytics by child-only override, explicitly select root
  and executable. Handle account identity/fingerprint only transiently; invalidate
  account generation before publishing old replies. With identity unavailable,
  do not claim confirmed historical-session/account matching or carry values
  across a known account change. Distinct RPC errors map to sanitized categories.
- [x] **Step 5: Perform one bounded live capability check.** `codex --version`,
  generate schema to temporary storage, then initialize the provider and read
  account/quotas without model requests or chat mutations. Record version,
  bucket/window presence, and success/unavailable outcome only. Missing 5h is
  expected behavior, not a failure. Notification schema support is not proof of
  cross-process delivery; polling stays enabled. Suggested commit:
  `feat: read account quotas through isolated app-server`.

**Acceptance:** A8–A9. Network/auth absence never breaks local parsing. No reset,
forecast, direct credential, or model-window activation code is present.

## Stage 5 — Minimal companion UI and real-time state

**Deliverable:** A native macOS menu-bar panel and one companion window sharing
already-tested providers and chat selection, with honest scope/freshness labels
and usable local settings.

**Files:** Add executable target to `Package.swift`; create `SidecarApp.swift`,
`SidecarStore.swift`, `CompanionView.swift`, `MenuBarView.swift`, `SettingsView.swift`,
`Resources/Info.plist`, `scripts/package-app.sh`, and `PresentationStateTests.swift`.
Keep presentation mapping testable in core if it has logic; UI-only styling does
not require redundant implementation-mirroring tests.

**Interfaces:**

```swift
@MainActor
final class SidecarStore: ObservableObject {
    // Published immutable session/catalog/quota presentation snapshots.
    func selectSession(id: String) async
    func refreshQuotas() async
    func setOffline(_ enabled: Bool) async
    func stop() async
}
```

  Construction receives catalog, reader, provider and local settings. The store
  owns subscriptions/cancellation; views issue these commands only. Use one
  SwiftUI Window scene for the companion, `MenuBarExtra` with `.window` style,
  and a separate Settings scene, all using the same app-level store. Open window
  uses `openWindow` with the companion scene's stable ID; never create a second
  provider when a scene becomes visible. Closing a window leaves the menu-bar
  app running; explicit Quit performs store shutdown and application termination.

- [x] **Step 1: Pin meaningful presentation cases before integration.** Feed
  synthetic DerivedSession/QuotaState snapshots for partial history, missing
  cache rate, weekly-only quota, stale/error retained values, unknown duration,
  interruption, no root/logs, configured-model-only state and unavailable exact
  current context. Assert presentation text includes the correct scope, never
  formats null as 0%, and does not call configured model “Actual model”. Keep
  English UI strings centralized enough to inspect.
  Add a shared-selection integration case with two synthetic chats: selecting B
  from either surface yields B's metrics/requests and preserves account quotas.
  Resolve a pending A read after selecting B and assert A cannot overwrite B.
  Use injected providers to assert one start per app lifetime; surface reopen
  never increments starts and explicit shutdown cancels the owned workers.
- [x] **Step 2: Implement the panel and small window.** Render SPEC §8. Keep 100
  recent rows visible with earlier-page loading; request detail shows subsets
  with “included in” labels and tool association confidence. Unattributed calls
  remain task activity. Provide manual selector, fixed selection mode label,
  source times, bucket choice, Refresh, offline mode and root/executable settings.
  Both surfaces expose Selected chat and shared scope/freshness state; the panel
  shows compact totals/cache/context availability and all returned quota windows.
  Add Open window, Refresh, Settings and explicit Quit actions to the panel.
  Use an icon-only menu-bar label, without inventing a single account-wide quota
  percentage. Use native accessibility, keyboard focus and system appearance.
  No custom charts/theme, autostart, prompt titles, or transcripts.
- [x] **Step 3: Validate SwiftUI build/packaging gate.** Run `swift test`,
  `swift build -c release`, then the local packaging script that copies only the
  release executable and Info.plist into `build/Codex Sidecar.app/Contents/`.
  Resolve the executable location via `swift build -c release --show-bin-path`.
  Package script must quote paths, write only under build, and perform no install,
  signing, quarantine removal, or upload. Verify native app launch from the
  bundle. If Command Line Tools/SDK cannot produce a launchable app, report the
  exact gate before claiming GUI completion; do not silently change toolchain.
- [ ] **Step 4: Inspect the UI with synthetic input.** Start using an explicit
  test-owned Codex root and fake quota transport. Review 380×680 default window,
  narrow/resized layouts, long tool/model labels, empty states, number selection,
  keyboard selection and accessibility labels. Inspect the compact menu-bar panel
  with weekly-only, 5h plus Weekly, multiple buckets and stale/unavailable data.
  Switch chats in both surfaces and check matching metrics/requests. Open window
  must focus/reuse the existing window and preserve the selection. Capture only synthetic screenshots
  if needed. Verify appending records updates the selected view within the target;
  toggling offline stops quota work while local updates continue.
- [ ] **Step 5: Check lifecycle.** Rapidly switch synthetic sessions, wake/refresh,
  dismiss/reopen the panel, close/reopen the companion, and explicitly quit;
  panel dismissal and window closure preserve selection and scheduled updates,
  while Quit stops workers. No obsolete state, duplicate reader, orphan owned child,
  or modified source file remains. Record packaging/deployment-floor evidence and
  any older macOS/Intel testing gap. Suggested commit:
  `feat: show shared chat usage in menu bar and companion`.

**Stage 5 evidence boundary:** Steps 4–5 remain open for native interactive
acceptance: the computer-use native pipe was unavailable. Deterministic lifecycle
and selection checks, release packaging and explicitly synthetic native process
launch passed. Layout, accessibility, focus/reuse and GUI Quit are not verified.
See the validation record, including the unintended default-root launch incident.

**Acceptance:** A1, A5–A9, A11, A13; UI remains accurate with unavailable metrics and
real-time events. macOS 14 support is a declared floor until tested on that OS.

## Stage 6 — Installed-version validation and public-repository hygiene

**Deliverable:** Dated acceptance report, documented compatibility/privacy limits,
and a reviewable local project. No release/push/deployment.

**Files:** Update `docs/validation.md`, `README.md`, `docs/research.md`, and
`.gitignore` only if build artifacts require additional exclusions. If the owner
has selected a license, create `LICENSE` with that exact choice; otherwise mark
publication as gated rather than inventing a license.

- [x] **Step 1: Run final deterministic checks once after final changes.**
  `swift test` and `swift build -c release` must succeed. Verify all A1–A13
  acceptance rows against owning stage/test evidence. Repeat only for new changes,
  failures or unresolved gaps; never substitute screenshots for accounting tests.
- [x] **Step 2: Bounded real read-only acceptance.** Manually select an existing
  local session with native records and compare derived unique owned sums,
  breakdown and cache rate against a selective numeric inspection in memory.
  Record only equality/difference and version, not private paths/IDs/totals/raw
  transcript captures. Observe naturally appended completed responses if present;
  do not start inference to generate validation data. If no new response occurs,
  mark live-append acceptance unverified and rely on synthetic append tests.
- [x] **Step 3: Verify passive quota behavior.** Read current quotas once, compare
  supported field/window interpretation to source result, and confirm absent
  windows stay absent. Do not trigger auth loss/reset/account changes on a real
  account; those are fake-transport tests. Document that loaded desktop thread
  detection and exact current context remain unsupported.
- [x] **Step 4: Inspect public hygiene.** Enumerate all project files. Scan text
  for real home paths, bearer/API tokens, auth payloads, raw prompts/tool arguments,
  account/session IDs and exported logs. Review matches manually; synthetic marker
  strings and invented fixture IDs are allowed. Confirm lockfiles are tracked if
  dependencies ever exist, real JSONL captures are absent, build outputs ignored,
  all docs/UI/code are English, and no downloaded upstream source was vendored.
  Check selected local log fingerprints before/after Sidecar reads to establish
  read-only behavior without treating concurrently appended Codex logs as tampering.
- [x] **Step 5: Document evidence and stop.** `docs/validation.md` must separate
  passing synthetic tests, passing live checks, unverified platform/notification
  cases, unsupported metrics, and any blockers. README documents build/run,
  selection, offline/network behavior, compatibility profile and known limits.
  Present the result and local diffs. Suggested commit:
  `docs: record installed-profile acceptance and privacy limits`.
  Publication/license/signing/notarization/push remain separate owner actions.

**Execution evidence (2026-10-08):** bounded native attempt, real numeric
comparison, one fresh passive quota full read, hygiene review, tests/build/package
and documentation are recorded in docs/validation.md. Native interaction and
completed-response live append remain unverified; checked steps denote the
authorized validation work, not closure of those acceptance gaps.

**Acceptance:** A12 and all cross-stage invariants. An unverified exact-context or
foreground-follow feature is not “completed” by substituting a guess.

## Requirement coverage and stop conditions

| Specification area | Owning stages |
| --- | --- |
| Definitions, data availability and compatibility | 1, 2, 4, 6 |
| Native ownership/dedup/subsets/reconciliation/legacy fallback | 1, 2 |
| Tool order/ambiguity, interruption and configured-model provenance | 2, 5 |
| Context unavailability and source window freshness | 2, 5 |
| Roots/executable resolution, discovery, incremental reading/manual selection | 3, 4, 5 |
| Quota maps/windows/auth/freshness/account generation/offline | 4, 5 |
| Minimal UI, settings/privacy/lifecycle | 3, 4, 5, 6 |
| Shared chat selection, menu-bar/window state and shutdown | 3, 5, 6 |
| Synthetic tests/live numeric validation/public hygiene/platform gates | 1–6 |

Stop dependent work if ownership/schema or accounting invariants cannot be
validated, core fails to build with the declared tools, quota transport requires
unsupported auth/mutations, or native packaging cannot launch. Parser work can
continue independently while quotas are unavailable; unavailable exact context,
5h, actual-model fallback attribution and foreground detection are expected MVP
limits. Do not broaden scope to bypass a gate.

Before implementation, the owner reviews SPEC.md and this plan. Execution method
(native or explicitly delegated) can be chosen in the implementation session.
This first session has produced documents only and stops here.

## Stage 6 owner-approved selector follow-up — 2026-10-08

After owner-reported native acceptance, refine both shared selectors: root-first,
recent activity descending with stable ties; optional indexed chat names after
project, distinguishable ID fallback and duplicate-name disambiguation. Read only
bounded stored name/update metadata, never prompt-derived names. Preserve pinned
selection, metrics and account quotas. Add synthetic regressions, rebuild/package,
review and record fresh results. Brief native selector recheck remains pending;
keyboard, VoiceOver and real completed-response append gaps are retained.
