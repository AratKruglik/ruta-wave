# Post-pipeline checks

Run by the orchestrator after the security fix pass (M1: Keychain delete moved after file removals).

| Check | Result |
|---|---|
| `[ ! -f .swiftlint.yml ] \|\| swiftlint lint` | exit 0 — no `.swiftlint.yml`, nothing to lint |
| `swift test` in each of the 6 packages | passed: Auth 31, InnerTube 64, AppSettings 1, PlayerEngine 1, Plugins 1, SystemKit 1 |
| `xcodegen generate` + `xcodebuild -scheme Redwave -destination 'platform=macOS,arch=arm64' build` | BUILD SUCCEEDED |
| `git grep -il tunewave -- ':!docs/plans'` | `LegacyStores.swift`, `LegacyStoresTests.swift`, `docs/00-prd.md`, `docs/06-backlog.md` — all on the approved allowed-hits list |

Not run: launching the app. Manual checks AC-4, AC-9 and AC-10 remain for the user.

```json post-checks
[{"command": "[ ! -f .swiftlint.yml ] || swiftlint lint", "exit_code": 0}]
```
