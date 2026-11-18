# Business Analysis: Rename the app from Tunewave to Redwave (backlog 0.3, issue #6)

## Executive summary

The product name Redwave was decided on 2026-11-18 (00-prd §1). The code, project and Keychain still use the working name Tunewave. This task moves every identifier to Redwave: project and target name, `PRODUCT_NAME`, bundle ID `dev.kruhlyk.redwave`, the app struct, UI strings and the Keychain service. Changing the bundle ID orphans the old session stores, which hold Google cookies. The renamed build must therefore remove the old-identifier Keychain item and WebKit/URL data from disk, and the user signs in again.

## Sources

| Tag | Source |
|---|---|
| [BRIEF] | `docs/plans/rename-redwave/_brief.md` (GitHub issue #6 body) |
| [PRD] | `docs/00-prd.md` §1 Name and positioning, §11 change log |
| [ARCH] | `docs/02-architecture.md` §1 (line 18), §12 (line 332) |
| [RISK] | `docs/05-risks-and-scope.md` §1 risk 11, §2.4 Credentials |
| [BACKLOG] | `docs/06-backlog.md` Stage 0, row 0.3 |
| [CODE] | Findings from scanning the codebase and local disk (this analysis) |

## Functional requirements

1. **FR-1 Project identity** [BRIEF, PRD §1, BACKLOG 0.3]. `project.yml` changes as follows: `name`, the target key and `PRODUCT_NAME` become `Redwave`; `PRODUCT_BUNDLE_IDENTIFIER` becomes `dev.kruhlyk.redwave`. `xcodegen` then generates `Redwave.xcodeproj`. The app builds as `Redwave.app`.
2. **FR-2 App entry point and UI strings** [BRIEF, PRD §1]. `TunewaveApp` becomes `RedwaveApp`, and the file `App/TunewaveApp.swift` is renamed to `App/RedwaveApp.swift`. Every user-visible "Tunewave" becomes "Redwave". The only literal is `App/GuestView.swift:43`. The menu-bar app name, "About …", "Quit …" and the window title come from `PRODUCT_NAME` through the generated Info.plist (`GENERATE_INFOPLIST_FILE: YES`), so they follow FR-1 with no code change.
3. **FR-3 Keychain service** [BRIEF, PRD §1, RISK §2.4]. `KeychainItem.session` uses service `dev.kruhlyk.redwave.session`. The account stays `default`, and the class, accessibility and sync settings are unchanged.
4. **FR-4 Remove the old-identifier stores** [BRIEF, PRD §1, RISK §2.4, CODE]. On launch, the renamed app deletes everything stored under the old identifier:
   - the Keychain generic-password item with service `dev.kruhlyk.tunewave.session` and account `default`;
   - `~/Library/HTTPStorages/dev.kruhlyk.tunewave/` (directory);
   - `~/Library/HTTPStorages/dev.kruhlyk.tunewave.binarycookies` (a sibling **file**, not inside the directory; this is the cookie jar) [CODE: present on the dev Mac];
   - `~/Library/WebKit/dev.kruhlyk.tunewave/` (directory);
   - `~/Library/Caches/dev.kruhlyk.tunewave/` (directory; it includes `Cache.db` from `URLCache.shared` as well as the WebKit network cache);
   - *(pending OQ-2)* `~/Library/Preferences/dev.kruhlyk.tunewave.plist`, which holds only `authUserIndex` and is not a credential.

   Cleanup is **idempotent and repeats on every launch until nothing is found**. It is not a "first launch" flag set up front, because a denied Keychain prompt or a still-running old build must not leave stores behind permanently.
5. **FR-5 Fresh sign-in under the new identity** [BRIEF Done-when]. After the rename the app starts signed out (guest mode, from 1.4). The user signs in again. The session is written to the new Keychain item and survives a relaunch.
6. **FR-6 .gitignore** [BRIEF]. `Redwave.xcodeproj` must be ignored. **This is already satisfied**: `.gitignore` line 8 is `*.xcodeproj/`. The work is to verify it, not to change it. An explicit line is optional.
7. **FR-7 Docs** [BRIEF, CODE]:
   - 02 §1 (line 18) and §12 (line 332): drop "(`Tunewave.xcodeproj` until backlog 0.3)".
   - 05 §2.4 (lines 34–36): replace the identifiers with `dev.kruhlyk.redwave.session` / `dev.kruhlyk.redwave`, and replace the "after the rename…" bullet with a statement that the renamed build removes the old stores.
   - 06 row 0.3: tick `[x]`.
   - **Gap, not in the brief:** the 00-prd §1 paragraph at lines 47–51 ("The code still uses the old identifiers… 0.3 must remove it") goes stale and must be reworded in the past tense.

## Non-functional requirements

- **Security:**
  - The old stores hold `google.com` / `accounts.google.com` cookies with full Google-account access (RISK §2.4), so removing them is the security goal of the task.
  - Matching must be **exact on `dev.kruhlyk.tunewave`**. Never use a `dev.kruhlyk.*` prefix or glob, because that could delete the new `dev.kruhlyk.redwave` stores or unrelated apps' data.
  - Cookie values and file contents are never logged. Logging paths and OSStatus codes is acceptable.
- **Reliability:**
  - Cleanup failure is never fatal. It must not block or delay the guest flow, sign-in or `AuthSession.restore()`.
  - A missing item or missing path counts as success.
  - Cleanup must not touch the current (Redwave) Keychain item or the `WKWebsiteDataStore.default()` of the running app.
- **Performance:** cleanup runs at launch with no visible delay. Directory removal may run off the main actor. After the first success it amounts to a few existence checks plus one Keychain delete that returns not-found.
- **Platform constraint:** the app is **not sandboxed** (ARCH §1 "Sandbox: off"), so `~/Library/...` resolves to the real user Library. If the sandbox is ever turned on, these paths stop being reachable. That is acceptable here.
- **Compliance:** none beyond RISK §2.4. Trademark rules (RISK §2.2) are respected because "Redwave" contains no Google mark.

## User stories (Gherkin)

### Story 1: The app carries its decided name
**As a** user
**I want** the app, its menus and its first screen to say "Redwave"
**So that** the product matches its decided name and identity

**Acceptance criteria:**
- Given `project.yml` after the change, When I run `xcodegen`, Then `Redwave.xcodeproj` is generated with target and scheme `Redwave`, and `xcodebuild build` succeeds.
- Given the built app, When I inspect its Info.plist, Then `CFBundleIdentifier` is `dev.kruhlyk.redwave` and `CFBundleName` is `Redwave`.
- Given the app is running in guest mode, When the guest screen shows, Then the title reads "Redwave", and the app menu shows "About Redwave" and "Quit Redwave".

### Story 2: Old credentials are removed from disk
**As a** user who ran the Tunewave build
**I want** the Redwave build to delete the old Keychain item and the old WebKit, cookie and cache data
**So that** no orphaned Google-account cookies remain readable on my Mac

**Acceptance criteria:**
- Given the Keychain item `dev.kruhlyk.tunewave.session` and the paths listed in FR-4 exist, When Redwave launches, Then after launch none of them exist.
- Given none of the old stores exist, When Redwave launches, Then cleanup does nothing and raises no error or prompt.
- Given a Redwave session exists in `dev.kruhlyk.redwave.session` and in the Redwave WebKit store, When cleanup runs, Then the Redwave session is untouched and the app restores it as signed in.

### Story 3: Cleanup that fails partway is retried and does not block the app
**As a** user
**I want** the app to start normally even if the old Keychain item cannot be deleted
**So that** a denied Keychain prompt or a locked file does not break the app

**Acceptance criteria:**
- Given deleting the old Keychain item fails (for example, the user denies the prompt, or `errSecAuthFailed` / `errSecInteractionNotAllowed` is returned), When the app launches, Then it reaches the guest or signed-in screen as usual, and the remaining old stores are still deleted.
- Given a previous launch left an old store behind, When the app launches again, Then cleanup tries again and removes it.

### Story 4: Sign in again under the new identity
**As a** user
**I want** to sign in once in Redwave and stay signed in
**So that** the rename costs me exactly one sign-in

**Acceptance criteria:**
- Given a fresh Redwave install after cleanup, When the app starts, Then it is in guest mode (signed out).
- Given I sign in through the sign-in window, When I quit and relaunch Redwave, Then I am still signed in, and the Keychain item `dev.kruhlyk.redwave.session` exists. ⛔ This is a manual check by the user, because it needs a real Google sign-in.

### Story 5: The repository no longer uses the old name
**As a** maintainer
**I want** the only remaining references to "tunewave" to be the cleanup code and named history
**So that** nobody reintroduces the old identifier by accident

**Acceptance criteria:**
- Given the merged branch, When I run `git grep -i tunewave -- ':!docs/plans'`, Then the only matches are:
  - the old-store cleanup code and its test;
  - the 00-prd §1 "Previous working name" row;
  - the 00-prd §11 change-log row;
  - the text of the completed backlog row 0.2 in 06.

  The proposed default is pending OQ-1.

## Verifiable acceptance criteria (tied to requirements)

| AC | Requirement | Check |
|---|---|---|
| AC-1 | FR-1 | `xcodegen` produces `Redwave.xcodeproj`; `xcodebuild -project Redwave.xcodeproj -scheme Redwave build` succeeds |
| AC-2 | FR-1 | The built `Redwave.app/Contents/Info.plist` has `CFBundleIdentifier = dev.kruhlyk.redwave` and `CFBundleName = Redwave` |
| AC-3 | FR-2 | `App/RedwaveApp.swift` declares `struct RedwaveApp: App` with `@main`; `App/TunewaveApp.swift` no longer exists |
| AC-4 | FR-2 | The guest screen title reads "Redwave" (code review plus a manual look) |
| AC-5 | FR-3 | `KeychainItem.session.service == "dev.kruhlyk.redwave.session"` |
| AC-6 | FR-4 | Unit test (Swift Testing, injected keychain spy and a temporary Library root): with all legacy items present, cleanup removes the old Keychain entry and every FR-4 path, including the `.binarycookies` file |
| AC-7 | FR-4 | Unit test: with a sibling `dev.kruhlyk.redwave*` file or directory present, it survives cleanup (exact-match guard) |
| AC-8 | FR-4 | Unit test: with nothing present, cleanup succeeds as a no-op; a Keychain delete failure does not stop path removal and does not throw to the caller |
| AC-9 | FR-4 | Manual check ⛔ on the dev Mac after the first Redwave launch: `security find-generic-password -s dev.kruhlyk.tunewave.session` reports not found, and `ls ~/Library/{HTTPStorages,WebKit,Caches}/ \| grep -i tunewave` is empty |
| AC-10 | FR-5 | Manual check ⛔: sign in, quit, relaunch, still signed in |
| AC-11 | FR-6 | `git check-ignore Redwave.xcodeproj` succeeds |
| AC-12 | FR-7 | The 02 §1/§12 parentheticals are gone; 05 §2.4 names the Redwave identifiers; 06 row 0.3 is `[x]`; the 00-prd §1 paragraph is in the past tense |
| AC-13 | Story 5 | `git grep -i tunewave -- ':!docs/plans'` shows only the allowed hits (OQ-1) |
| AC-14 | all | `swift test` passes in each of the 6 packages under `Packages/` |

## Data model sketch

No persistent data model changes. The change is to identifiers and store locations.

| Store | Old (to delete) | New |
|---|---|---|
| Bundle ID / WebKit and URL storage namespace | `dev.kruhlyk.tunewave` | `dev.kruhlyk.redwave` |
| Keychain generic password (service / account) | `dev.kruhlyk.tunewave.session` / `default` | `dev.kruhlyk.redwave.session` / `default` |
| HTTP storage dir | `~/Library/HTTPStorages/dev.kruhlyk.tunewave/` | `…/dev.kruhlyk.redwave/` (created by the system) |
| Cookie jar file | `~/Library/HTTPStorages/dev.kruhlyk.tunewave.binarycookies` | `…/dev.kruhlyk.redwave.binarycookies` |
| WebKit website data | `~/Library/WebKit/dev.kruhlyk.tunewave/` | `…/dev.kruhlyk.redwave/` |
| Caches (WebKit NetworkCache, `Cache.db`, HSTS) | `~/Library/Caches/dev.kruhlyk.tunewave/` | `…/dev.kruhlyk.redwave/` |
| UserDefaults domain (`authUserIndex`) | `~/Library/Preferences/dev.kruhlyk.tunewave.plist` (OQ-2) | `dev.kruhlyk.redwave.plist`; `authUserIndex` starts at 0, which is correct because the user signs in again |

These were observed on the dev Mac on 2026-11-19. All the old paths above exist, except that `Saved Application State` has no Tunewave entry.

## API contract sketch

N/A. There is no network or InnerTube API change and no new endpoint. The only internal surface is a launch-time "remove legacy stores" entry point. Its placement (the Auth package owns Keychain and WebKit knowledge, so it is the natural home) and its shape are left to the developer.

## Context package for development

- **Files impacted:**
  - `project.yml` (lines 1, 13, 26, 27)
  - `App/TunewaveApp.swift` → `App/RedwaveApp.swift` (struct name; the launch hook for cleanup)
  - `App/GuestView.swift:43`
  - `Packages/Auth/Sources/Auth/KeychainItem.swift:22`
  - a new cleanup unit plus a test in `Packages/Auth/Tests/AuthTests/`
  - `docs/00-prd.md` §1, `docs/02-architecture.md` lines 18 and 332, `docs/05-risks-and-scope.md` lines 34–36, `docs/06-backlog.md` row 0.3
- **Patterns to reuse:**
  - `KeychainItem(service:account:)` plus `delete()` already treats `errSecItemNotFound` as success. An instance with the old service string is enough for the Keychain half; no new Keychain code is needed.
  - The `KeychainStore` protocol and the `KeychainSpy` in `AuthSessionTests.swift` are the test-double pattern. The spy is `private` there, so it has to be shared or duplicated.
  - Swift Testing (`@Suite`, `@Test`, `#expect`), `@MainActor` suites.
  - The Swift 6 language mode and typed throws (`throws(KeychainError)`) used in Auth.
- **Constraints:**
  - The ad-hoc signature (`CODE_SIGN_IDENTITY: "-"`) makes Keychain access prompts likely (RISK risk 11).
  - Not sandboxed.
  - `AuthSession.wipeWebData()` uses `WKWebsiteDataStore.default()`, which is always the *current* bundle's store. It cannot reach the old store, so the old data must be removed as files.
  - `InnerTubeClient` uses an `.ephemeral` URLSession and writes nothing to disk.
- **No other "tunewave" in Swift sources or the packages' `Package.swift`.** Package names (Auth, InnerTube, …) are name-neutral.
- **Local, untracked leftovers (not part of the PR, cleaned up by hand):**
  - `Tunewave.xcodeproj/` at the repo root;
  - `build/` (it contains `Build/Products/Debug/Tunewave.app`);
  - `.claude/agent-memory/.../project_review_conventions.md`.

  Launching the old `Tunewave.app` again would recreate the old stores.

## Edge cases and error scenarios

- **Keychain ACL:** the old item's ACL trusts the old ad-hoc binary. Deleting it from Redwave may show a login-keychain prompt, or return `errSecAuthFailed`, `errSecUserCanceled` or `errSecInteractionNotAllowed` (a locked keychain). In every case: continue launching, and retry on the next launch. Retrying means the user may see the prompt on each launch until they allow it. This is accepted under risk 11, but see OQ-3.
- **The old build is still running:** it holds the WebKit sqlite/wal files open and may recreate them after deletion. Retry-every-launch covers this. Docs and the PR should tell the user to quit Tunewave first.
- **The user signed out in the old build first:** `signOut()` → `WKWebsiteDataStore.removeData(...)` clears records but **leaves the directories, salts, sqlite/wal files and caches on disk**. It also does not remove the `.binarycookies` file as a file. The brief's alternative of signing out in the old build therefore does **not** meet "no WebKit data of the old identifier is left on disk". Cleanup code is required either way.
- **Partial removal:** if one path fails (permissions, a busy file), the others are still attempted, and the failed one is retried next launch.
- **A path is a symlink or of an unexpected type:** remove the entry itself without following the link outside `~/Library`. This is low likelihood but follows from the exact-match security rule.
- **A clean machine that never ran Tunewave:** this is a no-op and must cause no prompt. `SecItemDelete` on a missing item returns not-found without prompting.
- **Cleanup racing with the first WebKit use:** the new app's WebKit store lives under `dev.kruhlyk.redwave`, so the two cannot collide. Cleanup and `AuthSession.restore()` are independent.
- **`authUserIndex` lost:** expected. The new defaults domain starts at 0, and the user signs in again.

## Risks and dependencies

- **Dependency:** 1.4 guest mode, which is merged (#5). This task blocks #30.
- **Risk: the Done-when grep is unreachable as written.** A plain `grep -ri tunewave` matches:
  - about 120 lines in `docs/plans/**`, including this brief;
  - the PRD history rows and backlog row 0.2;
  - gitignored build products (`build/`, `Tunewave.xcodeproj/`, `Packages/*/.build`).

  The criterion needs a defined scope (OQ-1).
- **Risk: the brief offers two options for the old session ("sign out in the old build first" or cleanup code).** Only cleanup code meets Done-when #3. Treat cleanup as required.
- **Risk: Keychain prompts.** Repeated prompts are possible with ad-hoc signing (risk 11). If they are unacceptable, the fallback is a manual `security delete-generic-password` step in the PR notes (OQ-3).
- **Risk: deleting the wrong data.** Mitigated by exact-identifier matching (AC-7).
- **Not checked yet (from PRD §1):** whether "Redwave" is free as a trademark, domain or GitHub name. That is tracked in #28 and is out of scope here.

## Open questions for stakeholders

1. **OQ-1, the grep scope for Done-when #2.** Proposed default: `git grep -i tunewave -- ':!docs/plans'`, which covers tracked files and excludes the historical pipeline artifacts. The allowed hits are the cleanup code and its test, the 00-prd "Previous working name" row and the §11 change log, and backlog row 0.2. Is that acceptable, or must history be rewritten too?
2. **OQ-2, the old preferences plist.** Should `~/Library/Preferences/dev.kruhlyk.tunewave.plist` also be removed? It holds only `authUserIndex`, which is not a secret. Proposed default: yes, through the preferences API rather than deleting the file, because cfprefsd caches it.
3. **OQ-3, repeated Keychain prompts.** If deleting the old Keychain item prompts and the user denies it, is a prompt on every launch until it succeeds acceptable? Proposed default: yes, consistent with risk 11. The alternative is to try once and document a manual `security delete-generic-password -s dev.kruhlyk.tunewave.session` step.

## Estimated complexity

**small.** The rename is mechanical, about 6 lines across 4 source and config files plus docs. The only new logic is the idempotent removal of legacy stores (one Keychain delete plus 4–5 exact paths) with a unit test.
