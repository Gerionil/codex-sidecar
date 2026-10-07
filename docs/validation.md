# Validation record

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
