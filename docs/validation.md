# Validation record

## 2026-10-08 — Stage 4 implementation

**Latest status: Stages 1–4 implemented. Stages 5–6 have not started.**

Started `stage/4-quotas` from clean local `main` at `ef05917`, after the owner
accepted and merged Stages 1–3. The 118-test baseline passed freshly. All new test
inputs are synthetic; filesystem/process tests use test-owned temporary resources.
Existing accounting, session reading and unavailable exact current context remain
unchanged. The deferred Stage 3 reducer optimization is outside this change.

### Deliverables and interfaces

- `QuotaModels.swift`: immutable dynamic buckets and source-slot windows, optional
  names/model-alias and permission metadata, source used percentages, clamped
  remaining percentages, sanitized warnings, receipt time and account generation.
  `QuotaDecoder.decodeRead(_:receivedAt:)` prefers even an empty returned map;
  only absent/null maps permit legacy fallback. Duplicate durations keep both
  slots. Duration labels use 300/10080 minutes; other/unknown durations stay literal
  or unknown. Signed integer durations retain Int64 precision. Malformed/null
  fields never become zero; unrepresentable JSON numbers fail closed. Reset dates
  outside Foundation's useful civil range remain unknown with a warning.
- `QuotaRPC.swift`: Sendable `QuotaTransport`, injectable `QuotaScheduler`, actor
  request correlation and 20-second deadlines. Only initialize/initialized,
  account/read with refreshToken=false and account/rateLimits/read with
  excludeResetCreditDetails=true are accepted. supportsLunaReserve is omitted.
  Unexpected server requests receive a fixed unsupported-method response; IDs
  larger than 256 UTF-8 bytes fail closed instead of being reflected. No approval,
  browser, login, inference, thread or reset action exists.
- `QuotaExecutable.resolve` checks explicit selection, absolute PATH entries and
  recognized installed bundle candidates. Explicit invalid selection fails rather
  than silently selecting another executable. Version verification was performed
  in the bounded capability check below; resolution alone is not a compatibility
  certification. Process construction receives the same resolved root chosen for
  session discovery, setting child CODEX_HOME and analytics.enabled=false through
  an argument array. It does not inspect or edit configuration/credentials.
- Foundation Process owns one stdio child. Independent nonblocking stdout/stderr
  dispatch sources drain in bounded chunks; stderr is discarded. Stdout buffering
  is bounded to 64 chunks and each JSON message to 1 MiB. Input writes are
  nonblocking, at most 1 KiB each with at most 32 queued writes; macOS per-descriptor
  SIGPIPE suppression prevents a closed child pipe from terminating Sidecar.
  Cleanup closes owned pipes, cancels sources and terminates only the owned child,
  escalating to SIGKILL after a bounded one-second grace if still running.
- `QuotaProvider.swift`: actor start/refresh/wake/offline/accountChanged/stop and
  latest-only `AsyncStream<QuotaState>` subscriptions. Loading, available,
  unavailable, stale and error states retain honest optional values. Transient
  failure keeps last good values; authentication loss and known account changes
  clear values. Account identifiers are transient comparison data only, never
  snapshot/diagnostic/persistence fields.
- Start/manual/wake reads are single-flight. Automatic reads occur at 60 seconds;
  staleness is 120 seconds, with immediate wake/reset stale labels. Retries use
  60/120/300 seconds capped at 300; manual refresh bypasses backoff. Past resets
  cause one refresh hint and retain usage, never an invented recovery or tight
  loop. Sparse quota notifications change neither buckets, nullable metadata nor
  freshness/deadlines; the next eligible full read coalesces them. Polling continues.
  Account notifications invalidate account generations and coalesce a fresh read
  on the same owned process, avoiding initialization-notification restart loops.
  A sticky account hint cannot be displaced by ordinary quota hints.
- Account/process generations and transition tokens discard obsolete results and
  prevent an old awaited stop from overwriting a later enable. Offline never
  constructs a transport, clears old quotas and stops the child; local parsing
  continues independently. Last-subscriber cancellation stops owned provider
  resources; explicit stop finishes streams, including subscriptions after stop.

### Test-first and independent review evidence

The planned mapping/provider/transport test classes were authored before their
production components. Initial RED builds reported the missing new interfaces.
Behavioral RED runs then reproduced internal account-generation changes wedging
single-flight cleanup and a notification restart inheriting its cancelled listener.
Both were corrected and passed before the initial 145-test full-suite GREEN run.

An independent fresh-context reviewer examined `ef05917..5cb38f3` and reproduced
four important findings using temporary synthetic harnesses. The author reproduced
regression failures and fixed all four in one fix pass:

| Finding | RED → GREEN regression / additional integration coverage |
| --- | --- |
| Initialization account notification restarted the process repeatedly | `testStartupAccountHintDoesNotCreateProcessRestartLoop`; reuse the handshake/process and invalidate account values |
| Blocking stdin prevented stop and an oversized reflected ID caused SIGPIPE | `testOversizedServerRequestIDIsNotReflected`; nonblocking bounded writes and per-fd SIGPIPE suppression; `testNonreadingChildCannotBlockStopAndWriterIsBounded`, `testClosedChildStdinDoesNotSendSIGPIPEToHost` exercise actual owned pipes |
| Old offline completion overwrote a later enable; old values survived pending stop | `testOfflineTransitionCannotOverwriteLaterEnableWhileStopIsPending`; clear immediately and check transition generation after await |
| Quota notification displaced an account-change hint | `testAccountChangeHintSurvivesQuotaHintFlood`; preserve account priority until the next account read |

Additional behavioral RED → GREEN tests preserve large Int64 duration precision
and classify the installed schema's optional absent account as authentication
absent, clearing cached values. There are no deferred reviewer findings. Later
hardening/integration tests add coverage; no second independent review is claimed.

### Fresh final verification

Apple Swift 6.4, arm64 macOS 27.0.1 host, macOS SDK 27.0; deployment target remains
macOS 14. Compiler cache and local Git writes needed sandbox escalation. No tools
were installed. Context7 resolved and queried current Swift AsyncStream/cancellation
and Codex app-server documentation; installed generated schema supplied the actual
wire capability evidence rather than assuming the historical version remained current.

| Check | Result |
| --- | --- |
| `swift test --filter QuotaModelsTests` | PASS: 9 tests, 0 failures |
| `swift test --filter QuotaRPCTests` | PASS: 12 tests, 0 failures |
| `swift test --filter QuotaProviderTests` | PASS: 16 tests, 0 failures |
| `swift test` | PASS: 155 tests, 0 failures (118 retained + 37 Stage 4), 10.269 s |
| Actual synthetic process pipes | PASS: simultaneous multi-megabyte stdout/stderr draining, bounded input backpressure, closed stdin/SIGPIPE protection and owned stop |
| Whitespace/privacy/scope checks | PASS: no real captures/credentials/raw diagnostics, third-party runtime dependencies, UI or session-accounting changes |

### Single bounded installed capability check

On 2026-10-08, the installed executable reported **Codex CLI 0.160.1**. Protocol
schema generation succeeded into temporary storage. Its initialize clientInfo,
optional account field, dynamic rate-limit map/windows and passive read parameters
were inspected. The version was checked freshly; the historical 0.160.1 result was
not treated as current proof.

One owned app-server was initialized, acknowledged, then asked for account status
with refreshToken=false and account limits with excludeResetCreditDetails=true.
The same root resolver used by session discovery selected its CODEX_HOME. Analytics
was disabled only in the child. Result: **initialization, account capability and
quota read succeeded; one bucket, one Weekly primary window; no 5h or secondary**.
The owned child was stopped. Missing 5h is valid. Only version, outcome and presence
are recorded; no personal percentages, reset dates, IDs or raw replies were saved.

This was a direct production-RPC capability check before the review fix pass, not
native UI or end-to-end provider acceptance. Final pipe/state changes are supported
by the deterministic regressions and actual synthetic owned-process checks, not a
second live probe. No inference, chat mutation, installation or login was attempted.
Codex-managed retrieval may use network and its normal authentication housekeeping;
Sidecar did not directly inspect or modify credentials.

### A8 and A9 coverage and remaining limitations

| Acceptance | Evidence and boundary |
| --- | --- |
| A8 | Weekly-only, both known durations, independent buckets, duplicate slots, optional alias/permission fields, authoritative empty map, null/absent fallback, malformed fields, clamping/warnings, exact Int64 durations and Unix seconds. Sparse hints retain full-read metadata and receipt time; only full reads replace/remove buckets. Installed live evidence returned Weekly-only. |
| A9 | Fake transport/controllable clock cover single-flight, start/manual/wake/reset/poll/stale/retry, unavailable/auth/API-key/init failure, late old replies/notifications, auth loss and offline; RPC tests cover interleaved IDs, 20-second timeout, cancellation, malformed/oversized replies and process exit. Actual synthetic pipes cover drain/backpressure/closed stdin and cleanup. Offline leaves local parsing operational. |

Cross-process notification delivery and account/workspace changes during real desktop
activity remain **unverified**. No inference was used to provoke changes; polling
remains essential. Tests demonstrate supplied identities/generations; absent identity
cannot prove that a historical selected chat matches the current account. Executable
resolution requires the caller's version/capability verification before claiming
compatibility; other installed versions, macOS 14, Intel and native UI/quit behavior
are unverified. Bounded synthetic concurrency tests are not an exhaustive scheduler
proof. This stage has no persistent metrics/account storage.

Only Stage 4 status/checklists were advanced. Exact current context and actual-model
attribution remain unavailable. Stop before Stage 5. No push, merge, publication or
branch deletion occurred; completed branches remain available.

The following records are historical earlier-stage evidence.

## 2026-10-07 — Stage 3 implementation

**Status at the end of Stage 3: Stages 1, 2 and 3 implemented. Stages 4–6 had not started.**

Started `stage/3-session-reader` from clean local `main` at `3673971` after
Stages 1 and 2 were accepted and merged. Existing branches were retained. All
Stage 3 input was authored synthetically in test-owned temporary directories;
no real Codex home, logs, configuration, credentials or source contents were read
or copied. No inference, installation, UI, quota provider, push, merge,
publication or branch deletion occurred.

### Deliverables and interfaces

- `LineFramer.append(_:)` and `reset()`: newline framing before UTF-8/JSON decode,
  CRLF normalization, empty records, persistent incomplete EOF, byte offsets and
  sanitized oversized diagnostics. At most 8 MiB is buffered for one line;
  oversized input is discarded through its newline. Diagnostics are aggregated,
  without payloads, and can be drained into the reader.
- Sendable `SessionDescriptor` retains local source URLs for reads, logical ID,
  project basename, CLI version, modification-time activity and parent provenance.
  Conflicting parent/root copies expose `provenanceAmbiguous` and cannot become a
  recent-root suggestion. Roots precede children; stable ID ordering breaks list
  ties without inventing foreground identity.
- `SessionCatalog.discover(root:)`, `sessions(root:)` and `stop()`: bounded initial
  header discovery, optional archives, duplicate logical-source grouping and
  explicit available/missing/unreadable/partial status. Root resolution is a pure
  helper receiving override, environment and user-home values; tests inject all
  three. It does not inspect configuration or credentials.
- `SessionReader.select(_:)`, `refresh()`, `snapshots()` and `stop()`: read-only
  background workers, per-source offset/framer/normalized contribution, inode and
  nanosecond metadata checks, immutable externally readable derived snapshots,
  cancellation and latest-only bounded AsyncStream subscriptions. Only complete
  lines pass through Stage 1; Stage 2 performs all accounting and reduction.
  Supplied `root` enables selected-session archive/duplicate reconciliation.
- `SessionSelection` keeps `pinnedID` separately from `mostRecentSuggestion` and
  equally recent root candidates. New children, concurrent roots, missing activity
  and source deletion cannot change the manual pin.
- Filesystem hints are optional accelerators. Selected-file stat checks run every
  1 second, catalog reconciliation every 5 seconds, on provider actors/workers.
  Each source read or integrity-check chunk is at most 64 KiB. Read loops consume
  only the statted extent, so a continuously appending writer cannot extend a
  single read indefinitely. Concurrent mutation fails closed and retries later.
- Source reads traverse directory descriptors with `openat`, `O_DIRECTORY` and
  `O_NOFOLLOW`, then open regular files with `O_RDONLY`. Every parent is pinned
  against symlink substitution; special files are rejected. Watch descriptors
  use `O_EVTONLY`; owned read handles close with `defer`, watcher cancellation
  closes owned descriptors, and `stop()` awaits outstanding owned read/scan jobs.
- Shrink, inode replacement, equal-size metadata changes and a changed previously
  read prefix rebuild that source contribution. Before treating growth as append,
  streaming SHA-256 verifies the entire prior extent; only digests survive these
  transient reads. Apple's system CryptoKit adds no third-party dependency.
  Old and replacement totals are never added together.
- Read/selection generations, source revisions and ordered/coalesced catalog
  requests reject obsolete results. Explicit refresh/reconciliation waits for its
  current work; cancelled catalog callers cannot wedge subsequent refreshes.
  Last-subscriber termination stops workers, and explicit stop finishes streams.
- Decode/framing gaps, incomplete EOF and unavailable sources propagate sanitized
  diagnostics, partial/unavailable source availability and degraded reconciliation.
  Valid observed rows remain available; missing breakdown and cache rate remain
  unknown. Completing an otherwise clean partial line can restore coverage. A
  malformed/unknown/oversized first record cannot authorize a later header.
  Exact current context remains unavailable.

### Test-first and independent review evidence

The four planned test classes and synthetic filesystem utility were written before
production components. The initial build reached missing Stage 3 types after
compiler-cache access was allowed. Behavioral RED runs subsequently reproduced
refresh returning before an existing watcher read finished and source-ID collision
when a new file sorted before an already cached source; both became GREEN.
Initial test URL comparisons were corrected for macOS temporary-path aliases;
tests now create directories first and use their physical canonical paths.

One independent fresh-context reviewer examined the complete implementation and
independently reran the initial 107-test suite. It found four important classes of
failure. Author-owned synthetic regression tests reproduced these before fixes:

| Important finding | RED → GREEN regression |
| --- | --- |
| Growing interior rewrite kept a removed request and missed a response conflict | `testInteriorRewriteWithGrowthRebuildsAndQuarantinesConflict` |
| Unknown/oversized first record permitted later header ownership | `testReplacementMustStartWithOwningHeader`, `testOversizedInitialHeaderCannotAuthorizeLaterHeader`, `testOversizedFirstRecordCannotDiscoverLaterHeader` |
| Obsolete catalog scan replaced a newer root status; concurrent scans lacked ordering | `testObsoleteCatalogScanCannotOverwriteNewRootStatus`, `testOlderConcurrentDiscoveryCannotChangeNewerStatus`; generations/request ordering guard status and publication, reader catalog requests coalesce |
| Parent symlink substitution between path check and open escaped discovery roots | `testSourceOpenRejectsParentSymlinkRaces`: original implementation read outside the test root 363 times in 4,000 attempts; descriptor traversal now reads none while still opening legitimate sources |

Additional RED → GREEN checks cover cancelled catalog callers wedging refresh,
explicit partial source availability after malformed/oversized input, and conflicting
root/child provenance. The concurrent-discovery test was additionally observed RED with its request-order
guard temporarily removed, then GREEN with it restored. Selection generation is
checked both in the final snapshot and in every observed AsyncStream update.
Root-before-child ordering was also corrected as an existing
Stage 3 specification requirement. No second review is claimed: fixes were verified
by the regression tests and final full suite.

Task ledger: framing/selection `bb91c65`; catalog/safe traversal `ed21edb`;
reader/rebuild/diagnostics `bf6cc6b`; final verification below. No implementation
scope ruling changes the accounting contract. Final deferred minor: unchanged stat
refresh still re-runs the normalized reducer (the reviewer measured approximately
0.150 seconds for 10,000 requests before the fix pass); snapshot reuse is a future
optimization. This does not reparse unchanged bodies or block the main actor.

### Fresh final verification

Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), macOS SDK 27.0, arm64 macOS 27.0.1 host.
Local compiler-cache access required sandbox escalation; no installation or developer
setting change occurred. Current Swift AsyncStream/cancellation and Apple CryptoKit
incremental-hashing documentation was consulted through Context7. No source from
another project was copied.

| Check | Result |
| --- | --- |
| `swift test --filter LineFramerTests` | PASS: 4 tests, 0 failures |
| `swift test --filter SessionCatalogTests` | PASS: 11 tests, 0 failures |
| `swift test --filter SessionReaderTests` | PASS: 19 tests, 0 failures |
| `swift test --filter SessionSelectionTests` | PASS: 2 tests, 0 failures |
| `swift test` | PASS: 118 tests, 0 failures (82 retained + 36 Stage 3) |
| Main-actor heartbeat during background 10,000-request replay | PASS; progress continues during provider work, not native UI acceptance |
| Whitespace/privacy/scope checks | PASS; no private captures or third-party runtime dependencies introduced |

### Measured filesystem behavior

The final full-suite run generated a **2,097,998-byte, 10,000-request** temporary
JSONL stream containing invented IDs, one-token completed responses and optional
breakdowns. The tests performed actual filesystem writes/reads and real elapsed
wall-time measurement in the debug build. Watcher hints were disabled for the
append/discovery measurements; the discovered file also contains the complete
10,000-request stream. These exercise production fallback intervals.
There are **no simulated timer measurements** presented as filesystem evidence.

| Measurement | Final full-suite result | Target / interpretation |
| --- | --- | --- |
| Initial parse/replay and reduction | 0.210 s | 10,000 requests; totals and optional counters checked |
| Appended complete request visibility | 0.980 s | PASS: ≤2 s through 1-second stat fallback |
| New nested session discovery | 5.100 s | PASS: ≤6 s through 5-second catalog reconciliation |
| Cancellation after a pending read had 20 ms to start | 0.000886 s | Responsive on this host; no cross-platform cancellation guarantee |
| Stop after appended state | 0.000423 s | Streams/workers stopped, outstanding owned work awaited |

Both latency targets held in this final run. These are bounded measurements on
this host under normal development load, not worst-case guarantees. Large-source
integrity revalidation and reduction costs can increase latency; unmet targets on
other hosts must be reported rather than inferred from this result.

### A1, A3, A10 and A11 coverage

| Acceptance | Stage 3 evidence and remaining boundary |
| --- | --- |
| A1 | Injected root precedence; empty/missing/unreadable roots and subdirectories; optional archives; duplicate logical sessions; symlink skips and racing parent substitution; root/child order and ambiguous provenance/activity; manual pin survives newer children/concurrent roots and deletion. Actual GUI/settings acceptance remains Stage 5. |
| A3 | Filesystem replay equals Stage 2's 180-token fixture; append, duplicate sources, archive move, conflicting copies, restart rebuild, distinct source identity and replacement contribution retraction. Stage 2 replay/snapshot/checkpoint invariants remain passing. |
| A10 | Every-byte and split multibyte framing, CRLF, empty records, incomplete EOF/completion, malformed-line recovery, >8 MiB discard/recovery with bounded buffer, honest parser diagnostics, invalid initial ownership, truncation, atomic/in-place equal-size replacement and interior rewrite with growth. No raw text/path diagnostics. |
| A11 | Actual synthetic 10,000-request parse/append/discovery/cancellation measurements, background main-actor heartbeat, stream termination and worker stop, selection generation rejection, obsolete catalog status regression and cancelled-caller recovery. No native UI or quota-process responsiveness/quit acceptance is claimed. |

### Remaining limitations and stop boundary

Only synthetic filesystem/core acceptance is complete. No real installed-profile
rollout acceptance, UI, quota process or live inference was performed. macOS 14,
Intel, other filesystems, exceptional sustained-write/load behavior and native UI
acceptance remain unverified. Filesystem ordering/symlink races have bounded
regression coverage, not an exhaustive adversarial scheduler proof. Unknown future
JSONL schemas remain outside the validated profile. Metadata and metrics have no
persistent database; source loss removes unavailable contributions rather than
pretending durable lifetime history.

Exact current context, actual fallback-model attribution, unreported attempts,
per-tool costs and family totals remain unavailable. Only Stage 3 status/checklists
were advanced. Stop before Stage 4; local commits require separate owner approval
for any later push or merge.

The following records are historical earlier-stage evidence.

## 2026-10-07 — Stage 2 implementation

**Latest status: Stages 1 and 2 implemented. Stage 3 has not started.**

Started `stage/2-session-model` from the clean current `main` at `51cb518`.
Stage 1's 29 tests remain passing. All new resources were authored synthetically;
no real rollout, credentials, account identifier, prompt or tool payload was read
or copied. No inference, installation, file discovery/reader, UI, quota process,
push, merge, publication or branch deletion occurred.

### Deliverables and accounting boundary

- Pure deterministic `SessionReducer.reduce(_:owningThreadID:)`, immutable
  Sendable `DerivedSession`, `ObservedRequest` and task snapshots.
- Initial header ownership is locked per logical source. Later inherited headers
  cannot change it. Foreign usage is excluded from the owned ledger, while foreign
  native boundaries still prevent unsafe tool association. Unidentified sources
  cannot authorize exact accounting.
- Deduplicate by owned thread/response key. Distinct IDs with equal usage count
  separately. Conflicting usage, task or cumulative values retract and quarantine
  that key, with sanitized diagnostics and degraded reconciliation. Source offset,
  timestamp and runtime session ID are provenance, not request identities.
- Optional-field checked aggregation preserves unavailable breakdowns. Cache rate
  uses the same validated request set; zero input or missing input/cache makes it
  unavailable. Aggregate overflow makes totals unavailable and degrades coverage,
  preserving the valid individual rows. Empty ledgers expose unavailable totals.
- `Reconciliation` keeps observed sums, inferred baseline and native reported
  cumulative separate. Positive baseline and legacy/native transitions are partial
  history; reset, component disagreement, conflicting ID and exceptional snapshot
  disagreement cannot certify continuity. Missing cumulative total is incomplete
  coverage. No balancing requests or positive-clamped billing deltas are created.
- Checkpoints can seed a reported baseline or corroborate their own native
  response boundary. They never create rows or reset observed totals. A checkpoint
  without a native ledger exposes reported partial history, not an exact timeline.
  Without native records, the latest legacy snapshot is unverified reported usage,
  including after a decrease/reset.
- `ToolAssociator` deduplicates function/custom calls, updates late output status,
  and associates only by validated single-task order segments. Unmatched output,
  orphan, conflicting call metadata, task/compaction boundaries, concurrent tasks
  and copies disagreeing on order preserve ambiguity. `functions.exec` remains
  one invocation; arguments and inner operations are not parsed. Tools never
  create requests or token charges.
- `ContextState` separates configured model, source/task-bound advertised window,
  timestamped last native footprint and its historical state. It exposes explicit
  window provenance and historical configured-model state. Exact current context
  is always unavailable. Changed model/window, interruption and compaction cannot
  revive an old footprint; fresh native usage and a matching window snapshot can
  recover the last-request ratio. Concurrent unscoped snapshots cannot assign a
  window. Conflicting configured labels across source copies are unavailable,
  including duplicate request attribution affected by that conflict.
- Exact source copies and strictly matching older prefixes are suppressed before
  lifecycle/context replay. Differing evidence is retained conservatively: an
  older start from another source cannot reopen a completed task until a fresh
  unique response provides evidence. Taskless terminal events can target only a
  single active task. Requests preserve stream order, without timestamp sorting.
- `Fixture.events(_:)` uses Stage 1 decoding and rejects unexpected fixture
  diagnostics. All added JSONL resources use invented identities and counters.

### Test-first and independent review evidence

The four focused test classes were written before implementation. Initial runs
first failed for missing Stage 2 types, then all four failed against compilable
empty reducers. Subsequent boundary regressions were observed RED before their
corrections, including legacy/native zero-baseline transition, foreign tool
boundary, changed window freshness, copied checkpoints, concurrent window scope,
post-compaction recovery, stale prefix lifecycle/context, differing source metadata
and exceptional context-full snapshots. The empty-cumulative regression was also
verified RED with its correction temporarily removed, then restored and passed.

A separate fresh-context reviewer inspected the complete Stage 2 implementation
and independently reproduced synthetic failures. Important findings were fixed
with regression tests:

| Finding | Regression evidence |
| --- | --- |
| Historical copied checkpoint compared with final global sum | `testCopiedCompactionStreamDoesNotDegradeReconciliation` |
| Empty cumulative object incorrectly certified coverage | `testEmptyCumulativeCannotCertifyFullCoverage` |
| Fresh post-compaction capacity could not restore ratio | `testFreshNativeAndMatchingWindowSnapshotRecoverAfterCompaction` |
| Concurrent snapshot mixed model/window task scopes | `testConcurrentSnapshotCannotAssignCapacityToLatestRequest` |
| Older prefix reopened completed task or restored older model/window | `testOlderPrefixCopyDoesNotReopenCompletedTask`, `testOlderPrefixCopyDoesNotReplaceLatestTaskContext` |
| Differing-window prefix reopened task and looked fresh; conflicting model chosen | `testDifferingWindowCopyCannotReopenCompletedTask`, `testDifferingWindowCopyInvalidatesOldFootprint`, `testDifferingModelCopiesDoNotChooseConfiguredAttribution` |

Final independent review: all reported important findings closed; **82 tests,
zero failures**, independently rerun. No confirmed remaining blocking correctness
finding. Review used repository fixtures and temporary synthetic probes only.

### Fresh final verification

Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), macOS SDK 27.0, arm64 development host.
Compiler-cache access required running the local Swift tests outside the filesystem
sandbox; no toolchain installation or developer setting change was made.

| Command/check | Result |
| --- | --- |
| `swift test --filter SessionReducerTests` | PASS: 14 tests, 0 failures |
| `swift test --filter ReconciliationTests` | PASS: 16 tests, 0 failures |
| `swift test --filter ToolAssociatorTests` | PASS: 10 tests, 0 failures |
| `swift test --filter ContextStateTests` | PASS: 13 tests, 0 failures |
| `swift test` | PASS: 82 tests, 0 failures (29 Stage 1 + 53 Stage 2) |
| `git diff --check` | PASS |
| Source/test privacy-pattern scan | No private path, credential file/token/key markers found |
| Dependency and scope inspection | No remote dependency, reader, executable/UI target or quota implementation added |

### A2–A7 coverage

| Acceptance | Stage 2 synthetic evidence and limits |
| --- | --- |
| A2 | SPEC example: total 180, input 150, cached 100, output 30, reasoning 7, cache rate 66.6667%; explicit zero, partial breakdown and checked aggregate overflow. Stage 1 retains invalid/negative/subset/overflow decoding checks. |
| A3 | Same-stream replay, duplicate logical sources, resume replay, identical older prefixes, repeated snapshots/checkpoints and equal-valued distinct IDs. Archive-like logical copies are covered; actual filesystem moves/replacement are Stage 3. |
| A4 | Conflict quarantine/retraction, locked initial ownership, foreign inherited usage exclusion, unidentifiable source rejection, positive baseline, reset, component disagreement, missing/empty cumulative, legacy/native transition and exceptional snapshots. |
| A5 | Two requests in one task, multiple task contexts, interrupted activity without usage, missing-start incomplete group, taskless single-active completion/interruption, older copy cannot reopen terminal task. |
| A6 | Function/custom calls, duplicate completed mirrors, late output, output-before-call, orphan/cross-task/concurrent activity, foreign native boundary, conflicting metadata and differing copy order. Inner orchestration operations remain discarded. |
| A7 | Source/task window provenance, configured model rather than actual model, unavailable exact occupancy, native footprint, stale compaction/interruption/model/window state, fresh matching recovery, concurrent snapshot scope, old prefixes and conflicting model/window copies. |

### Remaining limitations and next gate

This acceptance covers normalized synthetic replay only. JSONL internal profile
compatibility remains limited to the Stage 1 selective schema; it is not live
runtime certification. Decode diagnostics must be propagated by the future reader;
`Fixture.events` intentionally rejects malformed fixture input instead of hiding
those diagnostics. Source disappearance/replacement and stream rebuilding, file
ordering/discovery, performance, UI labeling, live quota behavior and live numeric
acceptance remain later-stage checks. macOS 14 and Intel runtime support are not
exercised. Conflicted/unknown metadata may conservatively remain unavailable.

Exact current context, actual fallback/compaction model attribution, attempted
requests without native usage, individual tool costs and family-wide totals remain
unavailable by design. No Stage 3–6 completion is claimed. Stop here for owner
acceptance; do not push or merge the Stage 2 branch.

The records below are historical earlier-stage evidence.

## 2026-10-07 — Stage 1 implementation

**Status: Stage 1 implemented and tests passing. Stage 2 has not started.**

Continued the existing `stage/1-parser` branch without resetting it. The owner
installed/selected Xcode; Sidecar did not install tools or change developer settings.
The active Xcode is 27.0 (27A266a), SDK macOS 27.0, Apple Swift 6.4
(`swiftlang-6.4.0.34.1`), arm64 host. `xcrun --find xctest` now resolves the Xcode
runner. The prior XCTest build gate is resolved. The deployment floor remains
macOS 14, but macOS 14 and Intel runtime support have not been exercised.

### Implemented boundary

- Swift 6 library/test package, macOS 14 minimum, no executable/UI target,
  no remote or third-party runtime dependencies; `Bundle.module` fixtures.
- Immutable Sendable value types for optional counters, source position,
  request identity/provenance, lifecycle, configured model, snapshots, tool
  metadata, compaction checkpoint, decode result and sanitized diagnostics.
- Checked Int64 validation and addition: reject negatives, subset violations,
  explicit total disagreement, input/output overflow, and field sum overflow.
  Missing/null fields remain `nil`; missing total is never recomputed. Cache-read,
  cache-write and reasoning values are not added again to the explicit total.
- Type-directed selective `Decodable` parsing accesses only allowlisted keys.
  No generic JSON tree or transcript content is retained by production code.
  Native records, snapshots and checkpoints remain separate event cases.
- Native records require nonempty thread/response/task IDs and a usage object.
  Runtime session/root-task IDs and cumulative breakdowns remain optional.
  Ownership enforcement, deduplication and trusted aggregation belong to Stage 2.
- Tool input/arguments/output, messages, reasoning, unknown event payloads,
  replacement history, quota payloads and unknown fields are discarded.
  Diagnostics contain category/optional position/count only, never decoding
  error descriptions or source bytes. Dates are normalized; configured model
  remains explicitly configured, never an actual-response model attribution.
- The decoder rejects a supplied record above 8 MiB before JSON decoding.
  Byte framing, partial EOF, chunking and oversized-stream recovery belong to
  Stage 3; this guard does not implement a live reader.

### Fresh tests and checks

| Check | Result |
| --- | --- |
| Initial focused runs after Xcode selection | RED: missing planned types, rather than missing XCTest |
| Compilable decoder stub, original parser suite | RED: 14 tests, 57 expected failed assertions |
| Expanded decoder stub suite | RED: 18 tests, 61 expected failed assertions |
| `swift test --filter RolloutDecoderTests` | PASS: 19 tests, 0 failures |
| `swift test --filter TokenUsageTests` | PASS: 9 tests, 0 failures |
| `swift test` | PASS: 29 tests, 0 failures (19 decoder, 9 counters, 1 resources) |

The focused and full suites use only authored fixtures and generated synthetic
bytes; no account/network or real Codex files are involved. Fixtures contain
SPEC §9's two request usages (120/60) and cumulative 180, plus malformed,
unknown/sensitive, optional/zero and invalid-counter cases. The synthetic native
profile represents the documented 0.160.1 envelope fields; test success is not a
claim of live compatibility or ledger reconciliation.

The synthetic fixture JSON/privacy scan passed for all five JSONL files (28
lines, one deliberately malformed). `git diff --check` passed. All source and
artifact text added for this stage is English.

### Independent review and regression fix

An independent read-only reviewer found one important gap: known partial input
or output could exceed the explicit total if its other parent field was missing.
The gap also applies to known cached/reasoning lower bounds with absent parents.
It was reproduced by `testPartialCountersCannotExceedExplicitTotal`,
`testPartialSubsetLowerBoundOverflowFailsClosed`, and
`testContradictoryPartialUsageIsQuarantined`: RED, 29 tests with 16 failed
assertions. The fix validates the minimum possible input/output sum and its Int64
overflow without filling unknown fields. The final focused/full GREEN results
are in the table above. No critical or minor review findings were reported.

Review scope boundaries were affirmed against the owner's Stage 1 instruction:
ledger ownership/deduplication/reconciliation/cache percentage belong to Stage 2;
streaming recovery and UI performance belong to reader/UI stages; live and older
platform compatibility require later acceptance. These are deliberately unclaimed,
with the risk that those later-stage gates can still uncover incompatibilities.
The documentation review exclusion was resolved by updating this record and
fixture notes. No additional implementation deviations or deferred minors remain.

Stage 1 covers A2's subset/availability/overflow primitives and A10's complete
malformed/unknown-record privacy. A2's session totals/cache rate and the remaining
A10 reader cases require later stages. No request reconstruction, cache-rate
aggregate, current-context claim, UI or quota provider is implemented. No real
logs/credentials were copied, no inference was run, and nothing was pushed/merged.

### Remaining gates

Stage 2 requires explicit owner authorization and the project's acceptance/merge
workflow. Stages 2–6 remain unstarted. Runtime compatibility, older macOS/Intel,
file framing/recovery, performance, native UI and live quotas remain unverified.

## 2026-10-07 — Initial build gate (historical, superseded below)

**Status: Stage 1 incomplete. Stage 2 has not started.**

Read `AGENTS.md`, `SPEC.md`, `IMPLEMENTATION_PLAN.md`, and `docs/research.md`.
Started `stage/1-parser` from the current local `main`; the working tree was clean
and the stage branch did not exist. No push, merge, installation, UI, quota
provider, live inference, real-log inspection, or credential access was performed.

### Tools and package

- Apple Swift 6.4 (`swiftlang-6.4.0.34.1`, `clang-2100.3.34.1`), arm64 target.
- Active developer tools: Command Line Tools. SDK version: macOS 27.0.
- No Xcode application was present in the inspected Applications directory.
- `Package.swift`: Swift tools 6.0 / Swift 6 language mode, macOS 14 minimum,
  `SidecarCore` library and XCTest test target, processed fixture resources,
  no executable target and no remote dependencies.
- Consulted current SwiftPM manifest/resource documentation through Context7
  (`/swiftlang/swift-package-manager`) for resource bundling with `Bundle.module`.

### Fresh command results

| Command | Exit | Result |
| --- | --- | --- |
| `swift --version` | 0 | Installed compiler identified above |
| `xcrun --show-sdk-path` | 0 | Installed Command Line Tools SDK resolved |
| `xcrun --show-sdk-version` | 0 | 27.0 |
| `swift build` | 0 | Empty core scaffold builds; no parser implementation exists |
| `swift test --filter FixtureTests` | 1 | Cannot resolve module dependency `XCTest` |
| `swift test --filter RolloutDecoderTests` | 1 | Cannot resolve module dependency `XCTest` |
| `swift test --filter TokenUsageTests` | 1 | Cannot resolve module dependency `XCTest` |
| `swift test` | 1 | Cannot resolve module dependency `XCTest` |
| Synthetic fixture JSON/privacy scan | 0 | 28 lines; one deliberately malformed line; no private paths, credential patterns, or email identifiers |
| `git diff --check` | 0 | No whitespace errors |

Initial sandboxed attempts could not write Swift/Clang caches and produced a
secondary SDK/compiler mismatch message. Repeating with cache access allowed
compiled the core scaffold and reached the distinct test dependency failure:

```text
FixtureTests.swift:1:8 unable to resolve module dependency: 'XCTest'
error: Build failed
```

The available Command Line Tools developer frameworks contained Swift Testing,
but not XCTest. No framework/toolchain substitution or installation was attempted.
The Stage 1 Step 1 instruction is: “If the installed SDK cannot compile a core
test, stop and report the precise build gate.” Implementation stopped at that gate.

### Preserved preparation and boundaries

Five JSONL fixtures are synthetic and documented in their fixture README. Test
sources describe counter subset/availability validation, checked sum overflow,
selective payload discard, identity/envelope rejection, native/snapshot/checkpoint
separation, lifecycle/model/tool metadata, and malformed-line recovery.

These are **unexecuted tests**, not demonstrated parser correctness. The focused
runs did not reach expected RED failures for missing decoder/validation because
XCTest import failed first. `Metrics.swift` is an import-only placeholder;
`TokenUsage`, normalized events, `RolloutDecoder`, and counter validation remain
unimplemented. The prepared tests reference those future APIs and will require a
fresh compile and RED→GREEN cycle after the build gate is resolved.

A2 and A10 are not accepted. No owned-ledger reconstruction, deduplication,
reconciliation, cache-rate aggregate, incremental reader, large-line framing,
context state, UI, quota work, or live compatibility is claimed. macOS 14 and Intel
runtime support remain untested. The authored profile matches the documented
0.160.1 native envelope and SPEC §9 numbers only; it is not a certified runtime
profile. The library build validates the scaffold, not accounting functionality.

Resume only Stage 1 on the existing branch after an XCTest-capable installed
toolchain is available. Re-run the build gate and both required focused tests,
implement the selective decoder/counter primitives, then run full `swift test`
and replace this blocked status with fresh evidence. Do not begin Stage 2.
