# Реалізація: каркас проєкту Tunewave (0.2)

## Файли
Створено: `project.yml`, `App/TunewaveApp.swift`, для кожного з 6 пакетів (Auth, AppSettings, InnerTube, PlayerEngine, Plugins, SystemKit) `Package.swift`, `Sources/<N>/<N>Module.swift`, `Tests/<N>Tests/<N>ModuleTests.swift`.
Змінено: `docs/02-architecture.md` (§1 Build, §2, §12 + примітка про відносні шляхи). `docs/06-backlog.md` не чіпали.

## Перевірка (реальні результати)
- `xcodegen generate`: ок, повторний запуск ідемпотентний; схема `Tunewave` створена автоматично.
- `xcodebuild -scheme Tunewave -destination 'platform=macOS' -quiet build` (Debug і Release): exit 0, без warning/error.
- `swift test` у кожному з 6 пакетів: exit 0, 1 тест passed.
- Info.plist: `dev.kruhlyk.tunewave`, `LSMinimumSystemVersion=14.0`, 0.1.0 (1).
- codesign: `Signature=adhoc`, `TeamIdentifier=not set`; entitlements лише `get-task-allow`; немає `app-sandbox`/`cs.*`.
- `git status`: `Tunewave.xcodeproj` не відстежується (`git check-ignore` підтверджує).

## Відхилення / зауваження
- Hardened Runtime: у Release `flags=0x10002(adhoc,runtime)`, у Debug `flags=0x2(adhoc)` (Xcode не додає runtime до Debug ad-hoc). Критерій `(runtime)` перевіряти на Release.
- `get-task-allow` у Release більше відсутній (M1 застосовано: `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO` для Release); у Debug лишається для lldb.
- Ручний запуск (порожнє вікно, ⌘Q) не виконувався.
