# Validation record

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
