# Реалізація: гостьовий режим (backlog 1.4)

План (`02-development-plan.md`) виконано без відхилень, включно із затвердженими `KeychainStore` і лімітом 512.

## Файли

Створено:
- `Packages/InnerTube/Sources/InnerTube/GuestVisitor.swift` (service)
- `App/GuestModel.swift` (model), `App/GuestView.swift` (screen, 3 `#Preview`)
- `Packages/InnerTube/Tests/InnerTubeTests/GuestRequestTests.swift`
- `Packages/Auth/Tests/AuthTests/AuthSessionTests.swift`

Змінено:
- `InnerTubeRequest.swift`: `makeGuest`, спільні `unauthenticated` і `attachPayload`
- `InnerTubeClient.swift`: `connectAsGuest()`, `resetGuestVisitor()`
- `KeychainItem.swift`: протокол `KeychainStore`
- `AuthSession.swift`: `State.isSignedIn`, `continueAsGuest()`, `cancelSignIn()`, `wipeWebData()`, `init(keychain: any KeychainStore, ...)`
- `App/TunewaveApp.swift`: `GuestView`, «Continue without signing in», `onChange(of: isSignedIn)` скидає `visitorData`
- `docs/02-architecture.md` §5.1, §6; `docs/06-backlog.md` примітка в 3.1 (1.4 не позначено)

Залежності, `project.yml`, `Info.plist`, entitlements не чіпали. `Tunewave.xcodeproj` перегенеровано `xcodegen`.

## Рішення і дрібні нюанси

- Публічний `convenience init()` тепер явно `KeychainItem.session` (потрібно через `any KeychainStore`).
- Помилку сховища `KeychainSpy` у тестах `write`/`delete` оголошено без `throws`, що сумісно з протоколом.
- Перевірка набору символів `visitorData` йде по `unicodeScalars`; довжина — `count` (1...512).
- AC10 структурний: `accept(` викликається лише в `connectAsGuest`.

## Тести

`test_command` повністю: збірка `Tunewave` (macOS arm64) без помилок і попереджень, `swift test` у всіх пакетах пройшов: Auth 16, InnerTube 61, AppSettings/PlayerEngine/Plugins/SystemKit по 1. Нові: `GuestRequestTests` (AC6–AC9, E2), `AuthSessionTests` (AC2, AC19, AC20, гард Cancel). Keychain, WKWebView і мережа в тестах не використовуються (шлях `cancelSignIn` з реальним очищенням WebKit не запускається).

## Для QA / безпеки / ручної перевірки

- Ручна перевірка на живому сервісі (користувач): чистий запуск → «Connected…» → Sign in → акаунт → Sign out → гість → Sign in → Cancel → гість; Esc в аркуші; після входу акаунт-екран вантажиться і повторний запуск лишається `.signedIn` (R-a).
- `GuestModel`/`GuestView` без unit-тестів (немає тестового таргета для `App/`).
- Перегляд безпеки: `visitorData`, cookies і `Authorization` ніде не логуються; гостьовий запит структурно не має параметрів cookies.
- R1/T3 (залишки WebKit після `restore()`) не виправлено, лише примітка в 3.1.

## Fix pass

- M1: `AuthSession.completeSignIn` починається з `guard !isSigningOut else { return false }`; Cancel під час очищення WebKit більше не програє входу, що завершується. Усі виклики лишаються сумісними (`false` означає "продовжувати спостереження").
- Юніт-тест не додано: `isSigningOut` виставляється лише через `cancelSignIn`/`signOut`, які викликають `WKWebsiteDataStore`; тільки ручна перевірка/рев'ю.
- L1 (лише документація): примітку 3.1 в `docs/06-backlog.md` переписано (non-persistent store для гостя, стан "Keychain є, WebKit порожній"); уточнення в `docs/02-architecture.md` §6.
