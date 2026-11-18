# План розробки: каркас проєкту Tunewave (backlog 0.2)

## 0. Передумова (блокер для фази реалізації)

`xcodebuild -version` на цій машині повертає: *"You have not agreed to the Xcode license agreements"*.
Поки ліцензію не прийнято, не працюють ні `xcodebuild`, ні `swift test`. Це має зробити сам користувач,
пайплайн цього не робить:

```
sudo xcodebuild -license accept
```

## 1. Виявлена форма проєкту

| Ключ | Значення |
|---|---|
| Стан репозиторію | greenfield: `docs/`, `.gitignore` |
| Система проєкту | XcodeGen 2.47.0 (`project.yml` у git; `*.xcodeproj/` ігнорується в `.gitignore`) |
| Тулчейн | Xcode 27.2, Swift 6.3 |
| Платформа | лише macOS, deployment target 14.0, destination `platform=macOS` |
| Swift | `SWIFT_VERSION = 6.0` (strict concurrency входить у мовний режим). `SWIFT_DEFAULT_ACTOR_ISOLATION` / approachable concurrency не задаємо: їх ніхто не просив |
| UI | SwiftUI, `@main App` + `WindowGroup` |
| Стан / персистентність / навігація / локалізація | ще немає (каркас) |
| Модулі | 6 локальних SwiftPM-пакетів у `Packages/` |
| Залежності | жодних remote-залежностей, тож `Package.resolved` не з'явиться |
| CLAUDE.md, форматер, SwiftLint | відсутні |

## 2. Файли для створення

| Шлях | Тип | Призначення |
|---|---|---|
| `project.yml` | manifest | XcodeGen: проєкт `Tunewave`, `options.deploymentTarget.macOS: "14.0"`, секція `packages:` з шістьма локальними пакетами (`path: Packages/<Name>`), один таргет `Tunewave` (`type: application`, `platform: macOS`, `sources: [App]`, `dependencies: - package: <Name>` ×6) |
| `App/TunewaveApp.swift` | screen | `@main struct TunewaveApp: App`, `WindowGroup { Color.clear.frame(minWidth: 480, minHeight: 320) }`. `EmptyView` не підходить, бо дає вікно нульового розміру. Інших файлів немає |
| `Packages/Auth/Package.swift` | manifest | без залежностей |
| `Packages/AppSettings/Package.swift` | manifest | без залежностей |
| `Packages/InnerTube/Package.swift` | manifest | `.package(path: "../Auth")` |
| `Packages/PlayerEngine/Package.swift` | manifest | `.package(path: "../Auth")` |
| `Packages/Plugins/Package.swift` | manifest | `../PlayerEngine`, `../InnerTube`, `../AppSettings` |
| `Packages/SystemKit/Package.swift` | manifest | `../PlayerEngine`, `../AppSettings` |
| `Packages/<Name>/Sources/<Name>/<Name>Module.swift` ×6 | model | один маркерний символ: `public enum <Name>Module { public static let name = "<Name>" }` |
| `Packages/<Name>/Tests/<Name>Tests/<Name>ModuleTests.swift` ×6 | test | Swift Testing: `@Test func moduleName() { #expect(<Name>Module.name == "<Name>") }` |

Шаблон `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InnerTube",
    platforms: [.macOS(.v14)],
    products: [.library(name: "InnerTube", targets: ["InnerTube"])],
    dependencies: [.package(path: "../Auth")],
    targets: [
        .target(name: "InnerTube", dependencies: [.product(name: "Auth", package: "Auth")]),
        .testTarget(name: "InnerTubeTests", dependencies: ["InnerTube"]),
    ]
)
```

Ключові налаштування таргету в `project.yml` (`settings.base`):

```yaml
PRODUCT_BUNDLE_IDENTIFIER: dev.kruhlyk.tunewave
PRODUCT_NAME: Tunewave
MARKETING_VERSION: "0.1.0"
CURRENT_PROJECT_VERSION: "1"
SWIFT_VERSION: "6.0"
GENERATE_INFOPLIST_FILE: YES
ENABLE_HARDENED_RUNTIME: YES
CODE_SIGN_IDENTITY: "-"
DEVELOPMENT_TEAM: ""
```

Секції `entitlements:` немає зовсім, тому немає і `com.apple.security.app-sandbox`, і `com.apple.security.cs.*`.

**Чого не створюємо (YAGNI):** `Assets.xcassets`/`AppIcon` (BA: іконка поза скоупом), власний `Info.plist`,
`.entitlements`, xcconfig, протоколи й заглушки в пакетах, `scripts/build-dmg.sh`, корінний `README.md`,
пакет `UI`, тести app-таргету.

## 3. Файли для зміни

| Шлях | Зміна |
|---|---|
| `docs/02-architecture.md` §1, рядок «Build» | «Xcode project» → «XcodeGen `project.yml` (генерує `Tunewave.xcodeproj`, не комітиться) + local Swift packages» |
| `docs/02-architecture.md` §2 | `YTMusic.app` → `Tunewave.app`; `Settings` → `AppSettings`; `UI` лишається з приміткою «поки живе в `App/`, винесення вирішується на етапі 4». Абзац про залежності переписати так: `InnerTube → Auth`, `PlayerEngine → Auth`, `Plugins → PlayerEngine, InnerTube, AppSettings`, `SystemKit → PlayerEngine, AppSettings`; `InnerTube` і `PlayerEngine` не знають одне про одного; `Auth` і `AppSettings` листові |
| `docs/02-architecture.md` §12 | `YTMusic.xcodeproj` → `project.yml` + `Tunewave.xcodeproj` (згенерований, у `.gitignore`); `Settings/` → `AppSettings/`; `App/` — «сцени, ресурси» (Info.plist генерується) |
| `docs/06-backlog.md` | позначити 0.2 виконаним (фаза документації) |

Не чіпати: §9 «Settings» і рядок ~224 у docs/02. Там ідеться про фічу налаштувань і SwiftUI-сцену `Settings`, а не про модуль.
`.gitignore` змін не потребує.

## 4. Порядок реалізації

1. Пакети-листи `Auth`, `AppSettings`, потім `swift test` у кожному.
2. `InnerTube`, `PlayerEngine` (залежать від `Auth`), потім `swift test`.
3. `Plugins`, `SystemKit`, потім `swift test`.
4. `App/TunewaveApp.swift` + `project.yml`, потім `xcodegen generate` і `xcodebuild -list`, щоб переконатися, що існує схема `Tunewave`. Якщо XcodeGen не створив її автоматично, додати таргету `scheme: {}`.
5. `xcodebuild … build`, перевірки `codesign` і `Info.plist` (розділ 7).
6. Оновити docs/02.

## 5. Дизайн-рішення

1. **Застосунок лінкує всі шість пакетів (FR7).** `App` є коренем DI, тож `xcodebuild build` одразу компілює весь граф у налаштуваннях застосунку. Невикористаний `import` не потрібен: досить залежності в `project.yml`.
2. **Info.plist генерується (`GENERATE_INFOPLIST_FILE: YES`).** `LSMinimumSystemVersion`, `CFBundleShortVersionString` і `CFBundleVersion` беруться з build settings, і окремий файл не треба підтримувати. Це відхилення від формулювання §12 («App/… Info.plist»), тому §12 оновлюється.
3. **Маркер `<Name>Module`, а не `public enum <Name>`.** Тип з тим самим ім'ям, що й модуль, ламає module-qualified lookup (`Auth.Something`) на наступних етапах.
4. **Ad-hoc підпис через `CODE_SIGN_IDENTITY: "-"` без team.** Hardened Runtime увімкнено, entitlements-файлу немає. Якщо automatic signing без team відмовиться підписувати, запасний варіант: `CODE_SIGN_STYLE: Manual`.
5. **Swift Testing у пакетах і `swift-tools-version: 6.0`.** Мінімальна версія, що дає Swift 6 language mode за замовчуванням і задовольняє FR4 («6.x»). Обидва входять у тулчейн, нових залежностей немає.

## 6. Contract for frontend

No frontend contract

## 7. Перевірка (стане `test_command` проєкту)

```
xcodegen generate \
 && xcodebuild -project Tunewave.xcodeproj -scheme Tunewave -destination 'platform=macOS' -quiet build \
 && for p in Packages/*/; do (cd "$p" && swift test) || exit 1; done
```

Додатково для критеріїв історії 3 (шлях до `.app` взяти з `xcodebuild -showBuildSettings`, `BUILT_PRODUCTS_DIR`):
- `plutil -p Tunewave.app/Contents/Info.plist`: `CFBundleIdentifier`, `LSMinimumSystemVersion = 14.0`, версія;
- `codesign -dv --verbose=2 Tunewave.app`: є `flags=…(runtime)`, `Signature=adhoc`, немає `TeamIdentifier`;
- `codesign -d --entitlements - Tunewave.app`: немає `app-sandbox` і `cs.*`;
- `git status`: `Tunewave.xcodeproj` не з'являється серед невідстежених;
- повторний `xcodegen generate` ідемпотентний;
- ручний запуск: одне порожнє вікно, ⌘Q закриває застосунок.

## 8. Скіли для фази реалізації

`swift-foundation:swift-tooling`, `swift-foundation:swift-conventions`, `swift-foundation:swift-testing`,
`apple-plugin:macos-app`, `apple-plugin:swiftui-conventions`, `apple-plugin:apple-testing`.
`swiftui-state` і `swiftui-navigation` не потрібні, бо в каркасі немає ні стану, ні навігації. `ios-ipados` і `watchos-app` теж не потрібні, бо платформа лише macOS.

## 9. Ризики та граничні випадки

- **Ліцензію Xcode не прийнято** (розділ 0). Без цього збирання неможливе.
- **Схема `Tunewave`.** Чи XcodeGen створить її без блоку `scheme:`, не підтверджено. Перевірка: `xcodebuild -list`.
- **`get-task-allow` у Debug.** Xcode додає `com.apple.security.get-task-allow` до Debug-збірок. Це не ключ `cs.*`, тож критерій історії 3 не порушено. QA не повинен позначати це як дефект.
- **Automatic signing без team** може вимагати `CODE_SIGN_STYLE: Manual` (див. рішення 4).
- **Відносні шляхи `../X`** між пакетами: перейменування каталогу ламає збирання. Це прийнятно й зафіксовано в docs/02 §12.
- **Пакет без тесту або без джерела** не збирається чи не тестується. У кожного пакета рівно по одному файлу в `Sources/` і `Tests/`.
- **Swift 6 strict concurrency** у `TunewaveApp`: тривіальний `App` компілюється без попереджень, але це треба перевірити на реальному збиранні.
