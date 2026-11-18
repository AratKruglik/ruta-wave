# Звіт розробки: auth-signin (1.1)

## Файли
Створено: `Packages/Auth/Sources/Auth/{SignInRules,SessionCookies,KeychainItem,AuthSession,SignInView}.swift`, `Packages/Auth/Tests/AuthTests/{SignInRulesTests,SessionCookiesTests}.swift`, `App/SignedInPlaceholderView.swift`.
Змінено: `App/TunewaveApp.swift`, `docs/05-risks-and-scope.md` (§2 п.4, §4 #2).

## Відхилення від плану
- `KeychainItem` і `AuthSession.init(keychain:defaults:)` internal (тип не публічний); публічний `init()` викликає їх зі значеннями за замовчуванням. Причина: публічний API не може мати internal тип у значенні за замовчуванням.
- `KeychainItem` використовує typed throws (`throws(KeychainError)`), щоб `restore()` ловив `KeychainError` без касту.
- Додано `isSigningOut` (для вимкнення кнопки «Sign out», D9) і `clearSignInError()` (для «Try again»).
- «Try again»/«Reload» перестворюють web view через `.id(attempt)` замість скидання `didComplete` у координаторі. Результат той самий: новий координатор перевіряє cookies на `didFinish`.
- Cancel для add-account лише на sheet заглушки, у оверлеї помилки його немає (дублювання).
- Крок 3 (ручна перевірка `errSecMissingEntitlement` для `kSecUseDataProtectionKeychain`) не виконано: потребує запуску застосунку. Прапорця в коді немає.

## Тести
- `xcodegen generate && xcodebuild ... -quiet build`: без помилок і warnings.
- `swift test` у всіх 6 пакетах: Auth 8 тестів у 2 suites passed (+ smoke-тести інших пакетів по 1), failed 0.
- D4: round-trip через `properties` → plist зберігає `HttpOnly` і `sameSitePolicy`, план B не потрібен.
- `grep print/Logger/os_log/NSLog` у `Packages/Auth`: порожньо.

## Лишається
- Ручний AC8/AC9 (go/no-go) користувачем: вхід, перезапуск, вихід, add-account (перевірити, що `AddSession` показує форму), запит Keychain після збірки.
- Реальні cookies WebKit можуть мати значення в `properties`, що не серіалізуються в plist (ризик з §10 плану): проявиться як `signInError` на go/no-go.
- `requiredNames` (`SID`, `HSID`, `SSID`) не перевірено на реальних cookies `youtube.com`.
- Ізоляція `cookiesDidChange` (nonisolated + Task на MainActor) і `Task` у `checkSignIn` — для рев'ю QA.

## Fix pass

- High #1 (docs): `docs/05-risks-and-scope.md` §2 п.4 (рядки 32-40) замінено приписаним англійським текстом. Статус: "accepted for personal use (user decision, 2026-11-18, re-confirmed after the security review)". Код не змінювався.
- Medium #1: `Packages/Auth/Sources/Auth/AuthSession.swift`
  - `addAccount()` не діє, поки `isSigningOut`.
  - `signOut()` тепер спершу очищає WebKit, потім видаляє елемент Keychain, потім скидає `authUserIndex` і ставить `.signedOut`.
  - Збій `keychain.delete()` лишає `signOutError` і стан `.signedIn`.
  - Зайвий `defaults.removeObject` прибрано: `didSet` усе одно записує ключ.
- `App/SignedInPlaceholderView.swift:10-11`: кнопку "Add account" вимкнено через `.disabled(session.isSigningOut)`.
- Відхилення: `removeData` не кидає помилок, тому гілки "збій очищення WebKit, не чіпати Keychain" немає. Єдина помилка виходу тепер від Keychain, `signOutError` має тип `KeychainError`, тож не змінювався.
- `docs/plans/auth-signin/04-security.md`: додано рядки статусу під High #1 (прийнято, docs/05 оновлено) і Medium #1 (виправлено у fix pass).
- Тест: `test_command` пройшов з першої спроби (збірка і `swift test` по всіх пакетах).
