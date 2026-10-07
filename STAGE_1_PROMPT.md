# Stage 1 Implementation Prompt

Read `AGENTS.md`, `SPEC.md`, `IMPLEMENTATION_PLAN.md` and `docs/research.md`.
Implement only **Stage 1 — Synthetic fixtures and selective parser correctness**.
Create `stage/1-parser` from `main`, or continue that branch if it already exists;
preserve existing changes. Use Swift 6, macOS 14+, Foundation, XCTest and SwiftPM,
with library/test targets only and no external dependencies.

Follow the stage's synthetic fixtures, selective decoding, counter validation
and privacy requirements. Run the required focused tests and full `swift test`;
record actual results and limitations in `docs/validation.md`. Keep project
artifacts in English and our conversation in Russian. Commit the completed stage
locally, report the result, and stop before Stage 2. Do not implement UI or live
quotas, copy real logs/credentials, install tools, push or merge.
