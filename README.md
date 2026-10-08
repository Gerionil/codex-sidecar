# Codex Sidecar

A passive macOS companion for Codex, with a menu-bar panel and a resizable
companion window sharing one manually selected local chat. Built with Swift 6,
SwiftUI and Foundation; no third-party runtime dependencies or metrics database.

## Current status

Stages 1–5 are implemented and locally merged. Stage 6 adds installed-profile
numeric validation, repository hygiene review and operating documentation.
Native interactive acceptance is **incomplete**: the computer-use channel failed
before providing an accessibility tree or screenshot. Successful launch and
unit tests do not establish full GUI acceptance. See the dated
[validation record](docs/validation.md) for checks, limitations and the historical
Stage 5 default-root launch incident.

The freshly checked CLI profile is **0.160.1** on Apple Silicon macOS 27.0.1.
The declared deployment floor is macOS 14; macOS 14 and Intel runtime support
have not been tested. Windows and Linux are outside this release. This is a local,
unsigned development build. Publication, license selection, signing and
notarization require separate owner decisions; no project license is selected.

## Build, test and package

Use a Swift 6 toolchain with the macOS SDK and XCTest available. The validated
host uses Apple Swift 6.4 with the active Xcode SDK 27.0. No tools are installed
by these instructions.

```sh
swift test
swift build -c release
scripts/package-app.sh
open 'build/Codex Sidecar.app'
```

For restricted environments like the one used for validation, project-local
compiler caches and SwiftPM's `--disable-sandbox` were needed:

```sh
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache"
swift test --disable-sandbox
swift build -c release --disable-sandbox
scripts/package-app.sh --disable-sandbox
```

The packaging script copies the release executable and Info.plist into
`build/Codex Sidecar.app`. Build outputs and local validation scratch files are
ignored. Packaging does not install, sign, notarize, upload or enable autostart.
The validation sandbox also required narrowly approved execution outside it for
native launch and tests; `--disable-sandbox` alone does not lift the host's outer
sandbox restrictions. Check command failures before treating the app as built.

## Launch and settings

Local Settings allow a Codex root, executable override and offline mode. Root
precedence is explicit override, inherited `CODEX_HOME`, then the current user's
`.codex` directory. A GUI launch may not inherit the shell environment. The same
resolved root is supplied to session discovery and the owned quota process.

Executable discovery uses an explicit override, safe absolute PATH entries, then
recognized installed application bundles. Sidecar runs a bounded `--version`
verification without a shell before using an executable. Missing or unverifiable
executables produce an unavailable state. Versions other than the reference
profile are labeled unvalidated; a version match alone is not proof of compatible
capabilities or every possible rollout shape.

Optional launch overrides (replace the example paths with your own):

```sh
open -n 'build/Codex Sidecar.app' --args \
  --isolated-settings \
  --codex-root /absolute/path/to/test-codex-home \
  --codex-executable /absolute/path/to/codex \
  --offline
```

`--isolated-settings` starts from default local settings without reading or
persisting saved Sidecar preferences. `--codex-root` and `--codex-executable`
override their settings; `--offline` disables quotas. For synthetic GUI checks,
provide a test-owned root and fake executable explicitly and verify the running
instance's arguments before binding any UI tool that could auto-launch an app.

Choose a chat manually from **Selected chat** in either surface. Descriptors use
local project/session metadata, without manufacturing titles from prompts.
Selection stays pinned until changed; recent activity is a suggestion, not
foreground-chat detection. Changing a chat changes its usage, not current-account
quotas. **Open window** is implemented to open/focus the companion; closing the
window keeps the menu-bar app running. **Quit** is implemented to stop owned
readers and quota workers. Native focus/reuse/close/reopen/Quit behavior still
needs interactive acceptance.

## Metrics and data boundaries

- Observed tokens sum valid, unique, owned completed-response records present in
  inspected sources. They are not guaranteed lifetime usage or an account bill.
  Reported cumulative usage and reconciliation are shown separately.
- Cached input is included in input; reasoning is included in output. They are
  not added again to total. Cache rate uses summed cached/input values across the
  same validated records. Missing breakdown stays unavailable, never zero.
- Tasks, model requests and tool calls have different scopes. Interrupted or
  failed activity without reported usage has no invented cost. Tool association
  uses validated stream order and preserves ambiguity; inner commands are not
  inspected for read/search counts.
- **Current context usage is unavailable.** Model context window and last-request
  footprint are separate historical metrics. Configured model is not guaranteed
  actual-model attribution through fallback or compaction. No parent/child totals.
- **Current account limits** show dynamic buckets and only returned windows.
  Duration 300 minutes is labeled 5h; 10,080 minutes is Weekly. Weekly-only,
  multiple buckets, duplicate-duration slots and null fields are valid shapes.
  Reset timestamps use Unix seconds. Missing windows are not fabricated.

Files are read locally and incrementally, with bounded framing and periodic
reconciliation. Sidecar retains normalized metrics in memory, not transcripts,
raw logs, credentials or account replies. Settings persist only local overrides,
session/bucket selection and offline preference. Restart rebuilds metrics from
original sources; source loss and partial history remain explicit. Large-stream reader measurements and limitations
are recorded in [validation](docs/validation.md).

## Offline and network behavior

Offline mode keeps local session reading available and starts no quota child.
When online, a separately owned `codex app-server` uses Codex-managed authentication
and network traffic for passive account/quota reads, with process-only analytics
disabled. Sidecar does not open authentication files, export credentials, perform
inference, manage chats, login/logout, reset credits or call private quota HTTP
endpoints. Codex itself may perform normal runtime housekeeping or credential
refresh; its internal state is not certified immutable.

Quota polling is independent of chat selection (normally every 60 seconds), with
bounded retries and explicit loading/unavailable/stale/error states. A startup
account notification can invalidate the initial read; scheduled recovery uses
the same process. Last good values remain labeled stale/error after applicable
failures. A past reset is a refresh hint, not proof that usage or permission resets.
Cross-process notification delivery and real account-change behavior remain
unverified; deterministic fake-transport tests cover these state transitions.

## Project references

- [Specification](SPEC.md) — approved product and accounting boundaries
- [Implementation plan](IMPLEMENTATION_PLAN.md) — stage scope and acceptance
- [Research](docs/research.md) — dated schema/source and installed-profile evidence
- [Validation](docs/validation.md) — fresh checks and unresolved acceptance
- [Working instructions](AGENTS.md) — language, privacy and branch workflow

Starter notes and prompts are historical. Current implementation status is above;
the specification supersedes earlier starter hypotheses.
