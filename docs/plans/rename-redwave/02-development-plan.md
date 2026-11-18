# Development plan: rename Tunewave to Redwave (backlog 0.3, issue #6)

## Assumptions awaiting approval

The BA open questions have not been answered yet. This plan uses the BA's proposed defaults. The approval gate can confirm or overturn each one.

1. **OQ-1, grep scope.** The check is `git grep -i tunewave -- ':!docs/plans'`. The allowed hits are:
   - the cleanup unit `Packages/Auth/Sources/Auth/LegacyStores.swift` (one `legacyID` literal);
   - its test `Packages/Auth/Tests/AuthTests/LegacyStoresTests.swift`, which names the type, not the literal;
   - `docs/00-prd.md` §1 "Previous working name" row;
   - `docs/00-prd.md` §11 change-log row;
   - `docs/06-backlog.md` row 0.2 (completed history);
   - **`docs/06-backlog.md` row 0.3, added here (missing from the BA list).** The row's text contains `TunewaveApp`, `dev.kruhlyk.tunewave.session` and "Rename app from Tunewave…". Ticking it `[x]` leaves those hits in place. It is completed history like row 0.2, so it is not rewritten.
2. **OQ-2, old preferences domain.** Remove it through `UserDefaults.standard.removePersistentDomain(forName: "dev.kruhlyk.tunewave")`, not by deleting the plist file, because cfprefsd caches the domain. This one line is deliberately not unit-tested: the call acts on the named domain globally, so a test would wipe the real domain on the dev Mac.
3. **OQ-3, retries.** Cleanup runs on every launch until nothing is left. There is no "done" flag. It never blocks launch: it runs off the main actor, and failures are swallowed. If the old Keychain item's ACL prompts and the user denies the prompt, it will prompt again on the next launch (accepted under risk 11).

## Project shape

| Key | Value |
|---|---|
| Project system | XcodeGen (`project.yml`). `Tunewave.xcodeproj` is generated and gitignored by `*.xcodeproj/` |
| Targets | one macOS app target, `sources: [App]`, macOS 14.0 deployment target, no extensions |
| Swift | `SWIFT_VERSION 6.0`; packages use tools 6.0 with no upcoming-feature flags; local toolchain is Xcode 27.2 / Swift 6.4.2 |
| Concurrency settings | none set (Swift 6 strict defaults, no default MainActor isolation) |
| UI | SwiftUI app lifecycle (`WindowGroup`) |
| State | Observation (`@Observable AuthSession`, `@State` in the App struct) |
| Persistence | Keychain via `KeychainItem` (Auth); `UserDefaults` for `authUserIndex`; WebKit default data store |
| Navigation | single window; switch on `session.state` |
| Modules | 6 local SwiftPM packages under `Packages/` |
| Localization | none: no String Catalog, literal `Text("…")` |
| Logging | no `Logger` in the app or Auth, so none is added |
| Tests | Swift Testing in package test targets; no app test target |
| Sandbox / signing | not sandboxed; ad-hoc signing `CODE_SIGN_IDENTITY "-"` |

## Files to modify

| File | Change | Why |
|---|---|---|
| `project.yml` | line 1 `name: Redwave`; line 13 target key `Redwave:`; line 26 `PRODUCT_BUNDLE_IDENTIFIER: dev.kruhlyk.redwave`; line 27 `PRODUCT_NAME: Redwave` | FR-1. Nothing else changes: no signing, Swift version or deployment target changes |
| `App/TunewaveApp.swift` → `App/RedwaveApp.swift` (`git mv`) | `struct RedwaveApp: App`; add an `init()` that starts the cleanup (see below) | FR-2, FR-4. `sources: [App]` picks up the renamed file at `xcodegen generate`, so no project entries are needed |
| `App/GuestView.swift:43` | `Text("Redwave")` | FR-2, the only UI literal. The menu "About/Quit Redwave" and the window title come from `PRODUCT_NAME` through the generated Info.plist |
| `Packages/Auth/Sources/Auth/KeychainItem.swift:22` | `service: "dev.kruhlyk.redwave.session"` | FR-3 |
| `docs/00-prd.md` lines 47–51 | Reword in the past tense, e.g. "Backlog 0.3 moved the code to these identifiers. The renamed build removes the session stores of the previous identifier on launch ([05 §2.4]…)". **Do not write the literal `tunewave`.** | FR-7 gap; keeps AC-13 green |
| `docs/02-architecture.md` lines 18 and 332 | Drop "; `Tunewave.xcodeproj` until backlog 0.3" and "(Tunewave.xcodeproj until backlog 0.3)" | FR-7 |
| `docs/05-risks-and-scope.md` lines 34–36 | `dev.kruhlyk.tunewave.session` → `dev.kruhlyk.redwave.session`; `dev.kruhlyk.tunewave` → `dev.kruhlyk.redwave`; replace the "after the rename…" bullet with "Since backlog 0.3 every launch removes the Keychain item and WebKit, cookie, cache and preferences files of the previous working-name identifier until none are left." **No literal `tunewave`.** | FR-7 |
| `docs/06-backlog.md` row 0.3 | `[ ]` → `[x]` only; the text stays | FR-7 |

`.gitignore` is not changed: line 8 `*.xcodeproj/` already covers `Redwave.xcodeproj` (FR-6, AC-11 is a verification step).

## Files to create

| File | Type | Purpose |
|---|---|---|
| `Packages/Auth/Sources/Auth/LegacyStores.swift` | service | Idempotent removal of every store under the old identifier |
| `Packages/Auth/Tests/AuthTests/LegacyStoresTests.swift` | test | AC-6, AC-7, AC-8 |

### `LegacyStores` shape

```swift
import Foundation

public enum LegacyStores {
    static let legacyID = "dev.kruhlyk.tunewave"

    // Runs on every launch until nothing is left: a denied Keychain prompt or a still-running old build must not leave Google cookies behind.
    public static func remove() {
        remove(
            library: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0],
            keychain: KeychainItem(service: legacyID + ".session", account: "default")
        )
        UserDefaults.standard.removePersistentDomain(forName: legacyID)
    }

    static func remove(library: URL, keychain: any KeychainStore) {
        try? keychain.delete()
        for path in ["HTTPStorages/\(legacyID)", "HTTPStorages/\(legacyID).binarycookies", "WebKit/\(legacyID)", "Caches/\(legacyID)"] {
            try? FileManager.default.removeItem(at: library.appendingPathComponent(path))
        }
    }
}
```

Notes on the shape (the implementation may adjust names, but not the behavior):
- `try?` per item. A missing item is already success for `KeychainItem.delete()` (`errSecItemNotFound`). For files, any error, including "no such file", is ignored and retried next launch. Each path is tried independently, so one failure never stops the others.
- **Exact-match guard:** the four paths are fixed literals built with `appendingPathComponent`. There is no directory enumeration, no glob and no `dev.kruhlyk.` prefix, so `dev.kruhlyk.redwave*` and other apps' data can't be reached.
- `removeItem(at:)` on a symlink removes the link itself and does not follow it (edge case "path is a symlink").
- The library root is the real `~/Library` because the app is not sandboxed (ARCH §1).
- Nothing is logged: the project has no logger, and the BA forbids logging cookie contents anyway.
- `KeychainItem` and `KeychainStore` are reused; there is no new Keychain code.

### Call site in `RedwaveApp`

```swift
init() {
    // SecItemDelete can block on a Keychain prompt for the old binary's item, so this must stay off the main actor.
    Task.detached(priority: .utility) { LegacyStores.remove() }
}
```

Why `init()` with a detached task rather than `.task`:
- It runs exactly once per launch. A `.task` on the window content would run again for every new window.
- It never runs on the main actor, so a SecurityAgent prompt or a large `Caches` removal can't freeze the UI.
- It is independent of `AuthSession.restore()`, which reads only the new `dev.kruhlyk.redwave.session` item.

### Tests: `LegacyStoresTests.swift`

- The suite is a plain `@Suite struct`, not `@MainActor`.
- Each test makes a UUID-named temp directory under `FileManager.default.temporaryDirectory` as the Library root, and removes it in `deinit` or with `defer`.
- A private `KeychainSpy` in this file implements `KeychainStore`. It counts deletes and can throw `KeychainError(status: errSecAuthFailed)`. This is duplicated rather than shared, because the spy in `AuthSessionTests.swift` is `private` and sharing it would mean editing an unrelated file.
- The test reads `LegacyStores.legacyID`, which is internal, through `@testable`. The literal therefore appears once in the repository's Swift code.

| Test | Covers |
|---|---|
| `removesEveryLegacyStore`: create the 3 dirs (each with a file inside) plus the `.binarycookies` file → `remove` → none exist, spy `deleteCount == 1` | AC-6 |
| `keepsRedwaveStores`: also create `HTTPStorages/dev.kruhlyk.redwave/`, `HTTPStorages/dev.kruhlyk.redwave.binarycookies`, `WebKit/dev.kruhlyk.redwave/`, `Caches/dev.kruhlyk.redwave/` → all survive | AC-7 |
| `emptyLibraryIsNoOp`: empty root → returns, root still exists and is empty | AC-8 first half |
| `keychainFailureStillRemovesFiles`: the spy throws → all legacy paths are still removed and nothing throws | AC-8 second half, Story 3 |

## Implementation order

1. `KeychainItem.session` service string (FR-3).
2. `LegacyStores.swift` + `LegacyStoresTests.swift`, then `swift test` in `Packages/Auth` (test first per TDD, then code).
3. `git mv App/TunewaveApp.swift App/RedwaveApp.swift`, rename the struct, add `init()`.
4. `GuestView.swift:43`.
5. `project.yml` (4 lines), then `xcodegen generate`.
6. Docs (00, 02, 05, 06).
7. Verification (below).

Dependencies: step 3 needs step 2 (`LegacyStores` must exist). Step 5's build needs steps 1–4.

## Verification

- `xcodegen generate`, which produces `Redwave.xcodeproj`.
- `xcodebuild -project Redwave.xcodeproj -scheme Redwave -destination 'platform=macOS,arch=arm64' -quiet build`: no errors and no new warnings (AC-1).
- `/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' -c 'Print CFBundleName'` on the built `Redwave.app/Contents/Info.plist` → `dev.kruhlyk.redwave`, `Redwave` (AC-2).
- `swift test` in each of the 6 packages (AC-14). Auth gains 4 tests.
- `git check-ignore Redwave.xcodeproj` (AC-11).
- `git grep -i tunewave -- ':!docs/plans'` shows only the allowed hits in assumption 1 (AC-13).
- Manual checks for the user ⛔: AC-9 (old Keychain item and paths gone after the first launch; quit any running Tunewave first), AC-10 (sign in, quit, relaunch, still signed in), AC-4 (the guest title and the About/Quit menu).

## Design decisions

1. **The cleanup lives in Auth**, which already owns Keychain and WebKit-session knowledge, and reuses `KeychainItem`/`KeychainStore`. The App target only starts it.
2. **No "done" flag.** Unconditional retry on every launch is idempotent and cheap: one `SecItemDelete` that returns not-found plus 4 failed `removeItem` calls. It also covers a denied prompt and a still-running old build (OQ-3).
3. **Fixed literal paths, never enumeration or prefix matching.** This is the security guard against deleting Redwave data or other apps' data (AC-7).
4. **Detached utility task from `App.init`.** A Keychain prompt can block synchronously, so the UI stays responsive, and the cleanup runs once per launch.
5. **The prefs-domain removal sits outside the tested seam**, so tests never touch a real global defaults domain. `removePersistentDomain` rather than a file delete, because of the cfprefsd cache.

## Convention skills to invoke during implementation

- `swift-foundation:swift-conventions` (Sendable / nonisolated, error handling)
- `swift-foundation:swift-testing` (suite shape, temp dirs)
- `swift-foundation:swift-tooling` (XcodeGen regenerate, xcodebuild)
- `apple-plugin:macos-app` (generated Info.plist naming, not sandboxed)
- `apple-plugin:swiftui-conventions` (App struct `init`, the string change)
- `apple-plugin:apple-testing` (protocol doubles for system services)

`swiftui-state` and `swiftui-navigation` are not needed: no state or navigation changes.

## Risks and edge cases

- **Keychain prompt on each launch** if the user denies deleting the old item (ad-hoc ACL, risk 11). It is accepted (OQ-3); the fallback for the PR notes is `security delete-generic-password -s dev.kruhlyk.tunewave.session`.
- **The old build is still running** and recreates its WebKit files. The next launch removes them; the PR notes tell the user to quit Tunewave first.
- **AC-13 regression through doc edits.** The new 00-prd and 05 wording must not contain the literal `tunewave`.
- **`removePersistentDomain` on another app's domain** may leave an empty plist file behind. That is acceptable: the file holds only `authUserIndex`, it is not a credential, and AC-9 checks only HTTPStorages/WebKit/Caches.
- **Fresh machine:** `SecItemDelete` on a missing item returns not-found without a prompt, so cleanup is a no-op.
- **Local leftovers are not part of the PR:** `Tunewave.xcodeproj/`, `build/` (old `Tunewave.app`). Launching the old app again recreates the old stores. Do not delete them in the pipeline; mention them as manual cleanup.
- Sandbox: if it is ever turned on, the paths stop resolving to the real Library. That is accepted by the BA.

## Contract for frontend

No frontend contract

## Deviations from spec

- The allowed-hits list for AC-13 adds backlog row 0.3 (see assumption 1).
- No logging is added, although the BA permits path/OSStatus logs: the project has no logger, and adding one is out of scope.
