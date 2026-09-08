# Tauri Plugin Cloud Storage

[![semantic-release: angular](https://img.shields.io/badge/semantic--release-angular-e10079?logo=semantic-release)](https://github.com/semantic-release/semantic-release)
[![Crates.io Version](https://img.shields.io/crates/v/tauri-plugin-cloud-storage)](https://crates.io/crates/tauri-plugin-cloud-storage)
[![NPM Version](https://img.shields.io/npm/v/%40impierce%2Ftauri-plugin-cloud-storage)](https://www.npmjs.com/package/@impierce/tauri-plugin-cloud-storage)

---

App-scoped cloud file storage for Tauri mobile apps, using Google Drive on Android
and iCloud on iOS. The public interface operates on files and opaque bytes;
applications own their data format, encryption, backup policy, and user interface.

**Under development:** iCloud file operations are implemented, but they have not
yet been validated against a real iCloud account or device. Google Drive support,
examples, successful CI validation, and publishing readiness are still pending.
The package is not ready to publish or use for production backups.

| Platform | Supported |
| -------- | :-------: |
| Linux    |    ❌     |
| Windows  |    ❌     |
| macOS    |    ❌     |
| Android  | Google Drive planned |
| iOS      | iCloud Documents implemented; device validation pending |

## Installation

During development, use a local path dependency in `src-tauri/Cargo.toml`:

```toml
[target.'cfg(any(target_os = "android", target_os = "ios"))'.dependencies]
tauri-plugin-cloud-storage = { path = "../path/to/tauri-plugin-cloud-storage" }
```

Build the JavaScript package in this repository with `pnpm install && pnpm build`,
then install it in the consuming app:

```shell
pnpm add @impierce/tauri-plugin-cloud-storage@file:../path/to/tauri-plugin-cloud-storage
```

_This also works with the corresponding local-package commands in npm and yarn._
Registry installation instructions will be added with the first release.

## Requirements

- This plugin requires a **Rust version of 1.77.2 or higher**.
- The minimum supported Tauri version is **2.8.0**. It supplies the nonblocking
  mobile plugin bridge used by every cloud operation.
- The Android library targets Android 7 (**API level 24**) and higher. The Google Drive provider will require Google Play services and per-app OAuth configuration.
- The Swift package targets **iOS 13** and higher. The iCloud provider requires an iCloud container, entitlements, and provisioning in the consuming app.
- The final minimum versions will be confirmed through mobile builds before release.

## Usage

Plugin registration is mobile-only. In a project that also compiles for desktop,
guard registration with `#[cfg(mobile)]`:

```rust
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default();
    #[cfg(mobile)]
    let builder = builder.plugin(tauri_plugin_cloud_storage::init());
    builder
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

### Public API contract

The JavaScript API is defined in [`guest-js/index.ts`](guest-js/index.ts), with
corresponding Rust models in [`src/models.rs`](src/models.rs) and an equivalent
Rust `CloudStorageExt` extension. iCloud implements every operation below;
Android currently exposes `googleDrive/unavailable` for status and rejects all
other operations with `unavailable` until Step 3.

| Operation | Purpose |
| --- | --- |
| `getStatus()` | Inspect the provider and connection state without prompting. |
| `connect()` | Explicitly enable access; may show Google account selection/consent. |
| `disconnect()` | Disable local plugin access without deleting cloud data. |
| `listFiles({ pageSize?, cursor? })` | List a page of file metadata. |
| `createFile({ name, data })` | Create a distinct file from bytes and return its metadata. |
| `readFile(id)` | Read file bytes. |
| `updateFile({ id, data })` | Replace contents, preserving the ID and name. |
| `deleteFile(id)` | Permanently delete a file. |
| `waitForUpload({ id, timeoutMs? })` | Wait for provider-confirmed upload. |

Files have an opaque `id`, display `name`, byte `size`, and UTC RFC 3339
`modifiedAt`. IDs belong to one provider, app, and account. Names are portable
filenames, not paths or unique keys; duplicate names are allowed. Creates never
implicitly overwrite another file. Empty files are valid.

Listings are unordered, with a default page size of 100 and a maximum of 1000.
Follow `nextCursor` until it is absent, including after empty intermediate pages.
Pagination does not promise an atomic snapshot while other devices modify files.
Applications can collect all pages and sort by `modifiedAt` for a backup picker.
The cursor is opaque, valid only for the current connection, and becomes invalid
after reconnecting or an iCloud account change.

The first release transfers whole files in memory and accepts files up to
**10 MiB**. `Uint8Array` values are converted to private JSON byte arrays for the
native bridge; callers do not encode them. Larger files require a later streaming
API.

Operations reject with a structured `{ code, message }` error. Applications should
match `code`, not provider-specific wording. Missing files return `notFound`;
updates do not silently create files. Simultaneous writes are not a transactional
sync system; immutable files created with `createFile` suit backup snapshots.

Connection state is separate from network connectivity and upload completion.
Disconnecting disables subsequent operations on this installation; it does not
cancel an in-flight operation, revoke Google's OAuth grant, sign out of iCloud,
or stop the OS from syncing already-written iCloud files. Reconnecting exposes
existing files in the same app/account. Account changes require reconnection.

On iCloud, `createFile` and `updateFile` resolve after a coordinated local commit.
They do not establish that the bytes have reached iCloud. Call `waitForUpload`
after a write when an application must confirm a remote backup; it waits up to
60 seconds by default (1–300 seconds allowed) and rejects with `timeout` or a
provider error if upload cannot be confirmed. It observes iCloud metadata rather
than polling while a coordinated file access is open.

### iCloud configuration

Enable **iCloud Documents** for the consuming iOS application and add an iCloud
container to its entitlements and provisioning profile. Plugin registration does
not add these host-app capabilities. The optional Tauri plugin configuration
selects a container; omit it to use the first entitled container:

```json
{
  "plugins": {
    "cloud-storage": {
      "containerIdentifier": "iCloud.com.example.app"
    }
  }
}
```

`connect()` does not show an Apple account prompt. It succeeds only when the
device has an iCloud identity and the selected container is entitled. An account
change clears the local connection, so the app must call `connect()` again.

### Permissions

The plugin grants no frontend commands by default. Add only the operations an
application needs to a capability, for example:

```json
{
  "permissions": [
    "cloud-storage:allow-get-status",
    "cloud-storage:allow-connect",
    "cloud-storage:allow-list-files",
    "cloud-storage:allow-create-file",
    "cloud-storage:allow-read-file",
    "cloud-storage:allow-update-file",
    "cloud-storage:allow-delete-file",
    "cloud-storage:allow-wait-for-upload"
  ]
}
```

### Android system backup

[Android Auto Backup](https://developer.android.com/identity/data/autobackup) is
a complementary, low-friction recovery mechanism for an Android host app. It
backs up selected private app files through the device's configured backup
service without this plugin managing OAuth or cloud credentials.

It is intentionally **not** a `CloudStorage` provider: the system controls the
backup schedule and restore lifecycle, retains only its current backup dataset,
and does not expose operations to create, list, read, delete, or confirm upload
of individual files. A host app must configure its own manifest and data
extraction rules, decide which of its private files are eligible, and handle its
own data format and encryption. This plugin neither enables Auto Backup nor
generates host-app backup rules.

Use the Google Drive provider when an app needs the file-oriented API documented
above, such as an explicit backup action, a list of existing files, or remote
upload confirmation. Android Auto Backup and Google Drive app data are separate
stores and can be used independently.

### Application integration

A host app can persist its own backup preference and call `connect()` when
enabled. It can list files for recovery and pass encrypted bytes to the generic
file operations. Scheduling, retention, password prompts, and encryption stay in
the application. Disabling automatic backups need not disconnect cloud access if
the app still needs to offer restore.

iCloud and Google Drive are separate stores. This plugin will not automatically
transfer files between iOS and Android accounts. It targets the app's cloud data,
not arbitrary files elsewhere in a user's Drive or iCloud account.

### Development steps

See the [implementation handoff plan](docs/IMPLEMENTATION_PLAN.md) for the next
steps, acceptance criteria, and suggested commit boundaries.

1. Define the generic contract, validation, and mobile entry points (complete).
2. Implement iCloud file operations, command wiring, and JavaScript/Rust APIs (complete; device validation pending).
3. Implement Google Drive authorization and app-data file operations.
4. Validate on both mobile platforms and prepare the release/publish process.

Run `cargo test`, `pnpm check`, and `pnpm build` to verify the contract and
bindings. The native Swift core is typechecked separately. These checks do not
exercise a real iCloud account; device validation remains required.

## Release strategy

The first planned release is `2.0.0-alpha.1`, aligned with Tauri 2. The current
`0.1.0` package versions are development placeholders and must be updated together
before publishing. Breaking changes during alpha must be documented; stable
releases will follow semantic versioning even when a breaking change requires a
major version beyond Tauri's own major version.

#### Conflicting release approaches

The intended workflow follows `tauri-plugin-keystore`: semantic-release determines
the next version and creates GitHub release metadata, while Cargo and npm publish
separately using the versions checked into `Cargo.toml` and `package.json`.
Both manifest versions must match the release tag.

#### Solution

The checked-in workflows mirror `tauri-plugin-keystore`: builds run on pushes and
pull requests; release and publishing remain manually dispatched. The planned
process is:

1. Run **release --dry-run** to determine the next version.
2. Update both manifests and review/commit the changes, for example:

   ```text
   build: release version v2.0.0-alpha.1
   ```

3. Run build checks and **publish --dry-run** against that commit.
4. Manually run **release** to create the GitHub release and tag.
5. Manually run **publish** against the same tested release commit. Publish npm
   prereleases with the `alpha` dist-tag rather than `latest`.

Creating a release does not automatically publish the packages. Workflow files
do not establish registry access, package ownership, or successful mobile builds;
those prerequisites must be verified before any manual release or publish run.
