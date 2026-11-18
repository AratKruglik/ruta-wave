# Brief — backlog item 0.2 (docs/06-backlog.md)

Create Tunewave macOS app skeleton: XcodeGen project.yml (bundle id dev.kruhlyk.tunewave,
macOS 14, Swift 6, empty SwiftUI window) and empty local Swift packages per
docs/02-architecture.md section 12.

Source of truth: docs/03-roadmap.md "Stage 0. Preparation"; docs/02-architecture.md §1, §2, §12.

Decisions already taken by the user (2026-11-18):
- App name: Tunewave; bundle ID: dev.kruhlyk.tunewave (replaces "YTMusic" naming in docs/02).
- Project system: XcodeGen (`project.yml` committed; generated `*.xcodeproj/` is gitignored).
- Distribution: DMG, no sandbox, Hardened Runtime on, ad-hoc signing (docs/03 stage 8).
- No third-party dependencies at the start.

Done when: `xcodegen generate` + `xcodebuild build` succeed and `swift test` passes in every
package under Packages/ (App, InnerTube, PlayerEngine, Auth, SystemKit, Plugins, Settings per §2/§12).
Out of scope: any real feature code (sign-in, networking, player) — stage 1+.
