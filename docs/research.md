# Codex Sidecar Research

Research date: **2026-10-07**, with a bounded installed-profile recheck on
**2026-10-08**. The first-session investigation is historical; Stages 1–5 are now
implemented. Stage 6 is complete in the owner-approved current-Mac scope (see
[validation](validation.md)). This document supersedes the original
research backlog. The [README](../README.md) describes the current product;
[validation](validation.md) records acceptance evidence and remaining limitations.

## Method and evidence boundaries

The starter packet was read in full: README, idea, research, MVP, architecture,
START_PROMPT, and `.gitignore`. Its technical claims were treated as hypotheses.
Investigation proceeded through installation, session logs, quotas, and public
projects, in that order, before the specification and plan were written.

- **Observed:** read-only installation/configuration checks, generated protocol
  definitions, and bounded schema/counter inspection of recent local logs.
- **Source verified:** public OpenAI source at the release tag matching the local
  CLI, official documentation, and selected files of pinned public projects.
- **Inference:** design recommendations based on those observations.
- **Unverified:** behaviors not established by the bounded sample or inspected
  sources. These are explicitly restricted in the specification.

Only schemas, numeric invariants, versions, and sanitized probe results were
retained here. Real prompts, source code, tool arguments/output, credentials,
account identifiers, session identifiers, filenames, and transcripts were not
copied into this repository. Examples below are invented. No third-party code was
copied into the project. Public source inspection took place in temporary storage.
No model inference, thread resume/fork/modification, login/logout, or settings
change was requested by the research probe. The probe started and terminated its
own app-server; normal Codex runtime housekeeping was not audited for byte-level
changes to its internal state. Source files were never edited.

## 1. Installed environment

| Item | Verified finding | Consequence |
| --- | --- | --- |
| Host | Apple Silicon, macOS 27.0.1 | Initial development/acceptance platform only; older macOS remains untested |
| Desktop distribution | ChatGPT application bundle, version 26.930.61225, build 13232 | Do not assume a separately installed `Codex.app` |
| CLI | Bundled `codex-cli 0.160.1`, found through executable discovery | Provider must resolve/configure its executable, not embed this machine's path |
| Local root | Shell `CODEX_HOME` unset; default `~/.codex` exists and contains recent desktop logs | Respect custom home and a manual root override; shell environment does not prove every desktop launch environment |
| Sessions | 517 JSONL files discovered at inspection; no `archived_sessions` directory | Discovery is required; avoid reading all transcript contents at startup |
| Configuration | `config.toml` exists; selected model is `gpt-6.1-sol`; no inspected context-window override | Configured model is not proof of the model used for every response |
| Swift | Swift 6.4 and Command Line Tools present | Native development is plausible without installing another runtime |
| Xcode | Active developer directory is Command Line Tools; `xcodebuild -version` cannot run there | Plan a SwiftPM build first; full Xcode/signing/distribution are separate checks |
| Workspace | Starter documents only; no Git repository | No commits, branches, pushes, or publishing were performed |

Read configuration selectively; never dump notification commands, MCP settings,
project lists, authentication files, or process environments. `CODEX_HOME` and
configuration support are documented in the [official configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).

The CLI successfully generated JSON Schema and TypeScript protocol definitions
into temporary directories with `app-server generate-json-schema` and
`app-server generate-ts`. CLI help marks app-server tooling experimental.
Generation establishes the installed wire schema, not a public stability promise
for JSONL rollout internals.

The matching public tag is `rust-v0.160.1`, resolving to commit
**`d27764b82f7118f674371e6d6e76271d9d606edb`**. This release source is the primary
semantic reference; a locally bundled binary may contain packaging differences.
Local observations support the relevant fields, but binary/source equivalence
was not proven beyond version/schema comparisons.

## 2. Session log schemas and accounting

Recent samples included headers reporting CLI 0.160.1 and 0.160.0, desktop origin,
a root conversation, and a child agent. Initial inspection was bounded to three
files and at most 2,000 records per file; focused validation used two samples of
at most 2,500 records. Live append activity means these are observations, not a
frozen transcript export. Older-version compatibility is not established.

### Verified event map

| Envelope / payload | Fields relevant to Sidecar | Established meaning / limits |
| --- | --- | --- |
| `session_meta` | `id`, `session_id`, `cli_version`, `cwd`, `source`, optional `parent_thread_id`, `context_window` | Logical identity, version, provenance, local project selection metadata; ignore instruction/account fields |
| `turn_context` | `turn_id`, `root_turn_id`, `model` | Task context and configured model; does not identify each model response |
| `event_msg` / `task_started` | `turn_id`, `root_turn_id`, `model_context_window` | Task start and advertised window; one task can have many requests |
| `event_msg` / `task_complete` | `turn_id`, timing fields | Task completion; ignore `last_agent_message` |
| `response_item` | `type`, `call_id`, `name`, optional `namespace`, `id` | Tool-call/output association; transcript-bearing fields must be discarded |
| `event_msg` / `item_completed` | `thread_id`, `turn_id`, `item`, timing | Another presentation of completed items; avoid counting it as another tool invocation |
| **`token_usage_record`** | `thread_id`, `session_id`, `turn_id`, `root_turn_id`, **`response_id`**, `usage`, `turn_token_usage`, `thread_token_usage` | Best-effort provider usage for a completed response; primary request accounting source |
| `event_msg` / `token_count` | `info.last_token_usage`, `info.total_token_usage`, `info.model_context_window`, sibling `rate_limits` | Latest usage/display snapshot; repeated and exceptional snapshots exist |
| `compacted` | `compaction_response_id`, `latest_token_usage_record`, window metadata | History/checkpoint boundary; nested latest usage is a checkpoint, not automatically another request |

`world_state`, messages, reasoning, inter-agent communications, and many future
events are outside the retained metrics schema. Ignore them without persisting
unknown payloads.

### Counters and subsets

[Protocol definitions and operations](https://github.com/openai/codex/blob/d27764b82f7118f674371e6d6e76271d9d606edb/codex-rs/protocol/src/protocol.rs)
and the [session usage accumulator](https://github.com/openai/codex/blob/d27764b82f7118f674371e6d6e76271d9d606edb/codex-rs/core/src/state/session.rs)
establish:

- `TokenUsageRecord.usage` belongs to one completed provider response.
- `turn_token_usage` accumulates responses within a task `turn_id`.
- `thread_token_usage` accumulates from the latest restored thread ledger record.
- Normal `TokenUsageInfo.append_last_usage` adds to `total_token_usage` and replaces
  `last_token_usage`. Neither cumulative field is a value to sum over snapshots.
- **Exception:** `fill_to_context_window` replaces the snapshot cumulative total
  with the context-window size and creates a synthetic last delta. Therefore a
  `token_count` total is not an unconditional strict lifetime counter.

The [Responses usage mapping](https://github.com/openai/codex/blob/d27764b82f7118f674371e6d6e76271d9d606edb/codex-rs/codex-api/src/sse/responses.rs)
maps cached tokens from input details and reasoning tokens from output details.
Cached input is part of input; reasoning is part of output. Preserve explicit
`total_tokens`; do not add the two subsets again. `cache_write_input_tokens` also
exists in this installation and must be preserved when provided, without adding
it again to the source total or assuming it is zero on other versions.

Focused local validation found 16 and 306 completed usage records respectively;
all inspected records satisfied `total = input + output`, `cached <= input`, and
`reasoning <= output`. The second sample contained 325 token snapshots, 20 exact
repeat snapshots, and two compactions. After compaction the latest request
footprint fell to roughly 32K while cumulative totals remained in the millions.
These checks support the source interpretation; they are not exhaustive tests.

### Request identity and replay

The observed native records had nonempty response IDs. Use ownership plus
`response_id`, rather than timestamps, task boundaries, usage equality, or byte
position, for request identity. Two distinct responses can have identical usage.
A token snapshot mirroring a native record must not add another row or cost.
Repeated native IDs with conflicting usage require a diagnostic and quarantine,
not a second request or silently replaced value.

The [upstream rollout test](https://github.com/openai/codex/blob/d27764b82f7118f674371e6d6e76271d9d606edb/codex-rs/core/tests/suite/token_usage_rollout.rs)
asserts two responses in one task (120 then 80 tokens, cumulative 200), followed by
a resumed task (30 tokens, thread cumulative 230). That directly disproves
`task turn = model request`. The test was inspected, not run locally.

A native ledger is still best-effort. Responses without a completed usage record,
including interrupted or failed attempts, cannot be assigned fabricated totals.
Compaction checkpoints may seed reconciliation baselines but must not be counted
as new requests merely because they repeat a nested record.

### Compaction, interruption, resume, fork, resets

| Case | Evidence | Conservative behavior |
| --- | --- | --- |
| Duplicate snapshots | Observed locally; source can re-emit usage state | Update snapshot freshness only; no request/count increment |
| Resume | Upstream test and [restored usage notification logic](https://github.com/openai/codex/blob/d27764b82f7118f674371e6d6e76271d9d606edb/codex-rs/app-server/src/request_processors/token_usage_replay.rs) | Replay owned identities deterministically; preserve cumulative baseline |
| Compaction | Local top-level checkpoints and falling last-request sizes; source supports history replacement | Preserve observed ledger totals; invalidate current-context claims; do not recursively parse replacement transcripts |
| Context exceeded | Protocol overwrites display usage | Mark token snapshot as unsuitable for lifetime accounting; do not manufacture a request |
| Interrupted requests | Completion-only ledger definition; lifecycle events exist in protocol | Keep task interruption and unassigned tool activity; missing usage is unknown |
| Fork | [Session source](https://github.com/openai/codex/blob/d27764b82f7118f674371e6d6e76271d9d606edb/codex-rs/core/src/session/session.rs) supports copied/referenced history and distinct storage identity | Exclude foreign-thread records from own usage; do not assume a fork file is a complete independent history |
| Parent/child totals | Child provenance observed; copied/referenced histories supported | No parent+child roll-up in MVP; overlap/independence not proven for every mode |
| Counter decrease/reset | Protocol has display reset/full-window behavior; exhaustive local reset history not sampled | Open a reconciliation boundary; no negative delta and no blind positive-clamped billing |
| Archive move/replacement | Not exercised against real chats | Test synthetically; merge identity across copies and rebuild after file replacement |

No existing chat was interrupted, forked, resumed, or compacted for this study.
Global non-overlap of parent/child cumulative totals remains **unverified**.

### Current context

`model_context_window` was observed as 258,400. Use returned values; do not infer
an advertised model maximum from the model name. This value is distinct from an
auto-compaction threshold and can vary by task/configuration.

No inspected metrics-only event provides an exact continuously current context
occupancy. `last_token_usage.total_tokens` measures the last response footprint;
it is not the size of all currently retained history after additional tool
results, queued input, or compaction. The [history estimator](https://github.com/openai/codex/blob/d27764b82f7118f674371e6d6e76271d9d606edb/codex-rs/core/src/context_manager/history.rs)
is a coarse byte-based lower bound inside Codex, requiring transcript/history
state. Sidecar will not reproduce it by ingesting conversation contents.

The protocol also has a baseline-adjusted context percentage helper (12K reserved
baseline), so a raw last-request/window ratio must not be presented as a verified
match to the desktop UI. MVP: **Current context: Unavailable**, advertised window
when known, plus separately labeled **Last request footprint**. Exact context is
a capability-gated future metric, not a prerequisite for useful session tracking.

### Tools and active session

Native function/custom calls and matching outputs carry `call_id`. Retain exact
public tool names, namespace, task identity, timestamps/order, and completion
state. Count a call once across response items and duplicate item-completed views.
The inspected records do not directly attach a response ID to every tool item.
Within one task, calls preceding a completed usage record can be associated by
stream ordering, explicitly labeled **order-based association**. Parallel,
late, orphaned, or boundary-crossing activity must remain unassigned when ambiguous.
An orchestration tool such as `functions.exec` is one observed invocation; inner
reads/searches/shell commands cannot be counted without inspecting its arguments.

File modification/activity time identifies recent activity, not the foreground
chat. Child agents and concurrent chats can be newer than the user's selected
root chat. The passive app-server test below returned no loaded threads. The Codex
host's own thread tools are privileged in-app capabilities, not an interface a
standalone Sidecar inherits. Manual selection is therefore the reliable MVP flow;
optional recent-root suggestions must be visibly heuristic.

## 3. Account quotas and independent app-server probe

The [official app-server documentation](https://learn.chatgpt.com/docs/app-server)
was opened, Context7 was queried, and installed generated schemas were inspected.
The installed protocol includes:

- `account/rateLimits/read` and `account/rateLimits/updated`;
- `thread/tokenUsage/updated` (a snapshot, not a response ledger);
- `thread/loaded/list`;
- `account/read`, with `refreshToken: false` for passive inspection;
- initialize/initialized handshake with `clientInfo` and capabilities.

A separate stdio server was initialized with analytics disabled by a process-only
override and explicit gateway OAuth handling. It was asked only for loaded
threads, account status, and rate limits, then terminated. Sanitized results:

| Probe | Observed result |
| --- | --- |
| Initialization | Success; installed reply exposes user agent, Codex home, platform fields |
| Account status | Existing managed `chatgpt` authentication |
| Loaded threads | Empty list, while the current desktop conversation was running |
| Quota read | Success, multi-bucket response present |
| Returned windows | `codex` bucket with a primary **10,080-minute** weekly window; secondary absent; no 300-minute window |
| Notifications | Supported by schema; delivery/cross-process completeness not demonstrated |

Exact account percentages, IDs, and reset dates are deliberately omitted from the
repository; this is a capability study, not a saved personal usage report.

Installed `RateLimitWindow`: `usedPercent` number, nullable
`windowDurationMins`, nullable `resetsAt`. The source [account processor](https://github.com/openai/codex/blob/d27764b82f7118f674371e6d6e76271d9d606edb/codex-rs/app-server/src/request_processors/account_processor.rs)
requires Codex-backend authentication; unauthenticated and API-key-only modes are
rejected. ChatGPT managed authentication worked here. Other auth modes were not
probed, and must be treated by capability rather than hard-coded assumptions.

Rules established from documentation/schema/source:

1. `usedPercent` means used; remaining is `clamp(100 - usedPercent, 0, 100)`.
2. Window duration is in minutes; reset is Unix time **seconds**.
3. Identify 5h and weekly by **300** and **10,080** minutes. Primary does not mean
   5h: the live probe returned a weekly primary window.
4. Prefer `rateLimitsByLimitId` when present; fall back to legacy `rateLimits` only
   when the map is absent/null. Preserve distinct buckets; never sum percentages.
5. Missing window/duration/reset/value means unavailable for that field. Neither
   null nor an empty response means zero usage or unlimited entitlement.
6. `ordinaryUsageAllowed` is nullable server permission, distinct from percent;
   Sidecar must not promise recovery from a reset countdown or quota percentage.
7. The response has no general freshness timestamp; stamp local receipt time.
   Preserve last successful result with stale/error labels after failures.
8. Poll independently: this process does not automatically observe other
   processes' desktop threads or guarantee notifications for their activity.

Retrieval uses Codex-managed authenticated network calls. Sidecar needs no direct
credential parser, private HTTP endpoint client, transcript upload, or cloud
backend. Starting Codex can involve its own credential refresh/runtime state;
Sidecar must neither implement login nor promise that Codex itself performs no
housekeeping writes. A local-only/offline mode must keep parsing operational with
quota provider disabled.

### 3.1 Dynamic-window recheck and installed raw shape

Follow-up inspection: **2026-10-07**, probe started at **14:17:57 UTC
(17:17:57 Europe/Minsk)**. CLI version remained **0.160.1**. Protocol definitions
were regenerated from that executable, rather than assuming upstream field names
are its wire schema. Two passive `account/rateLimits/read` calls succeeded, about
20 seconds apart, with `params: {"excludeResetCreditDetails": true}`. The default
`supportsLunaReserve` capability was not opted into. Existing `chatgpt` auth was
used; the research client did not open/read authentication files.

The owner's report that no 5-hour limit appears in App Settings is consistent
with the returned data. Settings UI itself was not inspected during this probe.
This is a time-specific account observation, not proof of an account's permanent
entitlements or of every other account's window set.

| Current-account question | Observed answer, both reads |
| --- | --- |
| Bucket keys | Exactly one: `codex` |
| Bucket name / model alias metadata | `limitName: null`, `normalModelSlug: null` |
| Primary window | Present, `windowDurationMins: 10080` = 7 days |
| Primary 5-hour window | No; primary is weekly |
| Any other 300-minute / 5-hour window | None returned |
| Secondary window | Explicitly `null` |
| Weekly window | Yes, primary |
| Additional/model-specific buckets | None returned in the map; support exists in schema/source |
| Percent/reset fields | Present and numeric on primary; actual personal values not retained |
| Change between reads | Window values unchanged |
| Independent process's loaded threads | Empty; desktop research chat was active |
| Rate-limit update notifications | Zero during a 40.3-second observation interval |
| Account notification | One `account/updated` during initialization/observation; not proof of a later account change |

There is **no mandatory 5h + weekly pair**. The primary/secondary position has no
fixed duration meaning. Missing 5h is a valid returned shape, not a reason to
manufacture a row, assume 0% used, or start inference to activate a window.

#### Wire fields versus backend fields

The installed generated app-server definitions establish the following shape:

```text
account/rateLimits/read(params optional)
  params.excludeResetCreditDetails?: boolean
  params.supportsLunaReserve?: boolean
  result.ordinaryUsageAllowed: boolean | null
  result.rateLimits: RateLimitSnapshot                 # legacy single bucket
  result.rateLimitsByLimitId: map<string, RateLimitSnapshot> | null
  result.rateLimitResetCredits: summary | null
  result.accountId: string | null                     # redact; never persist
  result.rateLimitUpsell: JSON value | null            # outside Sidecar metrics

RateLimitSnapshot
  limitId: string | null
  limitName: string | null
  normalModelSlug: string | null
  primary: RateLimitWindow | null
  secondary: RateLimitWindow | null
  credits: CreditsSnapshot | null
  individualLimit: SpendControlLimitSnapshot | null
  spendControlReached: boolean | null
  planType: PlanType | null
  rateLimitReachedType: RateLimitReachedType | null

RateLimitWindow
  usedPercent: number                                # Rust wire type i32
  windowDurationMins: number | null                   # integer minutes
  resetsAt: number | null                             # Unix seconds

account/rateLimits/updated notification
  params.rateLimits: RateLimitSnapshot                # one sparse bucket

account/updated notification
  params.authMode: AuthMode | null
  params.planType: PlanType | null
```

The actual read shape also contained non-null credit metadata with boolean
`hasCredits`/`unlimited` and string `balance`, a reset-credit summary with numeric
`availableCount` and null `credits`, non-null boolean ordinary/spend-control
fields, string plan metadata and string account ID. `individualLimit`,
`rateLimitReachedType` and `rateLimitUpsell` were null. Sensitive identifiers,
plan/credit amounts/permission values and usage numbers are not saved as personal
data. The [sanitized read example](fixtures/rate-limits-read.sanitized.json)
preserves this null/object/key shape but replaces personal scalar values; its
[fixture notes](fixtures/README.md) define which values are invented.

The snake_case names mentioned by the owner are real in the matching public
release's **backend OpenAPI models**, but they are not the app-server wire fields:

| Backend field | Installed app-server representation | Verified conversion |
| --- | --- | --- |
| `primary_window`, `secondary_window` | `primary`, `secondary` | Missing/null backend window normalizes to absent window |
| `used_percent` | `usedPercent` | Used percentage, not remaining |
| `limit_window_seconds` | `windowDurationMins` | Positive seconds round **up** to whole minutes: `(seconds + 59) / 60`; nonpositive becomes unavailable |
| `reset_at` | `resetsAt` | Absolute Unix seconds, widened from backend integer |
| `reset_after_seconds` | No corresponding window field on app-server wire | Not forwarded by the inspected window mapper; do not confuse it with absolute reset |
| `additional_rate_limits[].metered_feature` | Map key / `limitId` | Additional metered buckets; not necessarily a model ID |
| `additional_rate_limits[].limit_name` | `limitName` | Optional user-facing bucket name |

Evidence at matching commit `d27764b82f7118f674371e6d6e76271d9d606edb`:
[backend window model](https://github.com/openai/codex/blob/d27764b82f7118f674371e6d6e76271d9d606edb/codex-rs/codex-backend-openapi-models/src/models/rate_limit_window_snapshot.rs),
[backend status model](https://github.com/openai/codex/blob/d27764b82f7118f674371e6d6e76271d9d606edb/codex-rs/codex-backend-openapi-models/src/models/rate_limit_status_details.rs),
[additional bucket model](https://github.com/openai/codex/blob/d27764b82f7118f674371e6d6e76271d9d606edb/codex-rs/codex-backend-openapi-models/src/models/additional_rate_limit_details.rs),
and [backend normalization](https://github.com/openai/codex/blob/d27764b82f7118f674371e6d6e76271d9d606edb/codex-rs/backend-client/src/client.rs).
Sidecar consumes the normalized app-server interface; it does not need or claim
direct backend precision or a private HTTP client. A name/alias alone must not
turn a generic additional bucket into an assumed actual-model allowance.

#### Notification semantics during active work

The regenerated schema calls `account/rateLimits/updated` a **sparse rolling
update**. It contains a single `rateLimits` object, not a complete
`rateLimitsByLimitId` map. Nullable account metadata can be absent in this update
and must not erase previously read values. A notification for bucket A must not
remove B, and receiving A must not mark all buckets freshly checked.

The matching [event handler](https://github.com/openai/codex/blob/d27764b82f7118f674371e6d6e76271d9d606edb/codex-rs/app-server/src/bespoke_event_handling.rs)
emits a rate-limit notification when it handles a thread `TokenCountEvent` carrying
`rate_limits`, through a thread-scoped sender. The [protocol declaration](https://github.com/openai/codex/blob/d27764b82f7118f674371e6d6e76271d9d606edb/codex-rs/app-server-protocol/src/protocol/v2/account.rs)
allows clients to merge available fields into a full read or refetch. A standalone
quota process has no loaded desktop threads here; it cannot rely on this emission
path for notifications produced by another process's active session.

Empirical result: no rate-limit notifications were received during the bounded
probe, and both reads had identical window values. This **does not prove** that
limits cannot change, that no notifications ever arrive, or that an actual limit
change was tested. Deliberately causing inference/quota consumption or modifying
a user chat was outside scope. Installed-schema/source notification support is
verified; cross-process change delivery remains unverified.

Decision: keep the existing independent periodic read. Treat sparse notifications
as refresh hints, coalesce them into the next eligible single-flight read, and
replace the authoritative bucket map only on a successful full response. Null
metadata in a notification never clears cached full-read state. A null window in
a subsequent **full read** can remove that window. No new polling stage, inference,
credential access, or application implementation is required by this addendum.

#### Architecture consequences

Use a dynamic bucket map with optional primary/secondary windows and normalized
window durations, retaining source slot identity and optional model-alias metadata.
The visible list consists of the windows actually returned; 5h/Weekly are
convenience duration labels, not mandatory widget slots. Support additional
buckets by their returned ID/name without hard-coded model lists. Credit and
spend-control metadata are distinct from duration-based quota windows and must
not be treated as a fabricated time window. Retrieval succeeded through Codex
managed authentication without direct credential reading by the research client.

### 3.2 Stage 6 installed-profile recheck — 2026-10-08

Executable discovery and bounded `--version` verification freshly returned
**Codex CLI 0.160.1**. The production allowlisted QuotaProvider/QuotaRPC used the
same resolved Codex root as session discovery, with analytics disabled for its
owned process. One initial attempt was stopped after a startup account hint
invalidated the pending read, **before any quota read**. A bounded recovery run
allowed the existing scheduled 60-second reread on the same process; it completed
**exactly one** `account/rateLimits/read`. No repeated successful probes were made.

The normalized result matched an independent field comparison in memory for
dynamic bucket membership, optional names/model aliases, primary/secondary slot
identity, numeric availability, durations in minutes and reset timestamps in Unix
seconds. The current shape was one bucket with a 10,080-minute Weekly window and
one absent slot; no 300-minute window was returned. Present-window numeric fields
were non-null; the absent window remained absent. This does not establish real
multiple-bucket, duplicate-duration or null-numeric-field coverage: those remain
synthetic tests. Percentages, reset dates, account IDs and raw replies were not
exported. The owned transport was stopped. No authentication file was opened or
account/inference mutation requested; Codex-managed housekeeping is not audited.

A bounded existing native session (header 0.160.1) also matched independent
numeric inspection for unique-response count, observed total, optional breakdown,
cache rate, reported cumulative and reconciliation. Selected-file fingerprints
showed growth with the original prefix intact during a five-second interval,
rather than unchanged bytes. Completed-response live-append and GUI visibility
were not established by that byte growth. See the dated validation record for
method limits and remaining acceptance gaps.

Context7 resolved `/openai/codex` and queried the passive stdio/account protocol.
Its current-main documentation corroborates the method/field shape; installed
execution above, rather than current-main source, is the compatibility evidence.
No new product research or upstream implementation copying was performed.
Cross-process notification delivery and actual account changes remain unverified.

## 4. Existing projects: pinned source audit

All entries were inspected on **2026-10-07**, using GitHub repository metadata,
commit/tree APIs, license files where present, READMEs, and the named source files.
No project was installed, run, or benchmarked. Findings describe inspected code,
not tested compatibility or maintenance guarantees. Heads may change after this
date. Similar names do not establish the intended identity from the discussion.

| Candidate / repository | Inspected commit (full SHA) / version | Commit date (UTC) | Architecture / quota source | License |
| --- | --- | --- | --- | --- |
| [CodexScope — poer2023](https://github.com/poer2023/CodexScope) | `dea9cdcfd97573038feca75899259ce6a67265e8` | 2026-07-02 | Tauri 2, React/TS, Rust; app-server account usage/limits, extra direct reset-credit endpoint | MIT; preserves HduSy/tokenscope copyright and NOTICE |
| [CodexScope — JUk1-GH](https://github.com/JUk1-GH/CodexScope) | `21fcc718de232cca7f3453f9156bf8fec1e2aae0` | 2026-05-09 | Go export/cache and static web dashboard; log rate-limit snapshots | MIT |
| [Codex Token Monitor — gouwenct](https://github.com/gouwenct/Codex-Token-Monitor) | `a9ac20406f1a12fe796d824b20b34f0a405e665c`, package 0.3.0 | 2026-05-01 | VS Code extension, JS; local token analytics, no verified live official-quota provider | MIT, copyright gouwengone |
| [Codex-Claude-Token-dashboard — ganesh-santhanam](https://github.com/ganesh-santhanam/Codex-Claude-Token-dashboard) | `e8021f82972a9623fa30166d960e2b7ee27a16cd` | 2026-07-01 | Python, SQLite, local HTTP/web dashboard; logs, no live quota provider in inspected parser/scanner | MIT, copyright Nathan Herkelman; fork of nateherkai/token-dashboard |
| [Codex Usage Desktop — itvincent-git](https://github.com/itvincent-git/codex-usage-desktop) | `3bbeaec659e3b625b90af8d982dec8ef5c47d191`, package 3.12.0 | 2026-10-07 | Tauri, React/TS, Rust/SQLite; direct OAuth quota HTTP, CLI RPC fallback | MIT |
| [CodexMonitor — Dimillian](https://github.com/Dimillian/CodexMonitor) | `dd61b9abd37de5ded86e82b9fe8a83fd49d46fa5` | 2026-03-26 | Tauri/React/Rust; app-server-backed agent/workspace client and local usage | MIT |
| [Codex Usage Bar — spojma](https://github.com/spojma/codex-usage-bar) | `3e10b3ea0940a5b5ce84f731e741dc6f6314c8b5` | 2026-07-30 | Swift/AppKit UI plus Python; app-server bucket/window flattening | No license file/SPDX license identified; no code reuse |
| [Additional monitor — falyx6851-byte](https://github.com/falyx6851-byte/codex-monitor) | `b565aa66adab1f3733a0ad9b95ebe2189a19dca7` | 2026-09-15 | Node/local HTTP/SQLite; modern response-ledger parser, local analytics | MIT |

### CodexScope (both identities remain distinct)

**poer2023:** inspected `store.rs`, `parser.rs`, `account_usage.rs`, LICENSE and
NOTICE at the pinned commit. [Store](https://github.com/poer2023/CodexScope/blob/dea9cdcfd97573038feca75899259ce6a67265e8/src-tauri/src/store.rs)
uses incremental offsets, parser state, compact cached events, last-token values,
and IDs formed from session plus cumulative total. This suppresses some repeated
snapshots but is not provider response identity, and can collide across resets.
It tracks model context and extracts tool response items. Aggregate periods, not
a verified foreground chat, are the product focus.
[Account integration](https://github.com/poer2023/CodexScope/blob/dea9cdcfd97573038feca75899259ce6a67265e8/src-tauri/src/account_usage.rs)
starts app-server; additional reset-credit enrichment reads auth and calls a
private endpoint. Useful: separate provider, incremental state, compact menu UI.
Do not import credential handling or treat its request accounting as authority.

**JUk1-GH:** inspected `generate_codex_data.go`, README, LICENSE.
[Generator](https://github.com/JUk1-GH/CodexScope/blob/21fcc718de232cca7f3453f9156bf8fec1e2aae0/generate_codex_data.go)
prefers cumulative deltas after a baseline, falls back to last usage, clamps
negative component deltas, and deduplicates snapshot tuples. It exports static
analytics and log-derived quota information with incremental caching. This is
not a live app-server/active-chat companion. Useful: bounded metadata exports;
reset clamping is insufficient for Sidecar's strict reconciliation.

The earlier name alone cannot resolve which CodexScope was intended. Both are
recorded instead of selecting one silently.

### Codex Token Monitor

[Extension source](https://github.com/gouwenct/Codex-Token-Monitor/blob/a9ac20406f1a12fe796d824b20b34f0a405e665c/src/extension.js)
streams files, tracks configured model/service tier, computes cumulative deltas,
and skips zero deltas. File watching plus fallback polling updates a latest-session
status bar. Recent modification/token time is a heuristic, not selected desktop
chat identity. Component-wise delta handling cannot establish request identity
through resets, inheritance, or display-counter overrides. It also reads prompt
snippets and optional auth/account metadata; Sidecar will not adopt that approach.
Useful: watching plus polling and transparent unknown-model behavior.
Other projects also use this name (including hans0510/codex-monitor); the original
intended identity remains unconfirmed. That alternative was found but not audited.

### Codex-Claude dashboard

GitHub metadata establishes the named repository is a fork of
[nateherkai/token-dashboard](https://github.com/nateherkai/token-dashboard); its
README still directs cloning that upstream. Audit applies to the pinned **fork**,
not an assumed identical current upstream.
[Codex parser](https://github.com/ganesh-santhanam/Codex-Claude-Token-dashboard/blob/e8021f82972a9623fa30166d960e2b7ee27a16cd/token_dashboard/sources/codex.py)
emits token-count rows using `last_token_usage`, keys rows by session/line, groups
prompt/task metadata, parses tool commands/files, and retains raw JSON and text.
The inspected token-count path does not deduplicate repeated usage snapshots by
provider response ID. Scanner rescans changed files into SQLite; there is no
verified active-desktop selector or live account quota provider in this path.
Useful: source adapters and timeline ideas. Unsuitable to copy its text retention,
estimated token fallback, or row-as-request assumption.

### Codex Usage Desktop

Inspected `scanner.rs`, `session_index.rs`, `codex_limits.rs`, `lib.rs`, package and
license. [Scanner](https://github.com/itvincent-git/codex-usage-desktop/blob/3bbeaec659e3b625b90af8d982dec8ef5c47d191/src-tauri/src/scanner.rs)
uses last-token usage preferentially and cumulative deltas as fallback, with
SQLite-backed session/project analytics and conversation replay features.
[Limits provider](https://github.com/itvincent-git/codex-usage-desktop/blob/3bbeaec659e3b625b90af8d982dec8ef5c47d191/src-tauri/src/codex_limits.rs)
tries direct authenticated `wham/usage` before CLI fallback, and includes reset
and quota-window activation features. No foreground desktop session guarantee was
found in the inspected indexing path. Useful: independent limit fetching,
single-flight refresh and tests. Direct credentials, forecasts/third-party
services, resets, and model calls to activate windows are outside Sidecar scope.
Full scanner duplicate/edge-case behavior was not runtime-tested.

### Codex Monitor and additional modern parser

**Dimillian:** a full agent client, not a passive observer of another desktop
process. Inspected `backend/app_server.rs`, `shared/account.rs`,
`shared/local_usage_core.rs`, README and license. It manages its own app-server
processes and thread state; its ability to track its own threads does not prove
cross-process observation. Account switching/auth handling is outside scope.
Useful: lifecycle ownership and provider boundaries; do not reproduce the agent
orchestration surface. The generic candidate name is ambiguous.

**falyx6851-byte:** [session parser](https://github.com/falyx6851-byte/codex-monitor/blob/b565aa66adab1f3733a0ad9b95ebe2189a19dca7/lib/session-parser.js)
prefers `token_usage_record`, deduplicates response IDs, filters inherited foreign
history, and has legacy token-count fallbacks and timing estimates. This is the
closest inspected modern accounting reference. Its filtered system events,
fallback timing, and history index should not be treated as upstream guarantees.
Useful: response-ID ownership and modern/legacy source separation. No reliable
foreground desktop selection established; no live quota endpoint audited here.

### Menu-bar tools

**spojma:** inspected `agent_limits.py`, `usage_data.py` and README. It flattens
`rateLimitsByLimitId`, supports legacy view, labels by actual duration, and keeps
reset optional. Active-model matching uses Accessibility; numerical quotas do not
require it. Sidecar will not require Accessibility or install an autostart agent.
No license identified in inspected tree, so implementation must be independent.
Names also match unrelated projects such as bhutano/codex-usage-bar (log-only
terminal UI) and methol-dev/usage-bar (native app with direct credential reads).
Those are discovery leads, not audited/reusable dependencies.

### Reuse decision

No upstream implementation will be vendored in MVP. Write the small accounting
core independently from OpenAI schemas and synthetic examples. If code is later
copied from an MIT project, retain its actual copyright notice and full license
in the redistributed portion, including inherited notices and CodexScope NOTICE
where applicable. OpenAI source is Apache-2.0; any future source copying requires
its license/NOTICE review too. No-license candidates grant no assumed reuse right.
Links and independently expressed architectural lessons do not establish code
reuse. On 2026-10-08, the owner selected MIT for Sidecar, copyright Gerionil;
see [LICENSE](../LICENSE). Publication remains a separate owner action.

## 5. Stack evaluation and implications

Current documentation was fetched through Context7 for OpenAI Codex, SwiftUI,
and Tauri. Apple's [WindowGroup documentation](https://developer.apple.com/documentation/swiftui/windowgroup)
confirms a native window scene. [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/)
require Rust and platform tools; desktop macOS may use Command Line Tools.

| Choice | Fit for this MVP | Tradeoff |
| --- | --- | --- |
| Swift / SwiftUI + Foundation + SwiftPM | One macOS window, local file reader, subprocess quota RPC, one language, installed toolchain | macOS-only; SwiftPM app bundling/older macOS checks must be validated |
| Tauri 2 + Rust + web UI | Proven in several inspected projects; cross-platform shell and strong parser ecosystem | Rust plus web dependencies/IPC/build pipeline; cross-platform benefits are outside MVP |

**Recommendation:** Swift 6, macOS 14+, SwiftUI, Foundation, XCTest, SwiftPM,
no third-party runtime dependency and no database. macOS 14 is a chosen product
floor, not a tested compatibility claim. First implementation stage must verify
build/test feasibility with Command Line Tools; UI stage must verify `.app`
packaging and macOS floor before declaring support. No comparative memory or
performance benchmark was run, so no numeric performance claims are made.

## 6. Research conclusions and remaining gates

The feasible MVP is passive local **completed-response accounting** plus a
separate account-quota provider. Reliable manual selection replaces an unsupported
promise to follow the foreground desktop chat. Exact current context, exhaustive
failed-request usage, exact per-response model attribution through fallback,
parent/child roll-ups, and tool sub-operation costs remain unavailable.

Non-blocking limitations: absent 5h window, exact context, auto-selection, and
older JSONL versions. Blocking gates before dependent implementation: malformed
ownership/native schema must fail closed; counter conflicts must prevent complete
reconciliation claims; protocol/version capability checks must precede live quota
use; unavailable build/SDK support must be resolved before UI packaging. None
requires starting or altering chats. Acceptance must preserve these limitations
instead of trying to fill them with guesses.

### 6.1 Owner-approved platform and presentation direction — 2026-10-07

Following the research and interactive mockup discussion, the owner accepted
macOS-first delivery with Swift/SwiftUI. Windows remains a possible future phase,
not an MVP support promise. This is a product decision, not evidence that a Windows
version is technically impossible or that demand has been measured.

The presentation direction is a menu-bar panel plus a companion window, both
with manual chat selection and one shared store/provider lifecycle. Apple's
[MenuBarExtra documentation](https://developer.apple.com/documentation/swiftui/menubarextra)
supports a persistent menu-bar control and window-style custom content. Native
build, packaging, shared selection and lifecycle acceptance remain implementation
checks; a functioning synthetic mockup is not proof of native app behavior.

The owner has no Windows test environment. [GitHub-hosted Windows runners](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners)
and [Tauri UI tests in CI](https://v2.tauri.app/develop/tests/webdriver/ci/)
can support automated checks, but a future supported Windows release also needs
real installation, tray, Codex auth/limits, session discovery and relevant WSL
acceptance through a tester or accessible runtime environment. A SwiftUI MVP
would need a new Windows UI and adaptation of platform code; separating UI and
accounting responsibilities does not guarantee an automatic port. Current
behavior and limitations are described in the [README](../README.md) and
[validation](validation.md).

### Optional stored chat metadata — 2026-10-08

A bounded schema-only inspection of the local `session_index.jsonl` observed
`id`, `thread_name` and `updated_at` keys. No real values, names, identifiers or
source paths were exported. This internal, optional format is version-sensitive;
it does not guarantee a name for every discovered chat or exact desktop recency.
The owner approved using only those fields to improve selector labels and ordering,
with identity fallback. Unknown fields are discarded, names stay in memory and
no transcript fallback, database access or chat RPC is introduced. Foundation
ISO8601 parsing for ordinary and fractional timestamps was checked through current
Apple Foundation documentation via Context7. Synthetic regression evidence is in
[validation](validation.md).
