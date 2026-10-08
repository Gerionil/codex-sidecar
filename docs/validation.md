# Validation record

## 2026-10-08 — Approved compact selector dates

The owner approved `dd.MM HH:mm` in selector labels, with `.yy` added for a
different local Gregorian year. Full locale-formatted date, seconds and time zone
remain selectable under the chosen chat on both surfaces. Existing sorting,
identity, pinning and quota logic are unchanged. Batch label preparation reuses
one formatter off the UI actor. The new regression covers missing dates, the same
instant across a local New Year in UTC/+03:00 and actual compact selector output.

Fresh verification: full `swift test --disable-sandbox` **191 tests, 0 failures**;
release build/package exit 0; valid Info.plist and arm64 Mach-O bundle. Ten thousand
shared-prefix label preparation took 0.0237 s. Independent read-only review found
no material issues; `git diff --check` passed. RED initially established the absent
compact-date API. An initial test incorrectly assumed the full date's UTC year;
this was corrected to respect the local time zone, without changing full-date
formatting. Native acceptance of the new shorter label remains pending. Keyboard,
VoiceOver and naturally completed real-response append remain unverified. No
real-data probe, user-app termination, push or merge was performed.

## 2026-10-08 — Owner-approved selector refinement

Implemented on the existing `stage/6-validation` branch after the owner approved
the bounded design. Both native selectors now show optional stored chat titles
from the selected root's `session_index.jsonl`, with distinguishable ID fallback
and duplicate-title disambiguation. Root chats precede children; each group sorts
by newest known activity (maximum source modification/index update time), then
stable ID ties. Recency is a heuristic, not foreground detection. Selection stays
pinned by ID; catalog rename/reorder does not restart providers or change metrics
or account quotas.

The metadata reader is read-only, memory-only and bounded to 64 KiB chunks,
16 MiB total input and 4 KiB names, using regular-file/no-symlink source access.
It retains only names/update times joined to discovered IDs, discards unknown
fields and malformed complete entries, and ignores incomplete tails. Missing,
unreadable, symlinked or oversized indexes safely fall back. No transcript name
inference, chat RPC, real-data export or new quota/live-inference probe was used.
A focused failure exposed Foundation normalization of physical temporary-root
paths; resolving only the approved root fixed this while preserving rejection of
symlinked index files.

| Fresh check | Result |
| --- | --- |
| Focused RED → GREEN | Recency/name tests initially failed (6 tests, 7 assertions); descriptor behavior failed (3 tests, 5 assertions), then focused 9 tests passed |
| Full `swift test --disable-sandbox` | 190 tests, 0 failures; includes oversized/malformed metadata, rename/ties, ID collisions, read-only/symlink boundaries and shared-store selection/metric/quota preservation |
| Synthetic 10,000-chat duplicate-name/shared-prefix label preparation | 0.0243 s; 10,000 distinct labels; prepared off the UI actor once per catalog update |
| Synthetic 10,000-request reader run in full suite | Replay 0.229 s; stat-only append 0.945 s; stat-only discovery 5.097 s; stop 0.00045 s |
| `swift build -c release --disable-sandbox` | Exit 0 |
| `scripts/package-app.sh --disable-sandbox` | Exit 0; rebuilt local app bundle |
| Package inspection | Info.plist valid; Mach-O arm64; macOS deployment floor 14.0 |
| Independent code review | Initial P2 quadratic menu-label preparation fixed; repeat review found no material issues |
| Whitespace/privacy review | `git diff --check` passed; no debug output or real title/log/credential captures introduced |

Tests/build/package ran outside the outer validation sandbox with project-local
compiler caches. This verifies only the current Apple Silicon Mac. No Intel or
macOS 14 runtime check is claimed. The owner subsequently confirmed that stored names appeared and the list was
sorted in the rebuilt native app. Compact date presentation was requested; no
additional shared-selection/layout acceptance is inferred from that report. Earlier owner-reported
manual acceptance predates this change; keyboard navigation, VoiceOver and real
completed-response live append remain **NOT VERIFIED**. No user-owned app was
stopped or relaunched during this refinement. No push or merge was performed.

## 2026-10-08 — Owner-reported manual acceptance on the current Mac

The owner reported completing the supplied manual checklist except keyboard
navigation (Tab/Shift+Tab), VoiceOver labels and naturally appended completed
responses in a real chat. The no-natural-event reporting item is part of that
same live-append gap, not a fourth independent test. This is **owner-reported
native evidence**, not an automated UI-channel inspection or a new deterministic
suite. Acceptance scope is explicitly limited to the current Apple Silicon Mac;
macOS 14 and Intel remain untested, with no other environment required for this
bounded acceptance pass.

Covered by the owner's report: launch/menu icon, empty selection, synthetic A/B
accounting and details, empty chat, long labels/resizing/scrolling/selectable
numbers, shared selection and quota independence, pinning with a new synthetic
chat, panel dismissal/reopening, one companion window/focus/reuse/close/reopen,
all supplied quota variants (weekly-only, 5h plus Weekly, multiple buckets,
duplicate-duration slots, null values, empty map, loading, stale, retained error,
authentication unavailable), synthetic append, offline local updates/recovery,
and GUI Quit followed by the helper's process/fingerprint/allowlist check.
No new personal numeric data, transcript screenshots or real identifiers were
copied into the repository.

| Acceptance area | Updated evidence / remaining limitation |
| --- | --- |
| A1 | Native manual selection and synthetic launch overrides owner-reported PASS; exhaustive native Settings/root/archive variants remain outside this checklist |
| A2, A5–A7 | Supplied synthetic displayed metrics/details and unavailable current context owner-reported PASS; underlying deterministic accounting evidence remains separate |
| A8–A9 | Supplied synthetic quota rendering and offline behavior owner-reported PASS; real account changes/cross-process notifications remain unverified |
| A11 | Synthetic visible append and GUI Quit/owned cleanup owner-reported PASS; real completed-response live append remains UNVERIFIED |
| A12 | Prior bounded installed numeric/quota comparison and repository hygiene evidence retained; no new real-data probe |
| A13 | Shared/pinned selection, quota independence, panel/window lifecycle and GUI Quit owner-reported PASS |
| Keyboard/accessibility | Tab/Shift+Tab and VoiceOver checks NOT PERFORMED |

Full native acceptance is still incomplete for the remaining checks. The owner
also identified selector usability improvements: recent chats should appear first,
and available chat titles should replace opaque IDs after the project label.
These are requested follow-up changes, not passing acceptance of existing title
support. Current catalog ordering is root-first then identity, and current labels
show project/short ID/provenance/activity. No feature code is changed by this
acceptance record. Subsequent selector changes require focused regression checks
and a brief repeat of selection/layout acceptance.

The records below preserve earlier evidence and its original limitations.

## 2026-10-08 — Stage 6 installed-version validation and repository hygiene

**Status: authorized validation/documentation work performed; full native
application acceptance remains incomplete.** Started `stage/6-validation` from
clean local `main` at `150358b`, preserving Stages 1–5 and all existing branches.
No product behavior changes or deferred reducer optimization were made. No push,
merge, publication, license choice, installation, signing, notarization,
quarantine removal or branch deletion was performed.

### Synthetic native attempt, before real-data checks

Fresh test-owned files contained two invented native sessions, including a long
project label, and a fake quota executable with weekly-only data. LaunchServices
inside the sandbox failed with `kLSNoExecutableErr` (-10827). A narrowly approved
launch outside it used the packaged app with explicit `--isolated-settings`,
`--codex-root` and `--codex-executable`. Process inspection confirmed exactly one
Sidecar instance and all synthetic arguments **before** UI binding. The fake
reported `0.0.0-synthetic`; its method-only log contained initialize, initialized,
account/read and account/rateLimits/read, with no other methods.

Inventory worked, but the single binding to the confirmed running instance
failed with **`Sky Computer Use native pipe closed before response`**. No native
accessibility tree or screenshot was obtained. No retry or auto-launch recovery
was attempted. Post-failure inspection confirmed no extra/default-root instance.
Only the identified test app and fake child were stopped by signals; absence was
checked separately. Before/after SHA-256 comparisons of both synthetic source
files matched. Signal cleanup does **not** verify explicit GUI Quit.

The Stage 5 incident below remains historical and intact. This safe synthetic
attempt supplies launch/argument/privacy evidence, not interactive acceptance.
Weekly-only, 5h + Weekly, multiple buckets, duplicate-duration slots, null values,
empty/loading/unavailable/stale/error presentation, default/resized/long-label
layout, selectable numbers, keyboard/accessibility, native shared/pinned
selection, quota independence, focus/reuse, panel dismissal/reopen, companion
close/reopen, visible append updates, offline interaction and GUI Quit remain
**unverified in native UI**. Their deterministic coverage is separate below.

### Bounded real numeric comparison

Production catalog discovery selected one existing root session with a valid
owned native ledger and header version **0.160.1**. Candidate selection was bounded
to twelve recent single-source root sessions and at most 8 MiB per candidate;
only one eligible source was passed to SessionReader. An initial bounded batch
in catalog ordering found no eligible sample; ordering was corrected to recent
activity in the ignored validation harness, without changing application code.

An independent selective in-memory inspection keyed native records by owning
thread and response identity, checked counters/subsets, deduplicated responses,
and compared cumulative baseline progression and mirrored numeric snapshots.
The production SessionReader snapshot matched on all checked results:

| Comparison | Result |
| --- | --- |
| Unique owned completed-response count | Equal |
| Observed total and every optional breakdown component | Equal |
| Aggregate cache rate, including availability | Equal |
| Reconciliation classification | Equal |
| Latest reported cumulative components | Equal |

No source paths, session IDs, personal totals, prompts, reasoning, messages, tool
arguments/output or raw lines were printed or saved. Source bytes were transient
in memory; the ignored harness contains code and sanitized outcomes only, no
captures. No authentication files or prompt-derived titles were read. The
comparison is bounded single-session evidence, not exhaustive compatibility.

SHA-256 fingerprinting bracketed the production read and a five-second natural
observation. The selected source grew with the entire original prefix intact.
Therefore **unchanged bytes are not claimed**; this is consistent with concurrent
Codex append activity, rather than a source rewrite by Sidecar. The harness did
not establish whether the appended bytes included another completed-response
record, nor compare a new completed response to rendered GUI state. Real
completed-response live-append acceptance remains **unverified**. No inference,
resume/fork, compaction, interruption or chat mutation was initiated for data.

### Current installed quota compatibility

The chosen executable was resolved through production discovery and freshly
verified as **0.160.1**, using the same resolved root as session discovery.
Production QuotaProvider and its allowlisted QuotaRPC performed passive reads
with analytics disabled, `refreshToken: false`,
`excludeResetCreditDetails: true`, and no Luna reserve capability.

The first attempt received an initialization account hint and was stopped before
any quota read (zero full reads). This is the documented startup invalidation
path, not a schema incompatibility. A bounded recovery run allowed the provider's
ordinary scheduled 60-second retry on its existing process; it completed exactly
**one** full quota read. No manual extra quota read or repeated successful probe.

An independent in-memory comparison matched bucket membership/count, optional
name/alias metadata, slot identity, nullable values, minute durations and reset
conversion to Unix seconds. The returned shape had **one bucket, one 10,080-minute
Weekly window, one absent slot, no 300-minute window**, and no null numeric fields
inside the present window. Personal percentages, reset dates, account/plan values,
identifiers and raw replies were not retained or printed. Nullable windows stayed
absent; real multiple-bucket/duplicate-duration/null-numeric variants were not
observed and retain synthetic coverage only.

Methods remained allowlisted. Provider stop closed its owned transport; final
process inspection verified cleanup. No auth files were opened, no login/logout,
account switch, reset/credit action, inference or desktop process attachment was
performed. Normal Codex authentication/runtime housekeeping is not certified
read-only. Current initialization hints are not evidence for cross-process
quota notifications or a real account change. Historical Stage 4 and research
probes below are separate dated evidence, not substituted for this fresh check.

### Public-repository hygiene

Enumerated all **109 tracked files** and non-ignored untracked files (none before
edits). Reviewed scan locations for home/machine paths, bearer/API/private-key
patterns, UUIDs, transcript-bearing JSON keys and non-English artifact text.
No real home paths, credential-shaped secrets, real captures, non-English text or
tracked binary outputs were found. Reviewed UUIDs are the two invented fixture
identities; transcript-field matches contain `PRIVATE_MARKER`, invented ignored
text or synthetic account addresses. The documentation quota example uses a
redacted account marker and invented values, as its fixture notes declare.

`build/`, `.build/` and `.local/` are ignored, including the bundle, compiler
caches, fake transport and temporary validation code. `.gitignore` already covers
outputs, so no ignore change was needed. Package.swift contains only internal
core/executable/test targets and Apple frameworks; no third-party dependencies,
lockfile requirement or vendored upstream implementation was introduced. README
now describes implementation status, build/package/run, override isolation,
selection, offline/network behavior, executable verification, metric scope and
acceptance gaps. Research adds only newly verified compatibility evidence.
No LICENSE was invented; publication/license selection stays gated.

### Fresh checks and environment

Host: Apple Silicon macOS 27.0.1 (26A434), Apple Swift 6.4, active Xcode SDK 27.0.
Project-local CLANG_MODULE_CACHE_PATH and SWIFTPM_MODULECACHE_OVERRIDE were used,
with SwiftPM `--disable-sandbox`. The initial outer-sandbox test attempt built
but stalled in XCTest; the parallel release invocation waited for its SwiftPM
lock. Only those owned check processes were stopped, then checks were run
sequentially outside the outer sandbox. Neither stalled invocation is a pass.

| Check | Fresh result |
| --- | --- |
| `swift test --disable-sandbox` | PASS: 177 tests, 0 failures, 11.153 s (11.164 s whole suite) |
| `swift build -c release --disable-sandbox` | PASS: production build, 6.88 s |
| `scripts/package-app.sh --disable-sandbox`, plist/Mach-O inspection | PASS: packaged executable, valid plist; arm64 Mach-O with macOS 14.0 floor in plist and LC_BUILD_VERSION |
| Reader 10,000-request measurements | Replay 0.232 s; append 0.921 s; discovery 5.092 s; pending cancellation 0.000163 s; stop 0.000441 s. Reader goals met, not GUI timings. |
| `git diff --check` and independent review | PASS: no whitespace errors; one independent final review, no Critical/Important findings; one documentation Minor resolved |

Independent final review checked the documentation against production sources,
the approved Stage 6 scope, the ignored numeric harness and fresh build/test
results. It found no Critical/Important issues. The sole Minor was incomplete
README wording about persisted settings; it now explicitly lists local overrides,
session/bucket selection and offline preference. No product fix was necessary,
so no new regression tests or repeated live probes were added. There are no
deferred reviewer findings. Local links resolve and historical validation text
below is preserved verbatim.

### Dated A1–A13 evidence map

“Deterministic” means synthetic tests; “native” requires an actual GUI observation.
Earlier-stage records below retain their original dates and limitations.

| ID | Deterministic coverage retained in the fresh suite | Stage 6 live/native evidence and remaining gap |
| --- | --- | --- |
| A1 | SessionCatalogTests, SessionSelectionTests, PresentationStateTests: root precedence, missing/empty/unreadable roots, archives, children, concurrent candidates, manual pin/settings | Bounded real discovery and explicit synthetic launch overrides work; native selector/Settings and archived real sessions unverified |
| A2 | TokenUsageTests, RolloutDecoderTests, SessionReducerTests: 180/66.67%, subsets, optional/zero/invalid/overflow | One real native ledger count/totals/breakdown/cache comparison equal |
| A3 | SessionReducerTests, SessionReaderTests: replay, copies, moves, replacements, checkpoints, equal-value identities | No destructive live replay/archive manipulation; deterministic evidence only |
| A4 | ReconciliationTests, SessionReducerTests: conflicts, foreign ownership, baseline/reset/legacy transitions | One real reconciliation and reported cumulative comparison equal; adversarial live histories unverified |
| A5 | SessionReducerTests, PresentationStateTests: task/request distinction, interruption, missing start | No manufactured interruption; native detailed rows unverified |
| A6 | ToolAssociatorTests, RolloutDecoderTests: function/custom calls, duplicates, late/orphaned/concurrent boundaries | No tool-payload inspection or independent live tool attribution; native details unverified |
| A7 | ContextStateTests, PresentationStateTests: compaction/model/window invalidation and historical footprint | Exact current context unsupported; native labels unverified |
| A8 | QuotaModelsTests, QuotaProviderTests, PresentationStateTests: weekly-only, 5h + Weekly, multiple/alias buckets, duplicate slots, null/empty maps, unknown durations, seconds | One fresh real weekly-only shape matches normalization; native variants and real multiple/null-numeric variants unverified |
| A9 | QuotaRPCTests, QuotaProviderTests: timeout/auth/account generation, old replies, malformed/process exit, offline/wake/reset and startup hints | One passive quota full read after scheduled startup recovery; no induced auth/account/reset mutations, native offline interaction unverified |
| A10 | LineFramerTests, RolloutDecoderTests, SessionReaderTests: partial/malformed/unknown/oversized UTF-8, shrink/replacement/rewrite, sanitized diagnostics | Real source fingerprint grew with unchanged prefix; no raw capture retained; destructive live cases unverified |
| A11 | SessionReaderTests, ExecutableVersionTests, QuotaRPCTests, PresentationStateTests: append/discovery/10,000 requests, cancellation and owned shutdown | Fresh timing results above; synthetic process cleanup verified by signals; native responsiveness, GUI Quit and completed live append unverified |
| A12 | Synthetic privacy-marker tests plus repository scan/manual review | Bounded real numeric equality, fresh installed version/quota shape and hygiene checks pass within stated scope; not full application acceptance |
| A13 | PresentationStateTests: shared store/selection, quota independence, pinning, subscriber/provider reuse and shutdown races | No native shared-surface/focus/reopen/dismiss/Quit evidence; remains unverified |

No Stage 5 interactive checkbox is advanced. macOS 14 and Intel runtime support,
installation/distribution, signing/notarization, Windows/Linux, cross-process
notifications, real account-change acceptance and foreground detection remain
unverified or out of scope. Exact current context, exact fallback-model costs,
failed-response costs and family-wide totals remain unsupported. Stage 6 stops
at local review/commit; release/publication remain separate owner actions.

The following records are historical earlier-stage evidence.

## 2026-10-08 — Stage 5 implementation; native UI acceptance incomplete

**Latest status: Stages 1–4 implemented. Stage 5 code, deterministic tests and
packaging implemented; native interactive acceptance remains incomplete. Stage 6
has not started.**

Started `stage/5-native-ui` from clean local `main` at `3c92cd6`, after the owner
accepted and locally merged Stages 1–4. Fresh baseline: 155 tests passed. Local
commits only; no push, merge, installation, signing, publication or branch deletion.
The Stage 3 reducer optimization remains deferred. Source accounting and quota
allowlists, polling/backoff and process safety boundaries are unchanged.

### Deliverables

- `CodexSidecar` SwiftPM executable, Swift 6 / macOS 14 declared deployment floor,
  using SwiftUI, Foundation, AppKit lifecycle hooks and existing core providers.
  No third-party runtime dependencies.
- One application-level `@MainActor SidecarStore`, placed in SidecarCore so its
  presentation/lifecycle logic can be tested without SwiftUI. Injected catalog,
  reader, quota provider, settings persistence and asynchronous runtime factory.
  Store-owned subscriptions survive surface visibility changes; surface views
  issue commands and own no providers. Runtime replacement clears old metrics,
  selection and quotas immediately, serializes teardown and rejects old updates.
- Normalized `DerivedSession.owningThreadID` rejects buffered updates for a
  different selected chat, including empty/unavailable snapshots. This is the
  only change to the existing reducer; accounting/reconciliation is unchanged.
- `SidecarApp.swift`: one resizable `Window` with stable `companion` ID, 380×680
  default size, icon-only window-style `MenuBarExtra`, separate Settings scene.
  `openWindow(id:)` reuses/focuses that scene. Closing a window does not quit;
  explicit application termination awaits store shutdown. Workspace wake forwards
  to the same quota provider. No surface starts/stops providers.
- Shared manual Selected chat and limit-bucket selectors. Both surfaces show
  dynamic returned windows, source/freshness/error labels, local timezone resets,
  offline control, unavailable exact context, configured-model provenance,
  historical last footprint, observed response sum/cache rate and reconciliation.
  Unknown numbers are unavailable, retained failed quotas are visibly stale,
  weekly-only data has no 5h placeholder, duplicate slots remain separate.
  Disappearing saved buckets require explicit reselection with an unavailable label.
- Companion request pages contain at most 100 rows, with earlier/newer navigation.
  Disclosure details label cached/cache-write input and reasoning as included
  subsets; associated tool metadata states stream-order confidence, and task
  activity/unattributed calls never receive speculative individual token costs.
  Native controls, system appearance and selectable numeric text are implemented.
- Settings allow absolute root/executable overrides, shared selection and offline.
  UserDefaults holds only the allowlisted LocalSettings fields. No metrics,
  source content or account identifiers are persisted. Same resolved root is used
  by discovery, reader, executable version probe and quota process.
- Bounded cancellable `--version` verification for the chosen executable, retaining
  only its numeric version. Unknown versions remain explicitly unvalidated; the
  provider independently verifies supported handshake/read schemas. Failed
  version verification starts no quota transport. Offline starts no quota child.
- `Resources/Info.plist` and `scripts/package-app.sh`: release executable resolved
  with `swift build -c release --show-bin-path`, quoted paths, copies only the
  executable and plist to `build/Codex Sidecar.app/Contents/`. No installation,
  signing, quarantine changes or upload.

### Test-first and independent review

Initial presentation/integration tests were written before the new interfaces;
RED compilation confirmed the missing presentation/store APIs. GREEN established
scope/unknown values, shared selection, quotas independent of chat and pinned
selection. Subsequent behavioral RED → GREEN regressions reproduced:

- Offline changed during pending runtime creation was lost before provider start.
- Shutdown did not cancel pending runtime creation/version work.
- Missing pinned chat could remain Loading indefinitely.
- Startup could create subscriptions after shutdown during suspended offline
  setup; a later suspended subscription could finish after its initial stop.
- A saved bucket removed from a fresh quota snapshot remained an invalid selection
  and obscured current returned limits.

A fresh-context read-only reviewer examined `3c92cd6..658ad1a`, requirements,
providers, views, packaging and synthetic harnesses. No confirmed Critical or
Important production defect was reported; three findings were graded Minor:
startup after stop, indefinitely Loading missing selection, and removed bucket.
The missing-selection fix was already underway; the author treated unavailable
selection and the async lifecycle contract as required Stage 5 behavior and
reproduced/fixed all findings in one regression pass. An orphan in the real
catalog was not reproduced; late-start cleanup is also protected for injected
suspending providers. No second independent review is claimed. No findings remain
deferred. Reviewer declined native UI, older-platform and live-account judgments;
those remain unverified gates rather than presumed successes.

Additional actual owned-process tests verify root/argument propagation, sanitized
version retention, invalid output, cancellation of an unresponsive version child,
and explicitly unvalidated unknown-version labeling. A real temporary-file reader
with injected quota transport confirms offline local append, read-only source
bytes, shutdown and no running reader workers.

### Fresh deterministic/build evidence

Host: Apple Silicon macOS 27.0.1 (26A434), Apple Swift 6.4, active Xcode SDK 27.0.
The packaged arm64 executable's load commands and Info.plist declare macOS 14.0;
macOS 14 runtime and Intel are **not tested**. Context7 resolved Apple SwiftUI and
queried shared app state/Window/MenuBarExtra and Settings/accessibility APIs.

Commands used project-local compiler caches via `CLANG_MODULE_CACHE_PATH` and
`SWIFTPM_MODULECACHE_OVERRIDE`. SwiftPM `--disable-sandbox` was necessary because
nested `sandbox-exec` failed with `sandbox_apply: Operation not permitted`.
User-level SwiftPM cache warnings were environmental. Release dSYM generation
required a narrowly approved execution outside the sandbox after an initial
`Operation not permitted` failure. No tool installation or toolchain change.

| Check | Fresh result |
| --- | --- |
| `swift test --filter PresentationStateTests` | PASS: 19 tests, 0 failures |
| `swift test` | PASS: 177 tests, 0 failures (155 retained + 19 presentation/integration + 3 executable tests), 11.142 s |
| `swift build -c release` | PASS after regression fixes |
| `scripts/package-app.sh` and `plutil -lint` | PASS: release executable and valid plist in the local bundle |
| Synthetic 10,000-request replay/stat checks | PASS: replay 0.221 s; append 0.976 s; discovery 5.104 s; pending cancel 0.0022 s; reader stop 0.00043 s. These are reader measurements, not native UI timings. |
| `git diff --check` | PASS |

### Native launch evidence and exact limitation

The bundle executable exists, is executable and is arm64 Mach-O. Sandboxed
LaunchServices returned `kLSNoExecutableErr` (-10827) despite that file existing;
direct sandboxed AppKit execution exited 134. A narrowly approved LaunchServices
launch outside the sandbox succeeded using explicit test-owned root and executable
arguments plus `--isolated-settings` (no settings persistence). The selected
fake executable reported `0.0.0-synthetic`; no historical real CLI version was
used to certify it. Its stdio method log contained only initialize, initialized,
account/read and account/rateLimits/read. Synthetic session fingerprints remained
unchanged. The test processes were then stopped and their absence checked.

**Native computer-use channel failure:** both attempted UI bindings returned
`Sky Computer Use native pipe closed before response`. No screenshots or native
accessibility tree were obtained. Therefore default/resized layout, long-label
rendering, selectable numbers, keyboard navigation/accessibility, panel variants,
selection from actual surfaces, focus/reuse, panel/window close-reopen behavior,
native append visibility, offline interaction and explicit GUI Quit are
**not verified**. Process launch and deterministic store tests do not satisfy
those interactive acceptance steps. Cleanup used process signals for the known
owned test processes; it is not evidence for the GUI Quit action.

**Acceptance incident:** the first failed UI binding implicitly launched an extra
Sidecar instance without synthetic arguments. That instance used default-root
catalog discovery and started an owned real Codex quota child. This violated the
requested synthetic-only GUI boundary. No resulting session/account values or
source contents were inspected, copied or retained in the repository, and no
inference/chat mutations were requested. That Sidecar instance and its identified
direct quota child were stopped; their absence was checked. Passive reads and
Codex-managed housekeeping during that unintended interval were not audited;
this incident is not a successful live acceptance or a read-only fingerprint
certification of real Codex state. Subsequent launch used explicit synthetic
arguments only. After discovering the incident, no further UI binding was
attempted.

### Stage 5 acceptance coverage

| ID | Evidence and remaining boundary |
| --- | --- |
| A1 | Existing synthetic discovery/root/archive/provenance tests retained. Store tests add empty/no-root state, missing pinned chat, settings replacement and same-root executable/provider construction. Native Settings interaction unverified. |
| A5 | Interruption without completed usage remains unavailable, task activity displays usage-not-reported, completed requests stay distinct from tasks; retained reducer fixtures. |
| A6 | Details render included subsets and stream-order confidence; unattributed tools remain separate task activity. Existing associator regressions retained; native disclosure/long-tool layout unverified. |
| A7 | Presentation tests preserve configured-model-only state, historical footprint and unavailable exact current usage/window. No Actual model/current-occupancy claim. Existing context invalidation regressions retained. |
| A8 | Weekly-only, duplicate durations, unknown/null percentages, independent bucket choice and disappeared selection tested. Existing multiple-bucket/5h-plus-Weekly mapping tests retained. Actual menu-bar panel variants unverified. |
| A9 | Retained stale/error quota presentation, offline during start and independent local updates tested; existing deterministic quota auth/generation/wake/reset/retry/timeout/process cases retained. Historical Stage 4 live capability check below remains dated separate evidence, not GUI acceptance. |
| A11 | Real synthetic append/read-only/shutdown and fresh 10,000-request reader measurements pass. Provider/version child cleanup verified deterministically. Native responsiveness, visible latency and GUI Quit unverified. |
| A13 | One store owns subscribers; repeated start has one provider start/reader subscription; shared command changes A/B metrics while quotas stay fixed; late A rejected; settings/shutdown races covered. Native focus/reopen/shared-surface interactions remain unverified. |

Only Stage 5 status/checklists advanced. Steps 4–5 remain open for native interactive
acceptance. Stage 6, real installed-session validation and publication are outside
this task. Exact current context remains unavailable; cross-process notifications,
account-change coverage, macOS 14 and Intel runtime behavior remain unverified.


## 2026-10-08 — Stage 4 implementation

**Status at the end of Stage 4: Stages 1–4 implemented. Stages 5–6 had not started.**

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
