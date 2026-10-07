# Synthetic rollout fixtures

Every fixture was authored from scratch for Stage 1. No real rollout, credentials,
account data, prompt, tool payload, or private filesystem path was read or copied.
The owning UUID, task/response/call IDs, timestamps, model label, and numbers are
invented. `PRIVATE_MARKER` is deliberately synthetic text used to detect retention
of ignored fields and error payloads.

- `native-two-requests`: SPEC §9's 120- and 60-token records in one task, their
  cumulative values and mirrored snapshots, plus lifecycle/model/tool metadata.
- `unknown-and-sensitive`: unknown/transcript events, tool arguments/output, and
  an ignored extra native-record field containing the marker.
- `malformed`: one intentionally invalid complete JSON line followed by valid usage.
- `usage-missing-fields`: absent breakdown, null breakdown, and explicit zeros.
- `usage-invalid`: subset violations, negative and fractional counters,
  contradictory total, out-of-range Int64, and input/output addition overflow.

Resources describe the planned native rollout profile corresponding to the
0.160.1 research. They do not establish live compatibility or completed accounting.
The Stage 1 suite runs with the selected Xcode XCTest framework. See
`docs/validation.md` for fresh results and the historical Command Line Tools gate.
