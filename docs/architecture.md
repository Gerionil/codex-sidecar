# Architecture Notes

> Historical product-direction notes. Current behavior and limitations are described in the [README](../README.md), supported by [research.md](research.md) and [validation.md](validation.md). Illustrative layouts and technical hypotheses below are not live capability claims.

This document contains hypotheses, not final decisions.

Implementation should validate these assumptions before locking the architecture.

## High-level architecture

```text
Codex App
   │
   ├── ~/.codex/sessions/**/*.jsonl
   │
   └── Codex app-server
             │
             ▼
      ┌─────────────────┐
      │ Data Providers  │
      └────────┬────────┘
               │
               ▼
      ┌─────────────────┐
      │ Normalization   │
      │ + Turn Builder  │
      └────────┬────────┘
               │
               ▼
      ┌─────────────────┐
      │ Application     │
      │ State           │
      └────────┬────────┘
               │
               ▼
      ┌─────────────────┐
      │ Sidecar UI      │
      └─────────────────┘
```

## Session provider

Responsibilities:

- discover Codex session files
- monitor filesystem changes
- identify active sessions
- stream new events

Possible source:

```text
~/.codex/sessions/**/*.jsonl
```

The application should not hard-code a machine-specific home path.

Use the user's home directory dynamically.

## Parser

The parser should convert raw Codex JSONL records into a stable internal representation.

Avoid leaking Codex-specific schemas throughout the UI.

Example internal events:

```text
SessionStarted
TurnStarted
TokenUsage
ToolStarted
ToolFinished
TurnFinished
SessionFinished
```

These names are illustrative only.

## Token accounting

Potential raw fields include:

```text
total_token_usage
last_token_usage
model_context_window
```

Their semantics must be verified.

A likely pattern is:

- `total_token_usage` = cumulative session accounting
- `last_token_usage` = usage associated with the most recent model request

But implementation must derive this from real data and tests rather than assumption.

### Important failure mode

Never do this blindly:

```text
sum(all total_token_usage.total_tokens)
```

If the values are cumulative, this massively overcounts usage.

Preferred source for per-turn usage should be an explicitly per-request/per-turn field where available.

## Turn reconstruction

One user/task turn may contain several model requests:

```text
user/task turn
   ↓
model request A (Sidecar model turn A)
   ↓
tool call
tool call
tool call
   ↓
model request B (Sidecar model turn B)
```

Sidecar must distinguish an individual model request from an app-server turn or
user interaction. A `token_count` event is not automatically a new model turn:
repeated snapshots or completion events may refer to the same request. If request
boundaries cannot be reconstructed reliably, expose only the verified aggregate
and label per-model-turn accounting unavailable.

Tool activity should be grouped according to observed event ordering.

We should not claim:

```text
read_file = 4,392 tokens
```

unless Codex explicitly provides that accounting.

Instead:

```text
Turn #18 = 123,201 tokens

Associated tools:
read ×14
search ×6
shell ×3
```

## Active session detection

Potential heuristics:

1. newest modified session file
2. newest active task event
3. process/app-server metadata if exposed
4. project working-directory correlation
5. explicit manual selection as fallback

This should be researched.

## Quota provider

Updated from empirical research on 2026-10-07: there is no required fixed
`5-hour + weekly` pair. The current account returned one `codex` bucket with a
10,080-minute primary window, null secondary and no additional/model-specific
buckets. This is a dated returned shape, not a permanent account guarantee.
See [the follow-up investigation](research.md#31-dynamic-window-recheck-and-installed-raw-shape)
and [README](../README.md) for verified behavior.

Keep quota retrieval separate and expose a dynamic snapshot:

```text
QuotaProvider
  readSnapshot() -> RateLimitSnapshot
  states() -> stream of available/unavailable/stale/error snapshots

RateLimitSnapshot
  bucketsById: map<id, RateLimitBucket>
  receivedAt
  accountGeneration

RateLimitBucket
  id
  name?
  normalModelSlug?
  windows[]                 # preserve primary/secondary source slot

RateLimitWindow
  sourceSlot
  usedPercent?
  durationMinutes?
  resetAt?                  # absolute Unix seconds
```

Initial adapter: `CodexAppServerQuotaProvider`, using its own stdio process and
existing Codex-managed authentication. The client does not read `auth.json`, copy
tokens, or call private HTTP endpoints. Read `account/rateLimits/read`; prefer the
returned `rateLimitsByLimitId` map, with single-bucket `rateLimits` fallback only
when the map is absent/null. An empty map remains empty.

The installed 0.160.1 wire has nullable `primary` and `secondary` windows, with
`usedPercent`, `windowDurationMins`, `resetsAt`. Backend fields such as
`primary_window`, `limit_window_seconds`, `reset_after_seconds`, and `reset_at`
are another layer; Sidecar consumes the normalized wire, not guessed aliases.
Additional buckets are accepted by returned ID/name, without fixed model lists.
`normalModelSlug` is optional alias metadata, not actual-model attribution.

Render the windows actually returned. 300 minutes may be labeled 5h and 10,080
minutes Weekly; other durations remain supported. Primary does not imply 5h.
Missing windows/percent/duration/reset remain unavailable, never zero or invented
allowances. Credits and spend controls are separate from time windows.

`account/rateLimits/updated` contains one **sparse** bucket. Treat it as a hint for
an eligible coalesced full read, not a replacement for the complete map. Nullable
notification metadata must not erase cached full-read values; a successful full
read can authoritatively remove absent windows/buckets. Keep polling because an
independent app-server had no loaded desktop threads and received no rate-limit
notification during the bounded probe. Cross-process push delivery is unverified.

Background reads use `excludeResetCreditDetails: true`; no Sidecar fallback
capability is advertised through `supportsLunaReserve`. Quota retrieval may cause
Codex-managed OpenAI network calls. Offline mode disables the quota process while
local parsing continues. Local token counts never become official quota percent.

## Application state

Possible shape:

```text
AppState
  activeSession
  sessions[]
  quotas
  context
```

Session:

```text
Session
  id
  path
  project
  startedAt
  lastActivityAt
  model
  turns[]
  totals
```

Turn:

```text
Turn
  id
  startedAt
  completedAt
  tokenUsage
  tools[]
```

TokenUsage:

```text
TokenUsage
  input
  cachedInput
  output
  reasoning
  total
```

## Real-time processing

Prefer incremental reading rather than reparsing potentially large JSONL files every time they change.

Possible algorithm:

```text
open session
remember byte offset

filesystem change
      ↓
read appended bytes
      ↓
parse complete lines
      ↓
normalize events
      ↓
update current turn/session
      ↓
publish UI update
```

Handle:

- partial final lines
- file rotation
- session switching
- application restart
- malformed events
- unknown future event types

## Persistence

MVP may not require a database.

Historical data can potentially be rebuilt from session files.

If derived persistence becomes useful later, SQLite is a reasonable candidate.

Do not introduce it before needed.

## UI technology

The owner approved **Swift 6 / SwiftUI, macOS 14+, Foundation, XCTest and SwiftPM**
for the first release on 2026-10-07. No third-party runtime dependencies or database
are planned. Build/packaging and the declared OS floor still require validation.

The menu-bar panel (`MenuBarExtra` with window style), companion Window scene,
and Settings scene use one shared main-actor store. Selecting a chat in either
main surface updates the same reader/subscription and both views. Account quotas
retain their independent account scope; selecting a chat does not change them.
Open window focuses/reuses the companion. Panel dismissal or window closure
keeps the app/providers alive; explicit Quit cancels readers and the owned child.
UI views never perform token accounting or instantiate their own quota process.

Windows is possible later, with no release commitment. The owner currently lacks
a Windows test environment. A Windows phase requires user demand and real runtime
acceptance through a tester or accessible environment; CI is supplementary.
Separation from SwiftUI keeps responsibilities clear but is not a promise of a
portable UI/core: Windows needs another UI and platform adaptations.

Evaluated options:

### Swift / SwiftUI

Pros:

- native macOS experience
- menu bar/window integration
- low memory overhead

Cons:

- macOS-specific

### Tauri

Pros:

- Rust backend
- web UI
- cross-platform potential
- evaluate whether inspected Codex usage tools offer reusable architectural lessons

Cons:

- more moving parts than native Swift for a macOS-only MVP

The authoritative decision and scope are recorded in [README](../README.md).

## Security

Do not:

- upload conversation logs
- log auth credentials
- commit real Codex session files
- include user's absolute paths in fixtures
- copy prompts/source code into analytics unnecessarily

Tests should use synthetic JSONL fixtures.

## Open-source constraints

Before copying implementation details from another project:

- inspect its license
- document attribution requirements
- prefer clean independent implementations when uncertain

Target repository should be safe to make public from the first commit.

## Accounting invariants to verify

- Preserve explicit source totals and their scope; never sum cumulative snapshots.
- Cached input and reasoning output may be subsets of input and output. Verify
  the schema and avoid counting them twice.
- Use per-request counters only after proving their scope and deduplicating
  repeated updates. A cumulative delta is a fallback only within a validated,
  continuous counter epoch; negative/reset deltas require reconciliation.
- Do not aggregate parent and child sessions automatically: investigate whether
  their reported totals overlap.
- Treat compaction, resume/fork, interrupted requests, model changes, and counter
  resets as separate research cases.
- Current context occupancy needs its own validated source. Neither cumulative
  session totals nor an assumed model window is an acceptable substitute.
- For a validated percentage, remaining = clamp(100 - usedPercent, 0, 100).
  Missing values remain unavailable.

## Official app-server reference

The [official app-server documentation](https://learn.chatgpt.com/docs/app-server)
documents `account/rateLimits/read`, `account/rateLimits/updated`, and
`thread/tokenUsage/updated`. Its rate-limit examples include `usedPercent`,
`windowDurationMins`, and `resetsAt`, with optional multiple limit buckets.

The installed 0.160.1 protocol and passive quota reads were checked on 2026-10-07.
The dynamic shape and sparse-notification rules above replace the original fixed
pair hypothesis. A separate process returned no loaded desktop threads; the
40.3-second probe received no rate-limit update, while two read responses had
unchanged window values. This does not establish behavior after an actual limit
change or prove cross-process notification delivery. Periodic reads remain the
independent provider's source of freshness.

Keep Sidecar passive: quota inspection must not start model turns, resume or
modify user threads, or change account settings.

## File-reader and privacy details

Resolve the Codex data root from supported configuration/environment (including
`CODEX_HOME` where applicable), then use the default home-based location as a
fallback. Keep source files read-only.

Buffer incomplete JSONL lines until complete; distinguish append from truncation
or replacement. Reconcile after missed filesystem events and rebuild state on
restart without duplicate counting. Unknown fields/events should be tolerated;
malformed lines should produce a sanitized diagnostic, not a raw transcript dump.

Retain only derived metrics and minimal tool metadata. Quota retrieval may involve
Codex-managed authenticated requests to OpenAI; it does not justify a separate
Sidecar cloud backend. Store no copied credentials in Sidecar state or logs.
