# Product Idea

> Historical product-direction notes. Current behavior and limitations are described in the [README](../README.md), supported by [research.md](research.md) and [validation.md](validation.md). Illustrative layouts and technical hypotheses below are not live capability claims.

## Problem

Codex App provides useful usage information, but while actively working it is difficult to understand:

- how much of the 5-hour allowance remains
- how much of the weekly allowance remains
- when those limits reset
- how large the current context is
- how token usage changes over time
- which model turns consume the most tokens
- how much input is served from cache
- how individual agent cycles affect overall usage

Existing information is fragmented across Codex UI, local session files, CLI output, and third-party tools.

## Product

Codex Sidecar is a small companion application that stays alongside Codex App and exposes this information in real time.

It should not modify Codex App itself.

Conceptually:

```text
┌────────────────── CODEX ──────────────────┬───────────────┐
│                                          │ CODEX SIDECAR │
│ User prompt                              │               │
│                                          │ 5h       72%  │
│ Agent reads files                        │ Weekly   54%  │
│ Agent searches code                      │               │
│ Agent runs commands                      │ Context  55%  │
│                                          │               │
│ Agent continues reasoning                │ Turn #18      │
│                                          │ 123.2K tokens │
│                                          │               │
└──────────────────────────────────────────┴───────────────┘
```

## Main metrics

### Account usage

- 5-hour usage / remaining quota
- weekly usage / remaining quota
- quota reset timestamps

### Current context

- model context window
- estimated/current context usage
- context fill percentage

### Session

- total input tokens
- cached input tokens
- output tokens
- reasoning tokens
- total tokens
- cache hit rate

### Model turns

Each model turn should show, when available:

- input
- cached input
- output
- reasoning
- total
- model
- timestamp
- related tool activity

## Important distinction

The project should NOT pretend that a token cost can always be assigned to an individual tool invocation.

For example:

```text
read file
search
shell
```

may happen between two model requests.

The correct accounting unit is therefore:

```text
model turn
```

Tool calls can be associated with that turn, but not necessarily assigned separate token counts.

## Privacy

The preferred architecture is fully local.

Codex Sidecar should not require sending:

- prompts
- conversation contents
- source code
- auth tokens
- project files

to any external server.

## Future direction

Potential later features:

- per-project statistics
- daily / weekly token trends
- expensive prompt detection
- context growth visualization
- alerts when context approaches a configurable threshold
- multiple concurrent Codex sessions
- menu bar summary
- session history
- export of anonymized usage statistics

## Terminology and metric boundaries

A **model turn** in this product means one model request/inference cycle. A user
message or an app-server task/turn can contain several such cycles; do not assume
those boundaries are interchangeable.

Account quota, cumulative session usage, and current context occupancy are
separate metrics. Session tokens do not measure the current context and must not
be converted into official quota percentages.

Cached input may be included in input tokens, and reasoning output may be included
in output tokens. Verify this for the installed version; do not add those subsets
again to the total. Cache hit rate is cached input / input for the same validated
accounting scope, or unavailable when the denominator is zero or unknown.

Local-first means local parsing and storage. Retrieving account quotas may require
Codex-managed communication with OpenAI. Sidecar should have no separate analytics
or transcript-upload service.
