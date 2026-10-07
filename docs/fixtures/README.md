# Rate-limit research examples

These are documentation fixtures, not recorded transcripts or application code.

- `rate-limits-read.sanitized.json` preserves the field names and null/object shape
  observed through Codex CLI 0.160.1 on 2026-10-07. The one `codex` bucket, weekly
  primary duration (10,080 minutes), and null secondary reflect the observation.
  Percentages, timestamps, plan, credit/spend-control values, RPC ID, and permission
  values are invented. The account identifier is replaced with `<redacted>`.
- `rate-limits-updated.synthetic.json` is entirely synthetic, illustrating the
  installed sparse notification schema. No rate-limit notification was observed
  during the bounded passive probe. Null metadata here must not erase a previously
  read full bucket; the proposed provider schedules a full refetch.

No auth tokens, real account identifiers, credentials, personal usage values,
private paths, or session content are present. These shapes are version-specific;
the update example is not evidence of cross-process push delivery.
