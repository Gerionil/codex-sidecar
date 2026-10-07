# Codex Sidecar — Initial Development Session

You are working on a new open-source pet project called **Codex Sidecar**.

Do not start implementing the application immediately. Follow this order:
**research → SPEC.md → IMPLEMENTATION_PLAN.md → implementation**.

## Step 1 — Read the project context

Read completely:

- `README.md`
- `docs/idea.md`
- `docs/research.md`
- `docs/mvp.md`
- `docs/architecture.md`
- `.gitignore`

Treat the notes as product direction and hypotheses, not established technical
facts. Do not assume a technology stack has already been selected.

## Product goal

Build a local-first companion for Codex App that shows:

- 5-hour and weekly account quotas with reset times
- current context usage and model context window where reliably available
- session token totals and cache hit rate
- input, cached input, output, reasoning, and total tokens for each model request
- associated tool activity where it can be reconstructed reliably

The accounting unit called a **model turn** means one model request/inference
cycle. It is not necessarily an app-server turn, a user message, or a tool call.
Do not invent a separate token cost for each read/search/shell operation.

## Step 2 — Research the local Codex installation

Inspect the installed version and supported configuration read-only. Locate the
actual data root (including `CODEX_HOME` if configured), with
`~/.codex/sessions/**/*.jsonl` as the default candidate.

Read only a small sample needed to establish schemas. Do not print, copy into the
repository, or upload real prompts, source code, tool output, credentials, or
session files. Use synthetic fixtures to document findings.

Verify candidate event/field names and their semantics:

- `token_count`
- `last_token_usage`
- `total_token_usage`
- `model_context_window`
- `turn_context`
- `response_item`
- `task_started`
- `task_complete`

Determine:

1. Which counters are cumulative and which belong to one model request?
2. Are cached input/reasoning subsets of input/output?
3. Can individual model requests be identified and deduplicated?
4. How do compaction, interruption, resume/fork, reset, and repeated snapshots behave?
5. Which field measures current context rather than cumulative session usage?
6. How can tools be associated with requests without claiming unsupported costs?
7. Can the active desktop chat be identified reliably, or is manual selection needed?
8. Are parent/child session totals independent or overlapping?

Record evidence, Codex version, uncertainties, and unsupported metrics.
Do not modify Codex App or its data.

## Step 3 — Research account quotas

Use current official Codex documentation and the installed app-server protocol.
Investigate `codex app-server` as a separate quota provider, particularly
`account/rateLimits/read` and supported notifications.

Verify authentication requirements, returned window durations, used vs remaining
percentages, reset timestamp units, multiple buckets, missing values, and stale
data. Do not calculate official quota percentages from local token counts.

A locally started app-server may not observe another process's desktop threads.
Verify that capability rather than assuming it. Do not start model inference,
resume/modify user chats, change login/account settings, or patch Codex App merely
to investigate statistics.

Quota access may require Codex-managed network calls to OpenAI. Keep transcript
parsing/storage local and introduce no Sidecar telemetry or cloud backend.

## Step 4 — Research existing projects

Start with the candidates in `docs/research.md`:

- CodexScope
- Codex Usage Desktop
- Codex Token Monitor
- Codex Monitor
- Codex Usage Bar / similar menu-bar tools
- Codex-Claude Token Dashboard / Codex-Claude-Token-dashboard

Resolve canonical repositories; do not guess identities from names. Prioritize
CodexScope, Codex Token Monitor, and the Codex-Claude dashboard candidate.

For each useful project, record URL, inspected commit/version, date, architecture,
quota source, parser/accounting logic, active-session detection, edge cases,
license, and attribution/reuse constraints. Mark unresolved identities explicitly.
Do not copy code before verifying license obligations.

Update `docs/research.md` with findings and distinguish evidence from inference.

## Step 5 — Create SPEC.md after research

Only after completing the research, create `SPEC.md` in the project root.
It must include:

- problem, intended user, and MVP scope/non-goals
- verified data sources and compatibility limits
- exact definitions of session, user/task turn, and model request
- token accounting rules, deduplication, subsets, and reconciliation
- context and quota semantics, unavailable/stale/error states
- active-session selection and manual fallback
- minimal UI, privacy and network behavior
- acceptance criteria and meaningful test scenarios
- proposed technology stack with evidence and tradeoffs
- unresolved questions, with blockers called out before dependent work

Evaluate Swift/SwiftUI and Tauri for the initial macOS companion; choose based on
research, implementation simplicity, and maintainability. Do not add a database,
backend, or cross-platform scope unless the MVP needs it.

## Step 6 — Create IMPLEMENTATION_PLAN.md after SPEC.md

Once the specification is written and internally consistent, create
`IMPLEMENTATION_PLAN.md` in the project root, derived from that specification.

Break implementation into small, reviewable stages with deliverables and
verification criteria. Cover:

1. synthetic fixtures and accounting/parser correctness
2. model-request reconstruction and derived session state
3. incremental file reading, discovery, and session selection
4. separate quota provider with unavailable/stale/error handling
5. minimal companion UI and real-time updates
6. validation against the installed version and public-repository hygiene

Prioritize correct accounting before UI polish. Include tests for cumulative
counters, duplicates, partial/malformed lines, unknown events, reset/replay,
compaction, interruption, and unavailable metrics.

## Step 7 — Only then implement

Present the research findings, SPEC.md, and IMPLEMENTATION_PLAN.md before starting
application implementation. Resolve blocking questions before dependent work.
Implement in the plan's order and verify each stage against its acceptance
criteria; do not silently expand scope.

Keep real session files, credentials, user-specific absolute paths, and transcripts
out of the repository. Track synthetic fixtures and dependency lockfiles.
Do not publish to GitHub, push, or deploy without a separate user request.
