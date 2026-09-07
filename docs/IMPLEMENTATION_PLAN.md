# Cloud storage implementation handoff

## Progress

Step 2 is implemented in the current working tree and awaits review. It adds the
runtime Rust and JavaScript API, command permissions, an iCloud Documents
provider, and an explicit `waitForUpload` operation. The iCloud provider was
compiled through Tauri's iOS package build and the Rust/JavaScript contracts
were checked. Its Swift test target covers validation and DTO serialization, but
has not run in a generated Tauri host package. The provider has not yet run in
an entitled iOS host app or against a real iCloud account. Android
deliberately reports `googleDrive/unavailable` until Step 3 is complete.

The selected implementation choices are:

- Writes resolve after a coordinated local iCloud commit. `waitForUpload` observes
  iCloud metadata for remote confirmation, with a 60-second default and a
  1–300-second bound.
- The public API uses `Uint8Array` / `Vec<u8>`. The private JSON bridge carries
  byte arrays, and this first release caps whole-file transfers at 10 MiB.
- `containerIdentifier` is an optional typed plugin configuration. If omitted,
  iCloud uses the first entitled container.
- iCloud state changes run on a serial queue. Creates stage under a private
  temporary directory and atomically move the completed entry into place.
- Cursors are versioned, opaque base64-URL values bound to the current local
  connection. Reconnects and iCloud identity changes invalidate them.

Suggested review commit:

```text
feat: implement iCloud file storage
```

## Objective and working agreement

Implement the first publishable version of `tauri-plugin-cloud-storage` here,
using iCloud on iOS and Google Drive app data on Android. Build a generic,
open-source file API that a wallet can use for a simple backup toggle and a
selection of existing backup files.

- Work only in this repository unless the user separately requests wallet changes.
- Do not stage, commit, push, publish, or trigger release workflows yourself.
- Work in reviewable steps. After each step, report changes, validation, remaining
  limitations, and one concise conventional commit message. Let the user review
  and commit before proceeding to the next step.
- Keep the README and its basic structure. Update its support claims as features
  become real and tested.
- Mobile-only runtime. Host-side models/tests are intentional; do not add desktop
  storage, desktop fallbacks, or pretend desktop support.
- Do not import the abandoned implementation from
  `daniel-mader/plugins-workspace`. It was experimental and is explicitly discarded.
- Do not introduce wallet-specific filenames, encryption, scheduling, retention,
  password prompts, or UI into the plugin.
- No delegation/sub-agents are requested by this plan.

## Starting point

Plan prepared on 2026-09-07 against commit:

```text
617469a feat: define cloud storage API contract
```

The working tree was clean before this plan was added. Recheck status and local
instructions when resuming; do not overwrite subsequent user changes.

Implemented:

- Rust models and validation in `src/models.rs`; structured errors in `src/error.rs`.
- Runtime TypeScript bindings and a matching Rust `CloudStorageExt` API.
- Mobile command wiring and generated per-command permissions, with no default grants.
- An iCloud Documents provider outside the Swift Tauri adapter, plus Swift core tests.
- An explicit Android `unavailable` provider until Google Drive is implemented.
- Mobile-only registration in `src/lib.rs` / `src/mobile.rs`, using Tauri's
  asynchronous mobile-plugin bridge.
- Correct Cargo/npm package names and Apache-2.0 metadata.
- Five Rust contract tests in `tests/contract.rs`, and `pnpm-lock.yaml`.
- README describing the working iCloud interface, its configuration, and its
  remaining validation boundary.

Not implemented:

- Google Drive authorization and Android storage operations.
- An entitled iOS host build and real-device/account iCloud validation.
- A working example, CI, or publishing workflows.

Previous validation passed: `cargo test --offline` (four tests), `pnpm check`,
`pnpm build`, and `git diff --check`. These were host-side checks, not proof of
mobile compilation or cloud behavior. Xcode 26.2 and iOS/Android Rust targets were
installed in the previous session; check the current toolchain rather than assume.
Declared Rust 1.77.2 / Tauri 2.8 / iOS 13 / Android API 24 minimums remain to be
verified against the dependencies actually used.

## Agreed public contract

Read the source types and README before editing. Keep Rust and TypeScript aligned.

| JavaScript operation | Intended Rust method | Result |
| --- | --- | --- |
| `getStatus()` | `get_status()` | `StorageStatus` |
| `connect()` | `connect()` | `StorageStatus` |
| `disconnect()` | `disconnect()` | unit |
| `listFiles(options?)` | `list_files(options)` | `FilePage` |
| `createFile({ name, data })` | `create_file(options)` | `CloudFile` |
| `readFile(id)` | `read_file(id)` | bytes |
| `updateFile({ id, data })` | `update_file(options)` | `CloudFile` |
| `deleteFile(id)` | `delete_file(id)` | unit |
| `waitForUpload({ id, timeoutMs? })` | `wait_for_upload(options)` | unit |

Required semantics:

- Named JavaScript exports and an equivalent Rust `CloudStorageExt` API.
- Public bytes are `Uint8Array` / `Vec<u8>`; callers do not encode provider payloads.
- Provider identifiers are `iCloud` and `googleDrive`.
- Status is `unavailable`, `disconnected`, or `connected`; it is not online/sync status.
- Status checks never show consent UI. Connection is an explicit user action.
- Disconnect is a local access switch, not OAuth revocation, account sign-out,
  deletion, or cancellation of existing operations. Already-written iCloud files
  can continue syncing through the OS.
- Account changes invalidate the connection; reconnect explicitly. Never silently
  move an operation or cursor to another account.
- Files have opaque IDs, display names, byte sizes, and UTC RFC 3339 modification times.
- Names are not paths or unique keys. Duplicate names and empty files are valid.
  Creation always produces a new file; updating preserves ID and name.
- Listing is unordered: 100 items by default, 1–1000 requested, optional opaque
  cursor. Empty intermediate pages are possible. No atomic multi-page snapshot.
- Missing files, including deletes/updates, produce `notFound`.
- Match structured error codes, not diagnostic wording. Preserve native errors
  through Rust rather than flattening them into strings.
- Store only files in the app's provider namespace. IDs/cursors supplied by callers
  are untrusted; basic Rust ID validation alone is not an ownership check.
- iCloud and Google Drive are separate stores, not cross-platform synchronization.

## Step 2 implementation decisions

These decisions are implemented above and retained here as rationale for future
work. Preserve the documented behavior unless a later version intentionally
changes the public contract.

1. **Upload completion.** Keep iCloud file writes as coordinated local commits,
   explicitly distinguished from confirmed remote upload. Recommended addition:
   a bounded `waitForUpload(id, options)` operation, with matching Rust API, which
   completes immediately for a successfully uploaded Drive file and waits for
   iCloud upload confirmation. Verify Apple's observability and error semantics
   first. If a different sync-status API is better supported, document the choice.
   The wallet must have a way to avoid claiming an offline local file is safely
   backed up remotely. Do not change `connected` to mean uploaded.
2. **Binary transport and limits.** Recommended baseline: public bytes, internal
   base64 DTOs between Rust and native code, and explicit conversion of JavaScript
   typed arrays before JSON IPC. Validate native reads as well as writes. Set and
   document a bounded first-release file size (proposed: 10 MiB), accounting for
   encoding/copy overhead; reject oversized content with a documented error.
   Keep transport encoding private. Streaming can be a later API addition.
3. **Configuration.** Add typed, optional iOS container selection in the host
   plugin configuration; absent means the first entitled container. Google OAuth
   project/package/signing configuration belongs to each consuming app. Never
   embed a reusable client secret, service account, or publisher-owned OAuth app.
4. **Concurrency and recovery.** Serialize state transitions and protect active
   account context. Define behavior for simultaneous connects, disconnect during
   authorization, interrupted writes, and provider-side file conflicts. Prefer
   immutable create operations for backups; do not promise transactional syncing
   or automatic conflict merging.
5. **Identity and pagination.** Bind connection state and cursors to a stable native
   account identity and namespace. Determine which supported provider APIs expose
   that identity; do not treat an access token as a stable account identifier.
   Version and validate plugin cursors; document expiration and invalid-cursor errors.

## Step 2 — iCloud and the usable runtime API

Suggested commit:

```text
feat: implement iCloud file storage
```

### Rust / JavaScript / permissions

- Retain and manage `PluginHandle<R>`; expose `CloudStorage<R>` and `CloudStorageExt`.
- Add async command handlers and matching JS exports. Use asynchronous mobile calls
  if available at the verified minimum Tauri version; otherwise use a supported
  nonblocking bridge. Do not block the main thread or an async executor on cloud I/O.
- Validate in the shared Rust API so Rust callers receive the same validation as JS.
- Native entry points must validate independently where they accept paths/IDs or
  can be invoked without passing through the public Rust wrapper.
- Implement and test native DTO conversions, including `{}`/unit response handling,
  byte encoding, timestamp serialization, and native error-code mapping.
- Add command names to `build.rs`, regenerate permissions using the build tooling,
  and document explicit capability grants. Keep default permissions empty; no
  implicit authorization or broad file access. Ensure denied calls do not reach native code.
- Keep Android visibly unavailable until implemented. If shared commands require
  intermediate Android handlers, reject explicitly with `unavailable`; never return
  successful dummy files, metadata, or authentication states.

### iCloud implementation

- Put provider logic outside the Swift Tauri adapter so it can be tested.
- Inspect the host app's iCloud identity and entitled ubiquity container off the
  main thread. Observe identity changes and clear local connection state.
- Use an isolated plugin directory in the selected app container. Support duplicate
  display names without filename collisions. A recommended layout is a generated
  UUID directory per file with the original display name inside; prove discovery,
  crash recovery, and placeholder handling before adopting it.
- IDs are not absolute paths. Validate UUIDs/namespace and reject traversal,
  symlink escapes, foreign files, and malformed cursor inputs.
- Use coordinated file access and atomic replacement. Do not overwrite an existing
  object during create or accidentally create a missing object during update.
- Discover cloud-only files using supported iCloud metadata APIs; a plain local
  directory/exists check is insufficient for restore on a fresh device.
- Handle downloading on reads, upload observation, offline operation, bounded waits,
  unresolved versions, quota errors, and account removal without hanging invocations.
- Preserve empty/binary files, accurate sizes, timestamps, and permanent deletion.
- Add host entitlement/container/provisioning instructions. Plugin registration
  alone cannot enable iCloud for the consuming application.

### Acceptance before user review

- Host contract tests plus meaningful JS IPC/byte/error tests pass.
- Swift provider tests cover filesystem containment, duplicate names, empty/binary
  data, atomic replacement, and failure cleanup with a testable storage abstraction.
- Compile in a minimal iOS host app. A host `cargo test` skips `#[cfg(mobile)]` and
  cannot substitute for that build. Do not report a stub/mock as a native build.
- When devices/accounts are available: create, list, read, update, delete, reconnect,
  and recover on another device; verify that offline writes are not reported as
  confirmed uploads. Record any unavailable device checks as outstanding.
- README accurately reflects iOS progress and Android's unfinished state.

Current status: the Rust contract tests, JavaScript typecheck/build, and both
mobile Rust target checks pass. The iOS target compiles the package containing
the provider and adapter. An actual iCloud device/account test and the Swift
XCTest target in a generated Tauri iOS host remain outstanding; do not claim
remote-upload, discovery, or recovery behavior as device-verified yet.

## Step 3 — Android authorization and Google Drive app data

Suggested commit:

```text
feat: add Google Drive storage on Android
```

- Implement separate Kotlin provider and Tauri adapter layers.
- Use Google Identity `AuthorizationClient` with only the `drive.appdata` scope.
  Use Drive REST v3, not the retired Drive Android API or application-default
  credentials intended for server environments. Credential Manager alone does
  not authorize Drive access.
- Handle consent using Tauri's `startIntentSenderForResult` / activity callback.
  Resolve or reject each invocation exactly once, after completion. Handle
  cancellation, revoked grants, expired access, process/activity lifecycle, and
  concurrent calls. Background file operations must not unexpectedly launch consent.
- Keep tokens native; never log them or return them to JS. Obtain fresh access
  through supported authorization APIs rather than inventing refresh-token storage.
- Bind work to the connected account; do not silently choose another account on
  retry. Missing Play services, unavailable accounts, and rejected authorization
  must produce actionable structured errors/status.
- Implement create in `appDataFolder`, list with `spaces=appDataFolder`, download,
  update, and permanent delete. Request the metadata required by `CloudFile`.
- Before reading/updating/deleting an arbitrary supplied ID, verify it is an allowed
  app-data object. Exclude folders or unsupported object types from file listings.
- Support pagination and restore after reinstall on the same app/account. Do not
  assume Drive names are unique or use name-based upsert.
- Use finite network timeouts, bounded response bodies, and sensible throttling
  handling. Do not blindly retry non-idempotent creates after uncertain failures:
  a lost response can still mean a file was created remotely.
- Update Gradle dependencies, manifest Internet permission, release shrinker rules,
  and minimum platform versions based on current official documentation and builds.
- Document per-app Cloud project / Drive API / OAuth consent setup and Android
  OAuth clients for debug, release, and Play App Signing certificates. Explain
  what is needed to move the consuming app beyond OAuth testing mode.

Acceptance: Android build plus tests for callback completion/cancellation, binary
transport, pagination, ownership, error mapping, account changes, token expiration,
rate limiting, and uncertain create outcomes. Test actual create-to-restore round
trips on a Google-enabled device, including a second installation/device. Verify
release signing configuration separately from debug. Update support claims only
with evidence; document unavailable external checks.

## Step 4 — mobile examples, integration validation, and CI

Suggested commit:

```text
test: cover mobile cloud storage lifecycle
```


- Add a small mobile example with local plugin dependencies, basic HTML/TypeScript,
  and no wallet dependencies. Exercise both JavaScript and Rust API entry points.
- Show provider/connection status, explicit connect/disconnect, paginated listing,
  binary file actions, and upload status. Keep this a developer example, not a
  backup product. Include configuration templates with no credentials or signing
  artifacts. The original example was deliberately removed; introduce only what
  is necessary for reproducible mobile validation.
- Add reproducible host/JS checks and Android/iOS compile jobs where supported.
  Use the checked-in pnpm lockfile. Add real native test targets: the original
  template tests were removed and the Swift package currently has no test target.
- Test the documented minimum versions or raise them honestly. In particular,
  a broad Cargo requirement can resolve to newer dependencies with a higher MSRV.
- Record a manual device matrix for first authorization, denied authorization,
  offline launch/write/read, empty and maximum-size files, pagination, cloud-only
  files, conflicting changes, quota exhaustion, restart/reinstall, account switch,
  missing configuration, and disconnect while work is in flight.
- Clear separation in results: unit/mocked tests, native compilation, and actual
  cloud/device tests. Before release, both real providers need end-to-end evidence.

## Step 5 — package and release preparation

Suggested commit:

```text
ci: prepare cloud storage prereleases
```

- Inspect the current `impierce/tauri-plugin-keystore` `alpha` branch (or local
  checkout) as the release model. Its release and publish workflows are manually
  dispatched; a GitHub release does not automatically publish packages.
- Add build, release dry-run, publish dry-run, release, and publish workflows plus
  semantic-release configuration. Modernize dependencies/authentication as needed
  after consulting current registry documentation; do not blindly copy old tokens
  or action versions. OIDC provenance is not the same as trusted publishing auth.
- Build/test and verify Cargo/npm contents before release. Cargo must include the
  native sources, permissions, and build script; npm must include working ESM/CJS
  bindings and declarations. Validate installing the actual package artifacts in
  the mobile example so workspace-only paths cannot hide packaging failures.
- Verify package ownership/access for the names already declared in manifests.
  Record external credentials/trusted-publisher setup for the user without
  requesting or reading secrets unnecessarily.
- Select the next version from semantic-release's dry-run result. Initial target
  is `2.0.0-alpha.1`; align Cargo/npm manifests with the actual selected tag.
- Publish prereleases explicitly under npm's `alpha` dist-tag. Release and both
  registry publishes must refer to the same tested commit/tag. Prevent accidental
  publishing from a moving branch or mismatched manifests.
- Final README: accurate platform support, verified requirements, real install/API
  examples, capability configuration, provider setup, completion semantics, size
  limits, recovery limitations, and manual release instructions.
- No publish or release dispatch by the implementing model. Give the user precise
  review and manual release instructions. Registry dry-run commands are acceptable;
  actual publishing is not authorized.

A separate user-made version commit may use:

```text
build: release version v2.0.0-alpha.1
```

## Wallet context for a subsequent, separately requested integration

Repository: `impierce/identity-wallet`, branch `feat/cloud-backup`.
It was available locally at `/Users/daniel/dev/impierce/identity-wallet` and had
unrelated uncommitted changes; leave those untouched.

Useful files:

- `identity-wallet/src/state/backup/reducers/create.rs`
- `identity-wallet/src/state/backup/reducers/enable.rs`
- `identity-wallet/src/state/backup/actions/create.rs`
- `unime/src-tauri/Cargo.toml`

The wallet currently creates encrypted bytes in Rust and writes them locally;
its enable reducer is a placeholder. Its Tauri manifest still references the old
workspace plugin path. Later integration should move to this plugin, persist the
backup preference in the wallet, call connect on explicit enable, create immutable
snapshot files, collect/sort listing pages, and restore by ID.

There is a concrete separate blocker before shipping wallet backups: the inspected
prototype uses a fixed AES-GCM nonce, a simple SHA-256 password hash, and concatenates
files without a recovery format. Do not copy those choices into the plugin or imply
that transport correctness makes that backup format production-ready. A wallet
integration needs a versioned, authenticated, recoverable encrypted archive with
proper nonce/key derivation and tests. Keep that work outside this plugin's scope.

## Reference starting points

Verify current official API signatures/dependencies while implementing:

- Tauri mobile plugin development: https://v2.tauri.app/develop/plugins/
- Asynchronous mobile plugin bridge introduced in Tauri 2.8:
  https://v2.tauri.app/release/tauri/v2.8.0/
- Google authorization: https://developer.android.com/identity/authorization
- Drive app data: https://developers.google.com/workspace/drive/api/guides/appdata
- Drive scopes: https://developers.google.com/workspace/drive/api/guides/api-specific-auth
- Apple iCloud setup: https://developer.apple.com/documentation/xcode/configuring-icloud-services
- Keystore release model: https://github.com/impierce/tauri-plugin-keystore/tree/alpha

Do not treat a documentation example using server credentials as suitable for an
Android user account. Do not infer cloud readiness from local filesystem tests.

## Resume checklist

1. Read this plan, README, types, current git status, and applicable local instructions.
2. Review and commit Step 2 if it is accepted, then begin Step 3 without changing
   the completed iCloud contract accidentally.
3. Implement and validate a coherent step; keep unresolved provider claims explicit.
4. Report changed behavior, checks, limitations, and the suggested commit message.
5. Update this plan with completed steps and concrete outstanding checks so the
   next model can continue without reconstructing the history.
