# Security Review: rename Tunewave to Redwave (backlog 0.3, issue #6)

## Summary
- Critical: 0 (nothing for the fix pass)
- High: 0 (nothing for the fix pass)
- Medium: 1. It is a recommendation, but **it should go into the fix pass**: the fix moves one line, and the issue was introduced by this change.
- Out of scope: Low 2, Info 7

There is no exploit path. The deletion logic is safe by construction:
- `legacyID` is a compile-time constant, and the four paths are fixed literals.
- The root comes from `FileManager.urls(for: .libraryDirectory, in: .userDomainMask)`.
- There is no enumeration, no prefix matching and no user input.

Every lever an "attacker" has over the paths needs write access to `~/Library` as the same user: a planted symlink, a swapped path component, or a `HOME`/`CFFIXED_USER_HOME` override. That same access already reads the plaintext cookie jar directly, so no privilege boundary is crossed.

The main finding is M1, an ordering issue. `remove(library:keychain:)` calls `keychain.delete()` **before** it removes the files. `SecItemDelete` blocks for as long as a SecurityAgent prompt is open; the code comment in `RedwaveApp.init` says so. While the prompt is open, the plaintext `.binarycookies` jar and the WebKit stores stay on disk. If the user leaves the prompt open and quits, they survive that launch, and the next launch blocks at the same point.

## Checked and clean

| Check | Result |
|---|---|
| Path construction (`LegacyStores.swift:4`, `:9`, `:18`, `:22-24`) | `legacyID` is the constant `"dev.kruhlyk.tunewave"`. Each path is a fixed literal joined with `appendingPathComponent`, so there is no `..`, no glob, no enumeration and no `dev.kruhlyk.` prefix. The root is the user Library from `FileManager`, which is the real `~/Library` because the app is unsandboxed. `[0]` is safe: `.userDomainMask` always returns one URL on macOS. |
| Exact-match guard (AC-7) | All four paths end in exactly `dev.kruhlyk.tunewave` or `dev.kruhlyk.tunewave.binarycookies`. `dev.kruhlyk.redwave*` and other apps' entries can't be reached. The prefs call names the exact domain `dev.kruhlyk.tunewave`. |
| Symlink at a legacy path | `FileManager.removeItem(at:)` uses `removefile`. On a symlink it unlinks the link itself, and its recursive walk is physical: it doesn't follow links inside a directory. A link planted at `Caches/dev.kruhlyk.tunewave` that points at `~/Documents` deletes only the link. |
| Symlinked intermediate component (for example, `~/Library/Caches` pointing at another volume) | The target is still an entry named exactly `dev.kruhlyk.tunewave` in the resolved directory. Only a same-user process can plant such a link. It could delete those files itself, so nothing is escalated. **Do not add `realpath`/`resolvingSymlinksInPath` or a prefix check in the fix pass.** They add code and close no boundary. |
| TOCTOU | There is no `fileExists` before `removeItem`, so there is no check-then-act window in app code. Races inside `removefile` traversal would again need a same-user attacker. |
| Home-directory override (`HOME` / `CFFIXED_USER_HOME` in the launch environment) | This can move the root, but only to delete exact-named `dev.kruhlyk.tunewave` entries with the user's own privileges. Whoever sets the launch environment already runs as the user. Not a finding. |
| Keychain delete of the old item (`LegacyStores.swift:10`, `KeychainItem.swift:24-26`, `:44-47`) | The query is `kSecClassGenericPassword` with service `dev.kruhlyk.tunewave.session` and account `default`, which matches the old `KeychainItem.session` exactly. It has no `kSecMatchLimit`, so `SecItemDelete` removes every item matching that exact pair and nothing else. It reuses the same seam as `signOut`, with no new Keychain code. `errSecItemNotFound` counts as success, so a clean machine gets no prompt. |
| New Keychain service (`KeychainItem.swift:22`) | Only the service string changes, to `dev.kruhlyk.redwave.session`. Class, account, default accessibility, no synchronization and the login keychain all stay as decided in docs/05 §2.4. The only production consumer is `AuthSession.init()` (`AuthSession.swift:28-30`). `LegacyStores` builds its own instance with the old service and never reads it. |
| Preferences domain (`LegacyStores.swift:12`) | `removePersistentDomain(forName: "dev.kruhlyk.tunewave")` names the exact domain and goes through cfprefsd. The domain holds only `authUserIndex` (`AuthSession.swift:13`, `:22`), which is not a credential. |
| Concurrency (`RedwaveApp.swift:9-12`) | `Task.detached(priority: .utility)` runs once per process, from `App.init`. `LegacyStores.remove()` is a synchronous, nonisolated static function that captures nothing. `FileManager.default` and `UserDefaults.standard` are thread-safe. Cleanup is independent of `AuthSession.restore()`, which reads only the new item on the main actor. The two touch different Keychain items and different paths. |
| Retry and idempotence | No "done" flag. Each item is attempted on its own with `try?`, and a Keychain failure doesn't stop file removal (also covered by `keychainFailureStillRemovesFiles`). Everything left behind is retried on the next launch. |
| Path-list completeness, against the dev Mac on 2026-11-19 | A scan of `~/Library` (depth 2, plus every file under a matching directory) found the following, and **all of it is covered**: the HTTPStorages directory (`httpstorages.sqlite` with wal/shm), `HTTPStorages/dev.kruhlyk.tunewave.binarycookies` (the cookie jar), `WebKit/dev.kruhlyk.tunewave/WebsiteData/...`, `Caches/dev.kruhlyk.tunewave/` (`Cache.db`, WebKit NetworkCache, HSTS, AlternativeServices) and `Preferences/dev.kruhlyk.tunewave.plist`. Nothing was found in `Application Support`, `Saved Application State`, `Containers` or `/var/folders/*/*/0`. Not verifiable from here: `~/Library/Cookies` (EPERM); see Info 2. |
| `project.yml` | Only the name, target key, `PRODUCT_BUNDLE_IDENTIFIER` and `PRODUCT_NAME` change. Hardened runtime stays on, as do ad-hoc signing and `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO` in Release (no `get-task-allow`). No entitlements file, no ATS keys and no Info.plist secrets. |
| Logging | `LegacyStores` and `RedwaveApp` log nothing, so cookie contents and paths can't leak. |
| Dependencies | No `Package.resolved` and no new packages. |
| `App/GuestView.swift:43`, docs | A literal string change. The doc edits contain no secrets or credentials. |

## Critical findings (for the fix pass)

None.

## High findings (for the fix pass)

None.

## Medium recommendations (recommended for the fix pass)

### 1. The plaintext cookie jar is removed only after a Keychain delete that can block on a prompt — `Packages/Auth/Sources/Auth/LegacyStores.swift:16-19`

**Issue (introduced by this change).** `remove(library:keychain:)` calls `try? keychain.delete()` on line 16 before the file loop on lines 17-19. The two stores need different protection:
- The old Keychain item is in the login keychain, encrypted and ACL-bound to the old ad-hoc binary.
- `HTTPStorages/dev.kruhlyk.tunewave.binarycookies` and the WebKit stores hold the same `google.com` cookies in **plaintext**, readable by any process running as the user.

The removal that matters most is queued behind the call most likely to stall. `RedwaveApp.swift:10` states that `SecItemDelete` can block on a Keychain prompt for the old item; the plan and risk 11 note that ad-hoc ACLs make such a prompt likely.

**Failure scenario.**
1. Redwave launches. The detached task enters `SecItemDelete` and SecurityAgent shows "Redwave wants to use … `dev.kruhlyk.tunewave.session`".
2. The user doesn't answer and quits Redwave, or moves on and leaves the dialog open. The plaintext jar is still on disk for the entire session.
3. On the next launch the same thing happens. Each launch reaches the file removal only after the user answers the prompt.

This also inverts the rule `AuthSession.signOut` already follows (`AuthSession.swift:97`, "WebKit first"): remove the plaintext web stores first, then the Keychain item.

**Prescribed fix (symbol level).** In `LegacyStores.remove(library:keychain:)`, move the Keychain delete after the loop:

```swift
static func remove(library: URL, keychain: any KeychainStore) {
    for path in paths {
        try? FileManager.default.removeItem(at: library.appendingPathComponent(path))
    }
    // After the files: they hold the cookies in plaintext, and this call can block on a Keychain prompt.
    try? keychain.delete()
}
```

No other change is needed:
- `removesEveryLegacyStore` (`deleteCount == 1`) and `keychainFailureStillRemovesFiles` still pass unchanged.
- An optional order test for QA: have the spy's `delete()` record `LegacyStores.paths.allSatisfy { !library.exists($0) }`, then `#expect` that it is `true`.

**Why Medium, not High.** There is no attacker-triggered path, and the residue is the same state as before this change. It requires the prompt to appear and the user to leave it unanswered. Each further launch retries, and an answered prompt either way (Allow or Deny) unblocks file removal. But the fix is one moved line, and it removes the only way the plaintext jar can outlive a launch.

## Out of scope

### Low

1. **Cleanup failures are invisible** (`LegacyStores.swift:16`, `:18`). On the silent-failure checklist: `try?` throws away the `KeychainError` status and the `removeItem` error.
   - This is deliberate, because the retry runs every launch.
   - The consequence: if removal keeps failing on some Mac (a busy file, a permissions change, a persistent `errSecAuthFailed`), the only signal is the manual AC-9 check.
   - The residue is bounded: if the Keychain delete fails the files still go, and the Keychain item is ACL-protected. That is why this is Low.
   - **Fix (later, once the project adds a logger):** in each catch, log the fixed path or the `OSStatus`, using `privacy: .public` for those two values only. Never log file contents. The BA already allows this.

2. **Deleting local copies does not end the Google session.** The removed cookies (`SID`, `SAPISID`, …) stay valid server-side until they expire or are revoked. Copies already in Time Machine backups or local APFS snapshots of `~/Library/HTTPStorages` and `~/Library/WebKit` are not touched by this cleanup.
   - **Fix (docs and PR notes only):** add one line to the PR notes and to `docs/05-risks-and-scope.md` §2.4: "To invalidate the old session server-side, sign out of the old device session in Google Account → Security → Your devices."

### Info

1. **There are three launchable copies of the old app, not one.** Launching any of them recreates every legacy store under the old ID, including a fresh cookie jar after sign-in:
   - `build/Build/Products/Debug/Tunewave.app`
   - `~/Library/Developer/Xcode/DerivedData/Tunewave-chdxknkdekoetifuabtitdcbvpgs/Build/Products/Debug/Tunewave.app`
   - `~/Library/Developer/Xcode/DerivedData/Tunewave-chdxknkdekoetifuabtitdcbvpgs/Build/Products/Release/Tunewave.app`

   The plan's manual-cleanup list names only `build/` and `Tunewave.xcodeproj/`. **Fix:** list all three, plus the DerivedData folder, in the PR notes.

2. **`~/Library/Cookies` could not be checked** (EPERM, TCC-protected).
   - On this Mac the old jar is the observed `HTTPStorages/dev.kruhlyk.tunewave.binarycookies`.
   - A non-FDA app would most likely be refused writes to `~/Library/Cookies` anyway.
   - Don't add a fifth path on speculation. **Fix:** extend the manual AC-9 step with `ls ~/Library/Cookies | grep -i tunewave`, run from a Terminal that has Full Disk Access.

3. **Non-credential leftover in the per-user cache directory:** `/private/var/folders/sw/…/C/com.apple.WebKit.GPU+dev.kruhlyk.tunewave/`. It holds only Metal shader caches (`functions.data`, `libraries.data`): no cookies and no web content. The name follows a WebKit-internal convention. No action; optionally mention it in the PR's manual-cleanup notes.

4. **A Keychain prompt every launch until answered** (risk 11, OQ-3, accepted). Repeated prompts for an item the user doesn't recognize train them to click through Keychain dialogs. The PR notes already give the fallback `security delete-generic-password -s dev.kruhlyk.tunewave.session`.

5. **Squatting on the fresh `dev.kruhlyk.redwave.session` name.**
   - A same-user process can pre-create the generic-password item with a permissive ACL. `KeychainItem.write` (`KeychainItem.swift:37-40`) would then `SecItemUpdate` into it.
   - This class of issue predates this change: the old name had the same exposure.
   - The attacker gains nothing over reading the plaintext WebKit jar. No action.

6. **Sandbox would silently disable the cleanup.** If App Sandbox is ever turned on, the Library root becomes the container, and all four removals become no-ops. The BA accepts this. Note it at the point where the sandbox is enabled, not now.

7. **Carried over from 1.4 (guest-mode Info 2), still open.** The `visitorData` reset is tied to window content. It moved from `App/TunewaveApp.swift:26` to `App/RedwaveApp.swift:31` with unchanged behavior. No other 1.4 Low or Info item is closed or affected by this change.

## Severity summary

| Severity | Count | Next step |
|---|---|---|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 1 | M1: in `LegacyStores.remove(library:keychain:)` (`LegacyStores.swift:16-19`), move `try? keychain.delete()` after the file loop. **Recommended for the fix pass** (one line, no test changes required) |
| Low | 2 | L1: log cleanup failures once a logger exists. L2: add the "revoke the old session in Google Account" note to the PR and `docs/05` §2.4 |
| Info | 7 | Out of scope. Info 1 and 2 belong in the PR notes / AC-9 manual step. The rest need no action now |
