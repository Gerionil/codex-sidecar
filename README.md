# Codex Sidecar

Codex Sidecar is a planned local-first macOS companion application for the Codex App.
The first release uses Swift/SwiftUI, with a menu-bar panel and a separate window
sharing one manually selected chat. Windows is a possible later phase.

Its goal is to make Codex usage transparent while you work by showing:

- dynamically returned account rate-limit buckets and windows
- window durations and reset times
- 5-hour / weekly labels when those durations are returned
- reported model context window and last-request footprint; exact current context is unavailable
- session token totals
- input / cached input / output / reasoning tokens
- cache hit rate
- token usage per completed model request
- tool activity associated with each model request where it can be reconstructed reliably

The project is intended to become an open-source tool.

## Core idea

Codex Sidecar treats an observed **completed model request** as the main accounting unit, with tool activity shown where association can be reconstructed reliably.

Illustrative example (synthetic values, not a verified live readout):

```text
CODEX SIDECAR

CURRENT ACCOUNT LIMITS
Weekly   █████░░░░░ 75% remaining
Only windows returned by Codex appear, including 5h when available.

CONTEXT
Current usage         Not available
Last request          60 tokens

SELECTED CHAT
sample-project        Started Jan 1, 12:00
Observed tokens       180
Cache hit             66.67%

MODEL REQUESTS

Latest completed response
Input          50
Cached         40   included in input
Output         10
Reasoning       2   included in output
Total          60

Tools:
functions.exec ×1
```

## Principles

- Local-first
- Privacy-preserving
- No modification or patching of Codex App
- Correct token accounting before UI polish
- Prefer public/local Codex interfaces where possible
- No credentials or conversation contents should be uploaded anywhere
- Open-source friendly

## Expected data sources

Potential sources include:

```text
~/.codex/sessions/**/*.jsonl
```

and, where supported:

```text
codex app-server
```

The exact APIs and event semantics must be verified against the currently installed Codex version.

## Project status

Research complete; platform and stack approved; application implementation has
not started. The mockup illustrates selection in both surfaces with synthetic data.

See:

- `docs/idea.md`
- `docs/research.md`
- `docs/mvp.md`
- `docs/architecture.md`

The first Codex development session should start with `START_PROMPT.md`.

Required order: research → `SPEC.md` → `IMPLEMENTATION_PLAN.md` → implementation. The first-session research is complete. The specification and implementation plan are ready for review; application implementation has not started.

- [Research findings](docs/research.md)
- [Specification](SPEC.md)
- [Implementation plan](IMPLEMENTATION_PLAN.md)
- [Working instructions and stage branches](AGENTS.md)
- [Next-session Stage 1 prompt](STAGE_1_PROMPT.md)

The verified profile provides completed-response accounting and passive account quotas. Exact current context and foreground-chat detection remain unavailable; the MVP uses manual chat selection. Swift/SwiftUI is the owner-approved macOS stack. Menu-bar and companion views share state and providers. Windows has no first-release commitment and requires real runtime acceptance before support is claimed. See the specification for metric scope and compatibility limits.
