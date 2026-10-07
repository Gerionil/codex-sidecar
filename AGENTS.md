# Codex Sidecar Working Instructions

## Language and scope

- Use Russian in conversation with the owner. Keep documentation, UI, code,
  comments, tests, commit messages and public artifacts in English.
- Read `SPEC.md`, `IMPLEMENTATION_PLAN.md` and the relevant research before work.
  `SPEC.md` supersedes historical starter hypotheses.
- Implement only the stage explicitly requested by the owner. Stop before the
  next stage and report deliverables, checks and remaining limitations.
- macOS-first: Swift 6, macOS 14+, SwiftUI, Foundation, XCTest and SwiftPM.
  Windows and third-party runtime dependencies are outside the first release.

## Git workflow

- `main` is the integration branch. Do not implement stages directly on `main`.
- Start each stage from the current `main` after its dependencies have been
  accepted and merged. Create its branch when beginning that stage, rather than
  creating all stage branches from the initial documentation commit.
- Branch names:
  - Stage 1: `stage/1-parser`
  - Stage 2: `stage/2-session-model`
  - Stage 3: `stage/3-session-reader`
  - Stage 4: `stage/4-quotas`
  - Stage 5: `stage/5-native-ui`
  - Stage 6: `stage/6-validation`
- Inspect the working tree before switching. Preserve existing work; do not
  reset, discard or overwrite unrelated changes. Reuse an existing stage branch
  when continuing that stage; never reset it to `main`.
- Use small English Conventional Commits. Local stage commits are authorized
  when implementing a requested stage. Do not add `Co-Authored-By` trailers.
- Push, merge, publish, change repository visibility or delete branches only
  when separately requested by the owner. Repository creation and the initial
  documentation upload do not authorize later stage pushes or merges.
- Retain completed branches unless the owner asks to delete them.

## Data and verification

- Keep Codex files/configuration read-only. Never copy credentials, real logs,
  prompts, tool payloads, private paths or account identifiers into the repository.
- Author fixtures synthetically. Preserve null/unknown values and counter subset
  semantics. Do not fabricate exact context or a mandatory 5h/Weekly pair.
- Run checks required by the requested stage; record fresh results in
  `docs/validation.md`. Do not mark later stages complete or start live inference
  merely to generate test data.
- Use Context7 for current library/framework/SDK/API/CLI/cloud documentation:
  resolve the library first, then query the relevant concept. This does not
  require re-running the completed product research for unrelated edits.
