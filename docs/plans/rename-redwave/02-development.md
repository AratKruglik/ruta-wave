# Development report: rename Tunewave to Redwave (issue #6)

Implemented as in the approved plan; no deviations.

## Files
- Created: `Packages/Auth/Sources/Auth/LegacyStores.swift` (service), `Packages/Auth/Tests/AuthTests/LegacyStoresTests.swift` (4 tests).
- Renamed: `App/TunewaveApp.swift` -> `App/RedwaveApp.swift` (struct renamed, `init()` starts `LegacyStores.remove()` in a detached utility task).
- Modified: `project.yml`, `App/GuestView.swift`, `Packages/Auth/Sources/Auth/KeychainItem.swift`, `docs/00-prd.md`, `docs/02-architecture.md`, `docs/05-risks-and-scope.md`, `docs/06-backlog.md` (row 0.3 ticked).

## Decisions
- Cleanup lives in Auth, reuses `KeychainItem`/`KeychainStore`; fixed literal paths, no enumeration. The four paths are exposed as an internal `LegacyStores.paths` so tests iterate the same list.
- Prefs domain removed via `removePersistentDomain`, untested by design.
- No "done" flag, retry every launch.

## Verification (actually run)
- `xcodegen generate`: ok. `xcodebuild` scheme Redwave macOS arm64: BUILD SUCCEEDED, only an AppIntents metadata note.
- Built Info.plist: CFBundleIdentifier `dev.kruhlyk.redwave`, CFBundleName `Redwave`.
- `swift test`: Auth 27 tests pass (4 new); InnerTube 64; AppSettings, PlayerEngine, Plugins, SystemKit 1 each; all pass.
- `git check-ignore Redwave.xcodeproj`: ignored.
- Grep hits left: prd row 25 and 341, backlog rows 21 and 22. `git grep` does not list untracked `LegacyStores.swift`, which holds the one `legacyID` literal once staged.
- Not run (per orchestrator): the app itself, real `LegacyStores.remove()`. Manual AC-9, AC-10, AC-4 remain for the user.
