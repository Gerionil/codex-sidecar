# MVP

> Historical product-direction notes. Verified decisions and limitations are now defined in [SPEC.md](../SPEC.md), supported by [research.md](research.md). Illustrative layouts and technical hypotheses below are not live capability claims.

## Goal

Build the smallest reliable version of Codex Sidecar that proves we can observe an active Codex session and correctly account for model-turn token usage.

Correctness is more important than appearance.

## MVP features

### Session discovery

- discover Codex session files
- identify recently active sessions
- select the active session where possible
- provide manual selection and show when automatic selection is only a heuristic

Expected source:

```text
~/.codex/sessions/**/*.jsonl
```

### JSONL parsing

Parse only the metadata needed for metrics and tool summaries. Do not display or persist prompt text, source code, tool arguments, or tool output by default.

Candidate event concepts to investigate:

- token_count
- turn_context
- response_item
- task_started
- task_complete

Actual event names and schemas must be verified.

### Model-turn reconstruction

Build an internal representation such as:

```text
Session
  ├── Turn 1
  ├── Turn 2
  ├── Turn 3
  └── Turn 4
```

Each turn should contain:

- timestamp
- model if available
- input tokens
- cached input tokens
- output tokens
- reasoning output tokens
- total tokens
- tool-call summary

### Token accounting

Correctly distinguish:

- cumulative counters
- last-call counters
- session totals
- context window values

Do not sum cumulative counters blindly.

Automated tests are required.

### Real-time updates

Watch active Codex session files and update the application when new events appear.

### Quotas

Display, if reliably available:

- 5-hour usage
- weekly usage
- reset timestamps

Prefer an official/local Codex mechanism such as app-server where available.

Quota retrieval should be isolated behind an interface so it can change independently.

### Minimal UI

One small window is enough.

Suggested first layout:

```text
LIMITS

5h        72% left
Weekly    54% left

CONTEXT

143K / 258K
55%

SESSION

Total      1.42M
Cached     1.18M
Cache hit  87%

TURNS

#18     123.2K
#17      81.4K
#16      42.7K
```

Selecting a model turn can reveal its breakdown. All example numbers above are synthetic.

Show missing or unsupported metrics as unavailable, never as zero. Show a last-updated time and stale/error state when a provider stops updating.

## Non-goals for MVP

Do not initially build:

- cloud synchronization
- user accounts
- telemetry backend
- Windows/Linux support unless nearly free
- Codex App modifications
- overlay injection into Codex UI
- exact token cost per individual tool call
- cost estimation in dollars
- long-term analytics dashboard
- automatic GitHub publishing
- notifications
- elaborate charts
- themes
- plugin system

## Acceptance criteria

MVP is successful when:

1. Starting a Codex session makes it appear in Sidecar.
2. A new model turn updates Sidecar automatically.
3. Turn token values match the source events.
4. Session totals are not inflated by cumulative counter mistakes.
5. Context usage is displayed correctly where source data allows it.
6. Supported account quotas are shown without exposing credentials; unsupported or unauthenticated quota retrieval is explicitly unavailable.
7. No conversation contents need to leave the machine.
8. Parser behavior is covered by synthetic fixtures and tests, including repeated usage snapshots, partial lines, malformed/unknown events, counter resets, compaction, and restart replay.
9. A replay of the same data does not change totals or duplicate model turns.
10. App-server task/turn boundaries are not silently treated as individual model requests.
11. Unavailable context, quota, or model-turn data is clearly labeled and not replaced with fabricated values.
