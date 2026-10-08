# Codex Sidecar Specification

Date: **2026-10-07** (approved product specification). The owner approved macOS
as the first-release platform and Swift/SwiftUI as the stack. Stages 1–5 are now
implemented; Stage 6 validation is recorded in [docs/validation.md](docs/validation.md).
Native interactive acceptance remains incomplete. Product requirements below are
unchanged; the original research session preceded implementation.

Evidence: [research findings](docs/research.md). Execution:
[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md). Where starter notes differ,
this specification takes precedence over their unverified examples.

## 1. Problem, user, and success

Codex users need a compact view of account quotas and the usage of a selected
conversation while work continues. Account limits, context information, task
lifecycle, completed model responses, and tool activity have different scopes.
Combining them without those distinctions produces misleading numbers.

The initial user is a macOS Codex desktop user with local rollout files and an
installed Codex executable. Sidecar is a passive local companion with a menu-bar
panel and a small independent window sharing one selected chat. Success means
source-backed metrics update without duplicate
accounting, missing data stays visibly unknown, and conversation contents remain
local and unretained by Sidecar.

### MVP scope

- Discover sessions under a configurable Codex home and select one manually.
- Open a compact panel from the macOS menu bar and a separate companion window;
  both provide chat selection and share the same state and providers.
- Suggest recently active root sessions, explicitly as a heuristic.
- Show observed completed-response token totals and cache hit rate.
- Show a completed model-request timeline, configured model when known, breakdown,
  and tool activity associated by validated stream order.
- Display advertised context window and last-request footprint separately from
  unavailable exact current context.
- Read account quotas using a separate local stdio app-server provider, with
  missing, stale, offline, authentication, and error states.
- Follow append activity, recover from missed events/restarts/replacements, and
  tolerate unknown future event types.

### Non-goals

No model inference, chat management, login/logout/reset redemption, Codex patching,
Accessibility/screen inspection, overlays, cloud sync/backend/telemetry, copied
credentials, direct private quota HTTP, database, transcript viewer, cost pricing,
notifications, autostart, historical analytics, exports, or
Windows/Linux support. Do not invent costs for individual tools or parse nested
orchestration arguments to classify reads/searches. No automatic publication.

All repository documentation, product UI, code names/comments, tests, and public
artifacts are in **English**. Collaboration with the project owner is in Russian.

## 2. Compatibility and sources

Initial verified source profile: **Codex CLI 0.160.1** bundled with desktop version
26.930.61225/build 13232, on Apple Silicon macOS 27.0.1. Logs with 0.160.0 headers
were also sampled but are not an independently certified compatibility target.
JSONL rollout events are internal, version-sensitive data. App-server tooling is
experimental; validate capabilities rather than silently accepting every version.

| Source | Used for | Required limitations |
| --- | --- | --- |
| `sessions/**/*.jsonl`, optional `archived_sessions/**/*.jsonl` | Session identity, owned response ledger, task lifecycle, tool metadata, configured model and window snapshots | Read-only; bounded selective decode; do not retain transcript payloads |
| Optional `session_index.jsonl` | Stored chat title and recency, joined only to discovered session IDs | Read-only, bounded and memory-only; unavailable or invalid entries use identity fallback; no transcript title inference |
| `token_usage_record` | One completed response and task/thread cumulative reconciliation | Best-effort completed usage, not all attempted inference |
| `event_msg/token_count` | Snapshot diagnostics/window; conservative legacy aggregate | Never another native request; display totals can be overridden |
| `codex app-server` via stdio | Account status and quotas | Own process only; does not follow desktop threads automatically |
| Local settings | Data-root/executable override and selection | No credentials or raw source/log payloads |

Root precedence: explicit Sidecar override → inherited `CODEX_HOME` → dynamic
user-home `.codex`. A GUI launch may not inherit the user's shell environment;
show the chosen root in local settings and allow correction. Do not parse
arbitrary configuration commands to infer it. Executable precedence: explicit
user-selected executable → safe PATH discovery → recognized installed application
bundle candidates, verified with `--version`. Never run through an interpolated
shell command. Use the same chosen root for log discovery and quota process.

Sidecar must report unreadable/missing roots and executables rather than request
broader filesystem or Accessibility access automatically. A successful quota
read belongs to the current Codex account, not inherently to an old selected
session. Display “Current account limits”; do not assert that a historical or
foreign session belongs to that account.

Unknown CLI versions may expose compatible capabilities. Show an unvalidated
compatibility label and permit verified aggregate data only where its schema is
valid. Never enable exact request accounting without valid ownership and native
response IDs. Absence of a metric is supported behavior.

## 3. Terminology and internal boundaries

- **Thread / logical session:** conversation identity from the owning initial
  `session_meta.id`. Multiple files/copies can describe the same logical session.
- **Runtime session ID:** `token_usage_record.session_id`; provenance, not a
  substitute for the owning thread and not assumed constant across every resume.
- **Task turn:** `task_started.turn_id` / app-server task turn. Can include several
  model requests, tool waits, interruptions, and continuation behavior. A user
  message is an input interaction, not necessarily a task/request boundary.
- **Model request / model turn:** one inference cycle. MVP can observe its usage
  only when a valid native completed-response usage record is written. Prefer the
  UI label **Model requests** to avoid confusion with task turns.
- **Owned request:** native record whose `thread_id` equals the selected owning
  thread. Foreign inherited records are excluded from own totals.
- **Counter epoch:** contiguous comparable snapshot/ledger segment, separated by
  reset, conflict, history rewrite, or an unresolvable continuity boundary.
- **Observed usage:** sum of valid unique owned completed-response records present
  in the inspected files. It is not an account invoice or guaranteed lifetime
  total when history is missing.

Normalized state must keep identity/provenance and numeric availability separate.
Use checked signed 64-bit integers for token counters, reject negatives/overflow,
and preserve missing fields as missing. No conversion from null to zero.

A normalized response contains key, timestamp, task ID, runtime session ID,
usage, configured-model label/provenance, association confidence, and minimal
related tool metadata. A snapshot contains cumulative/last usage, window, source
location/order, and receipt/source time; it never directly creates a native row.

## 4. Token accounting and reconciliation

### 4.1 Primary ledger

1. Validate the initial session header; do not switch file ownership when an
   inherited header appears later. Reject an unidentifiable file for exact metrics.
2. Accept `token_usage_record` only with nonempty response/thread/task identities,
   owning-thread match, valid counters, and valid envelope structure.
3. Deduplication key is **(owning thread ID, response ID)** across file copies,
   rereads, archive moves, and resumes. Runtime session ID is retained as provenance.
4. Identical duplicates are ignored for accounting. Conflicting values for one
   key quarantine that request from trusted observed totals, preserve a sanitized
   diagnostic, and mark completeness degraded. Do not choose the latest value
   merely because it appears later.
5. Two different response IDs with equal token values count twice. Timestamp,
   task ID, byte offset, and value equality are not response identities.
6. Sum `usage` of valid unique owned responses once. Never also add
   `turn_token_usage`, `thread_token_usage`, or token-count mirrors.
7. Task/stream ordering comes from file order, with timestamps displayed but not
   used to reorder the stream; clocks may be equal or out of order. Conflicting
   copies invalidate associations that cannot be reconciled.

The ledger reports completed Responses usage. If interruption/error occurs
without a valid record, show “Usage not reported” for the affected task/activity;
no zero-cost request row. A valid zero-usage native response remains a response
with zero usage. Do not fabricate started-request counts from tools or reasoning.

### 4.2 Subsets and formulas

Preserve `input_tokens`, `cached_input_tokens`, `cache_write_input_tokens` when
present, `output_tokens`, `reasoning_output_tokens`, and `total_tokens`.

- Cached input is included in input. Reasoning output is included in output.
- The tested profile has `total = input + output`; preserve explicit total and
  mark a mismatch as incompatible/inconsistent, not silently recomputed.
- Do not add cache-read, cache-write, or reasoning fields again to total.
- Validate cached input ≤ input and reasoning output ≤ output. Preserve missing
  subset values as unavailable; partial records may support total only.
- Cache hit rate = 100 × sum(cached input) / sum(input) over the **same** validated
  set of records. If input is zero or any required subset is unknown, show
  unavailable; never average per-request percentages.
- Optional uncached input = input − cached input, only when both fields are valid.

Observed session totals and cache rate must state their scope. Records with valid
identity/total but missing breakdown can contribute to observed total while
making the corresponding aggregate breakdown/cache rate unavailable. Negative,
overflow, contradictory totals or subset bounds quarantine the record. Never
silently present a partial breakdown sum as complete.

### 4.3 Reconciliation

Maintain **observed response sum** and **reported thread cumulative** separately.
Within a continuous owned-ledger epoch:

- Infer baseline from first cumulative snapshot minus its own usage, component by
  component, only if comparable fields are present and all differences nonnegative.
- Compare each later cumulative snapshot with baseline plus unique owned usage.
- A zero baseline and matching full coverage permit “Reconciled observed usage”.
- A positive baseline indicates earlier/inherited/unobserved usage; label “Partial
  history” and display the reported cumulative separately, without adding baseline
  to observed usage.
- Missing history, cumulative decrease, field disagreement, conflicting response
  identity, or ownership ambiguity must downgrade reconciliation. Preserve verified
  rows but never invent a balancing request or assign a gap to an arbitrary task.
- Task cumulative values may corroborate grouping; do not sum them across snapshots.

`compacted.latest_token_usage_record` is a checkpoint. It may corroborate/seed a
reported baseline, but does not create a billable row. If a compaction response
is separately present as a native owned record, count it once. Its exact actual
model may be unknown. Do not traverse `replacement_history` for metrics.

### 4.4 Legacy snapshots

Without a usable native ledger, exact model-request timeline is **Unavailable**.
Show the latest valid `token_count` cumulative snapshot as **Reported snapshot
usage — unverified lifetime scope**, separately from observed response totals.
Repeated snapshot tuples add nothing. Do not sum positive-clamped deltas across
resets, or convert a context-full synthetic last delta into a request.

For files that transition from legacy to native records, native observed usage
covers the native portion only. Legacy state may explain an earlier baseline but
is never added to native totals automatically. Preserve the partial-history label.

### 4.5 Parent/child, resume and replacement

No family-wide totals in MVP. Parent/child and fork metadata appear in selection
only. Exclude records belonging to other thread IDs even if copied into the file.
Do not assume cumulative child totals exclude inherited parent usage.

Restart rebuilds from original files; no persistent metrics database. Resume uses
existing response identity and baseline. Truncation/replacement rebuilds the file
contribution rather than adding a new epoch total to old state. An archive move
or duplicate source copy must not double-count. If originals disappear, expose
source-unavailable state; do not claim durable historical coverage.

## 5. Context and configured model

Exact **Current context usage** is unavailable for the validated metrics-only
profile. A future exact source may be added only after its scope and post-tool,
post-compaction, model-change and reset semantics are demonstrated.

Display independently:

- **Model context window:** positive source `model_context_window`, tied to its
  task/model context. Never hard-code 258,400 or a public advertised model maximum.
- **Last request footprint:** latest valid owned native request `total_tokens`
  (input + output in the validated profile), with timestamp and label. Optional
  footprint/window ratio is explicitly last-request, not current context.
- **Configured model:** latest valid `turn_context.model` for that task. Do not
  relabel it “Actual model”: fallback/compaction can use another model.

After compaction, model/window change, interruption, or file replacement, previous
context-related values are stale/historical until fresh matching evidence arrives.
A new model context with no positive window makes the current window unavailable;
never carry a prior model's capacity forward. No reserved-baseline percentage
matching the desktop UI is claimed.

## 6. Quota provider

### Protocol and safety boundary

Own one stdio app-server process, with Codex home explicitly resolved and analytics
disabled using a process-only configuration override. Never attach to, patch,
stop, or proxy the desktop's process. Use Foundation Process with an argument
array and asynchronously drained stdout/stderr; never retain raw stderr/stdout
payloads in diagnostics.

Allow only initialize, initialized, `account/read` with `refreshToken: false`, and
`account/rateLimits/read` with `excludeResetCreditDetails: true` for background
reads; omit `supportsLunaReserve` because Sidecar provides no automatic fallback
capability. Recognize `account/rateLimits/updated` and
`account/updated`; ignore other notifications. No thread start/resume/list-content,
turn start, logout, auth-token export, resets, credits actions, or approval RPCs.
For unexpected server requests, return a sanitized unsupported-method response;
do not open browsers or perform login/attestation actions automatically.

Use the generated 0.160.1 protocol as the initial handshake reference. CLI missing,
unsupported protocol, auth absent/API-key-only, process exit, timeout, malformed
reply, and network failure are distinct unavailable/error reasons. Do not copy or
read `auth.json`; Codex owns its normal authentication/refresh behavior.

### Dynamic bucket/window model

Account quotas are a dynamic collection, never a required `fiveHourLimit +
weeklyLimit` pair. The 2026-10-07 follow-up read of CLI 0.160.1 returned one `codex`
bucket with weekly primary (10,080 minutes), null secondary, and no additional or
model-specific buckets. This is a dated observation, not a permanent entitlement.
See [installed raw shape and probe](docs/research.md#31-dynamic-window-recheck-and-installed-raw-shape)
and [sanitized documentation fixture](docs/fixtures/rate-limits-read.sanitized.json).

Normalized model:

```text
RateLimitBucket
  id
  name?                 # wire limitName
  normalModelSlug?      # alias metadata, not assumed actual request model
  windows[]             # each keeps sourceSlot: primary or secondary

RateLimitWindow
  sourceSlot
  usedPercent?
  durationMinutes?      # wire windowDurationMins
  resetAt?              # wire resetsAt, Unix seconds
```

The installed wire uses `primary`/`secondary`, `usedPercent`,
`windowDurationMins`, `resetsAt`; backend `primary_window`, `limit_window_seconds`
and `reset_after_seconds` are not alternative app-server fields to guess. Future
schema adapters require validation before changing units or names. Credits and
spend-control metadata are separate capabilities, not time-window replacements.

### Window mapping

Prefer `rateLimitsByLimitId` when a map is returned, including an empty map. Only
absent/null map falls back to the legacy view. Keep opaque bucket identity and
optional label. Default focus is `codex` if available; otherwise require an
explicit bucket selection. Never select a bucket by percentage or merge windows
from different buckets into one allowance.

Preserve slot identity within each bucket. Label by duration: 300 minutes = **5h**;
10,080 minutes = **Weekly**; other durations are shown literally. If two slots
share a duration, retain both with distinct labels instead of collapsing them.
Missing duration produces **Unknown window**; never infer duration from slot.
Render only returned windows. Do not reserve mandatory 5h/Weekly rows or treat
the absence of either as provider failure. An optional diagnostic can explain
that a duration was not returned; no synthetic allowance is created.

`usedPercent` finite numeric value → remaining = clamp(100 − used, 0, 100).
Retain source used value for validation; out-of-range values show a warning while
the display remains clamped. Missing/malformed percentage is unavailable.
`resetsAt` is Unix seconds, rendered in user-local time with timezone and optional
countdown. A missing reset does not suppress an otherwise valid percent. Past
reset triggers refresh and an awaiting-refresh label, never an assumed reset to
zero used. Nullable permission fields never become a promise of availability.

### Refresh and freshness

Refresh on provider start, explicit Refresh, and wake. Poll every **60 seconds**
while the app is running, single-flight. `account/rateLimits/updated` contains one sparse bucket, not the authoritative
multi-bucket map. Treat it as a refresh hint, coalesced into the next eligible
single-flight scheduled read; do not erase cached buckets/metadata from nullable
notification fields or mark unrelated buckets fresh. A successful full read may
replace the map and remove absent windows. Notifications do not replace polling
and need not observe another process's desktop activity. Request timeout:
**20 seconds**. Retry after transient failures at 60, 120, then 300 seconds; cap
at 300 seconds. An explicit refresh may bypass backoff but never run concurrently.
No rapid quota polling loop and no model request to activate an absent window.

Successful read is stamped with receipt time and account generation. Values are
stale after **120 seconds**, immediately on wake pending refresh, after reset
passes, or on known account change. On transient failure retain last good values
with stale/error state. Auth loss or account change clears old account values;
an in-flight response from a prior account generation is discarded. No raw
account identifier needs to be persisted or shown. Codex notifications do not
prove cross-process auth-change coverage; fresh polling/account status is needed.

Metric states: **Loading**, **Available**, **Unavailable(reason)**,
**Stale(last good value, time, reason)**, **Error(reason, optional last good
value)**. Null data is never zero. Quota freshness is independent from session
activity. Offline mode disables this provider and all Sidecar-initiated network
activity while preserving local session parsing.

## 7. Discovery and incremental reading

List regular JSONL files inside the selected roots; skip symlinks and external
paths. Read bounded headers/tails for session candidates; do not parse every
session's body at launch. Root sessions come before child agents; list child
provenance without auto-aggregating. Within each root/child group, order by newest
known activity (maximum source modification time and valid indexed `updated_at`),
then stable session identity for ties. This is a recency heuristic, not foreground
chat detection. Use project basename and an optional stored `thread_name` joined
by session ID from the selected root's `session_index.jsonl`; never derive a title
from transcript or prompt text. Missing/invalid metadata falls back to a short,
distinguishable identity. Duplicate names within a project add an identity suffix.
Selector dates use local `dd.MM HH:mm`, adding `.yy` for a different local year;
full date/seconds/time zone remain in selected chat details.
The optional index uses bounded reads (16 MiB total, 4 KiB title), skips malformed
complete entries and ignores an incomplete tail. Over-limit/unavailable/symlink
indexes fall back without hiding discovered chats. Most recent valid timestamp
wins repeated entries; equal timestamps use the last complete valid entry.

After manual selection, keep that session pinned until changed. An optional
“Recent activity” suggestion may use timestamp/task evidence; it must not switch
a pinned selection or claim to be the foreground chat. Equal/concurrent recent
candidates remain visible for manual choice. The UI always states selection mode.

For selected sources, maintain file identity, byte offset, incomplete byte buffer,
and parser state. Read bounded chunks off the main thread; split on newline
before UTF-8/JSON decode. Buffer partial lines, including split multibyte text.
Skip a malformed complete line with a sanitized diagnostic and continue. Tolerate
unknown fields/events without retaining their contents. Do not parse an unfinished
last line on EOF as complete.

Use filesystem signals as hints plus a **1-second selected-file stat check** and
**5-second directory reconciliation** to recover missed events. Detect shrink,
inode/file-identity replacement, equal-size replacement through metadata/prefix
checks, and archive moves; rebuild rather than append old state. Identity/cursor
changes are never treated as new token usage automatically.

Resource boundaries: read chunks up to 64 KiB, maximum buffered line 8 MiB, at
most 100 request rows rendered at once with earlier rows loadable. Oversized lines
are skipped to their newline without saving raw data and mark coverage degraded.
Account arithmetic overflow fails closed. No timer/file scan on the main UI
thread. Performance goals: appended complete records visible within 2 seconds
at idle host load; new sessions discoverable within 6 seconds. Verify with
synthetic 10,000-request streams; report degraded performance explicitly if unmet.

## 8. Minimal UI and privacy

Two native surfaces share one application-level store:

- A persistent macOS menu-bar icon opens a compact panel using
  `MenuBarExtra` with `.window` style. Use the icon alone in MVP; a menu-bar
  percentage is optional future scope, not a mandatory single-window summary.
  The panel shows current account limits, a **Selected chat** selector,
  configured model, observed tokens, cache hit rate, and context availability.
  **Open window** opens or focuses the existing companion window with the same
  selected chat. Refresh and Settings remain accessible from the panel.
- One native resizable companion window, approximately 380 × 680 points
  initially, with scrolling for its longer request list. It provides the same
  **Selected chat** selector and detailed breakdown/request views below.

Selection in either surface updates both. Selecting a chat changes session
metrics and requests, not current-account quota values. The UI lists local chat
descriptors from project basename, optional stored chat title, last activity and
root/child identity; do not read prompt text to reproduce chat titles.
Manual selection remains pinned when another desktop chat becomes active.

Companion content:

1. Selected chat selector, selected project/session, selection mode, last activity.
2. Current account limits with a dynamic list of buckets and returned windows,
   reset/freshness state, Refresh and offline setting.
3. Context: exact current usage unavailable, advertised window, last request
   footprint with timestamp; configured-model provenance.
4. Observed session tokens and breakdown, cache rate, reconciliation/partial-history
   label; reported cumulative is secondary detail.
5. Recent model requests, timestamp and total; selection reveals breakdown and
   order-associated tool names/counts/status, with unattributed task activity.

Both surfaces render all returned windows for the chosen bucket; a 300-minute
window appears as 5h whenever returned, alongside Weekly if present. Weekly-only
accounts have no mandatory 5h placeholder. Availability/freshness labels remain
visible in the compact panel as well as the window.

Opening/closing the panel or companion window does not restart providers or clear
selection. Closing the companion leaves the application available from the menu
bar. Explicit Quit cancels subscriptions/readers and stops only the owned quota
child. Use one reader and one quota provider across both surfaces. Closing a UI
surface does not disable scheduled quota refresh while the application is running.
Autostart and custom Dock visibility behavior are outside MVP.

Use selectable numeric text and standard accessible native controls. No elaborate
charts, hidden transcript expansion, live final-answer previews, or speculative
“expensive prompt” feedback. Local settings allow home/executable override and
selection without embedding implementation details into the primary view.

Raw bytes exist only transiently for parsing; normalized state retains numeric
metrics, opaque identities, local source cursor, project basename, optional stored
chat title, public tool
name/call ID, and lifecycle times. Never persist prompts/messages/reasoning,
arguments/output, raw JSON, credentials, source contents, or account IDs. Do not
retain full unknown events. UserDefaults may hold local overrides and selection;
no derived transcript/metrics cache. Diagnostics contain category, line/offset,
and count only, excluding raw payloads, stderr text, and full private paths.

Quotas can cause Codex-managed OpenAI traffic, including normal credential
refresh. Sidecar has no HTTP client for transcripts, telemetry, private quota
endpoints, third-party pricing, or updates. Offline mode starts no quota child.
Do not promise that the separately installed Codex runtime itself has no internal
logging/housekeeping behavior.

## 9. Synthetic examples and acceptance

These values/identities are invented; they are not copied from local sessions.
Native accounting fields are illustrated without transcript fields:

```json
{"timestamp":"2026-01-01T12:00:01Z","type":"token_usage_record","payload":{"thread_id":"11111111-1111-4111-8111-111111111111","session_id":"11111111-1111-4111-8111-111111111111","turn_id":"task-a","root_turn_id":"task-a","response_id":"response-a","usage":{"input_tokens":100,"cached_input_tokens":60,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120},"turn_token_usage":{"input_tokens":100,"cached_input_tokens":60,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120},"thread_token_usage":{"input_tokens":100,"cached_input_tokens":60,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120}}}
```

A second unique response in the same task with input 50, cached 40, output 10,
reasoning 2, total 60 produces observed total **180**, input **150**, cached **100**,
output **30**, reasoning **7**, cache hit **66.67%**, two requests and one task.
A repeated record/snapshot/checkpoint leaves those numbers unchanged. Two distinct
IDs both carrying the first usage produce 240, not 120.

| ID | Acceptance criterion / meaningful scenario |
| --- | --- |
| A1 | Header/root selection works with default/custom home, empty/unreadable directories, archived files, children and ambiguous concurrent roots |
| A2 | Above synthetic accounting yields 180 and 66.67%; subsets are not added again; partial/zero/negative/overflow cases remain explicit |
| A3 | Replay, duplicate files, archive moves, repeated snapshots, repeated checkpoint and equal-valued distinct requests are idempotent |
| A4 | Identity conflicts, foreign inherited records, positive baseline, cumulative reset and legacy/native transition never manufacture complete history |
| A5 | One task with several requests remains distinct; interrupted task without usage is unknown; missing task start is diagnosed without losing a valid owned response |
| A6 | Function/custom tool and output deduplicate by call ID; late outputs, orphaned calls, concurrent segments and task boundaries preserve ambiguity; inner commands are not parsed |
| A7 | Compaction/window/model changes invalidate stale context; exact current context is unavailable; footprint is never displayed as current occupancy |
| A8 | Weekly-only primary maps correctly without a 5h placeholder; a returned 300-minute window appears as 5h alongside Weekly when both exist; multiple buckets/model-alias metadata/duplicate durations/null map/empty map/unknown duration and reset seconds behave as specified; sparse updates do not remove unrelated buckets or null out full-read metadata |
| A9 | Quota timeout/auth loss/account change/late old response/malformed reply/process exit/offline/wake/past reset have deterministic state; no inference or auth mutations occur |
| A10 | Partial/malformed/unknown/oversized lines, split UTF-8, truncation and equal-size replacement recover without transcript diagnostics or duplicate totals |
| A11 | Synthetic append/discovery latency targets hold, UI stays responsive, restart rebuild matches one-pass parse; provider workers stop cleanly on exit |
| A12 | Real read-only acceptance on installed profile matches manually extracted numeric ledger counters; no raw files enter repository, privacy scan and English-only artifact review pass |
| A13 | Both surfaces select the same chat and update its metrics/requests; account quotas remain independent of chat selection; opening/focusing/closing UI surfaces preserves selection and creates no duplicate provider; explicit Quit stops owned workers |

Tests must be synthetic, deterministic, and independent of live account/network
availability. Live acceptance is bounded numeric comparison, not destructive edge
case generation in user chats.

## 10. Architecture and technology decision

**Owner-approved stack:** Swift 6, macOS 14+, SwiftUI, Foundation, XCTest, SwiftPM;
no third-party runtime dependencies and no database. Native macOS-only scope
requires one language/runtime, and the installed Swift toolchain supports a
reasonable first build path. Command Line Tools build feasibility and packaging
remain implementation gates. Do not claim macOS 14 or Intel support is tested.

Components: selective rollout decoder → pure owned-ledger reducer → incremental
selected-file reader/discovery → presentation state. A separate stdio quota
client emits quota state. SwiftUI reads immutable snapshots published on the main
actor; file/RPC processing stays off it. Local settings hold only overrides and
selection. No UI view performs counter arithmetic.

Tauri 2 is viable and used by audited projects, with Rust plus frontend tooling
and IPC. Its cross-platform benefit is outside MVP; extra build/dependency layers
are not justified for this small native window. No measured performance advantage
is claimed. Reconsider only if Swift build/packaging is blocked or cross-platform
scope is explicitly authorized.

**Platform decision (2026-10-07):** Ship macOS first. Windows is a possible later
phase with no release commitment. The owner has no Windows test environment;
automated builds/tests alone are not sufficient product acceptance for installation,
tray behavior, real Codex auth/limits, file discovery and WSL setups. Reconsider
Windows when user demand and a tester or accessible Windows environment exist.
Keep accounting and providers separate from SwiftUI, but do not claim automatic
portability: a Windows version needs another UI and adaptation of platform code.

## 11. Open questions and gates

| Question / limitation | Decision and dependent-work gate |
| --- | --- |
| Exact current context? | Unavailable in MVP. Block any feature claiming live occupancy until a validated passive source exists |
| Follow foreground desktop chat? | Manual selection; heuristic suggestions only. Block automatic foreground-follow claim without public cross-process evidence |
| Account has no 5h window? | Expected unavailable state; do not run inference to create it |
| All failed/interrupted requests counted? | No; count observed completed records only and label missing usage |
| Actual model through compaction/fallback? | Configured-model provenance only; block exact per-model accounting claims without actual request model source |
| Parent/fork totals globally independent? | Unproven; block family-wide totals, preserve ownership/baselines |
| CLI 0.160.1 shipped source exactly identical? | Schema/local observations support profile; keep version capability checks and unknown-version state |
| SwiftPM build and `.app` packaging with installed tools? | Validate core in stage 1 and packaging in stage 5 before dependent deliverables; no tool installation in research session |
| Older macOS and Intel? | Product floor macOS 14+, untested platforms clearly stated until exercised |
| Public project license? | No copied code; own license must be explicitly chosen before publication, which is separately authorized |

This specification intentionally narrows unavailable metrics rather than blocking
the useful local completed-response companion. The original first session included
no application code, dependency installation, packaging, inference or publishing. Current implementation and
validation status is recorded separately above.
