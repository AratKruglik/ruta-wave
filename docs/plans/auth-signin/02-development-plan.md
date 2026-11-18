# План розробки: Auth — вхід через Google у WKWebView, cookies у Keychain, вихід (backlog 1.1)

Джерело вимог: `01-business-analysis.md` разом із розділом «Відповіді на відкриті питання» від 2026-11-18. Його рішення мають пріоритет: cookies на диску WebKit приймаються, стан визначає лише Keychain, у 1.1 є кілька акаунтів через `authUserIndex` і `addAccount()`.

## 1. Форма проєкту

| Ключ | Значення |
|---|---|
| Система проєкту | XcodeGen (`project.yml`). `Tunewave.xcodeproj` генерується і є в gitignore. Новий файл у `App/` компілюється після `xcodegen generate`, ручних правок pbxproj немає |
| Таргети | один `Tunewave` (application, macOS), deployment target macOS 14.0. Інших платформ і extensions немає |
| Swift | `SWIFT_VERSION 6.0` у застосунку, `swift-tools-version: 6.0` у пакетах (strict concurrency за замовчуванням Swift 6). Тулчейн Swift 6.3 / Xcode 27.2 |
| Підпис | ad-hoc (`CODE_SIGN_IDENTITY "-"`, `DEVELOPMENT_TEAM ""`), Hardened Runtime увімкнено, sandbox вимкнено, `.entitlements` немає |
| UI | SwiftUI App lifecycle (`@main TunewaveApp`, один `WindowGroup`) |
| Стан | Observation (`@MainActor @Observable`, docs/02 §4.3, §7). Коду стану ще немає |
| Персистентність | ще немає. Секрети в Keychain, налаштування в `UserDefaults` (docs/02 §1) |
| Навігація | ще немає. Корінь `WindowGroup` |
| Модулі | локальні SPM-пакети `Packages/{Auth,AppSettings,InnerTube,PlayerEngine,Plugins,SystemKit}`. `Auth` і `AppSettings` — листи графа |
| Локалізація | String Catalog і `.strings` відсутні. Рішення про локалізацію — етап 4 (docs/05 §4 #7) |
| Дизайн-система | відсутня (asset catalog немає) |
| Тести | Swift Testing, `swift test` у кожному пакеті |
| Залежності | жодних сторонніх. WebKit, Security і SwiftUI — системні фреймворки, лінкуються автоматично через `import` |

## 2. Файли

### Створити

| Файл | Тип | Призначення |
|---|---|---|
| `Packages/Auth/Sources/Auth/SignInRules.swift` | model (чиста логіка) | `enum SignInRules`: `signInURL`, `addAccountURL`, `allowedHosts`, `isAllowedMainFrameNavigation(_ url: URL) -> Bool`, `musicCookies(_ cookies: [HTTPCookie]) -> [HTTPCookie]` (домен `youtube.com` / `.youtube.com` / `music.youtube.com`), `isSignInComplete(mainFrameURL: URL?, cookies: [HTTPCookie]) -> Bool`, `safariApplicationName` для UA |
| `Packages/Auth/Sources/Auth/SessionCookies.swift` | model (чиста логіка) | `enum SessionCookies`: `requiredNames` (`SAPISID`, `__Secure-3PAPISID`, `SID`, `HSID`, `SSID`, один константний список), `encode(_ cookies: [HTTPCookie]) throws -> Data`, `restore(from data: Data?, now: Date) -> RestoreOutcome` (`.signedIn([HTTPCookie])`, `.signedOut`, `.corrupt`) |
| `Packages/Auth/Sources/Auth/KeychainItem.swift` | service | `struct KeychainItem: Sendable { service, account }`, `static let session = KeychainItem(service: "dev.kruhlyk.tunewave.session", account: "default")`, `read() throws -> Data?`, `write(_ data: Data) throws`, `delete() throws`. Тонка обгортка над `SecItem*`, без протоколу. `struct KeychainError: LocalizedError { status: OSStatus }` з текстом від `SecCopyErrorMessageString` |
| `Packages/Auth/Sources/Auth/AuthSession.swift` | model | `@MainActor @Observable public final class AuthSession`: `state`, `authUserIndex`, `restore()`, `completeSignIn(with:)`, `signOut() async`, `addAccount()` / `isAddingAccount`. Деталі в §4 |
| `Packages/Auth/Sources/Auth/SignInView.swift` | screen + view | `public struct SignInView: View` (web view, оверлей помилки з кнопкою «Try again», для режиму add-account ще кнопка «Cancel») і приватний `SignInWebView: NSViewRepresentable` з `Coordinator` (`WKNavigationDelegate`, `WKUIDelegate`, `WKHTTPCookieStoreObserver`) |
| `Packages/Auth/Tests/AuthTests/SignInRulesTests.swift` | test | AC1, AC2, фільтр доменів |
| `Packages/Auth/Tests/AuthTests/SessionCookiesTests.swift` | test | AC3, AC4 |
| `App/SignedInPlaceholderView.swift` | view | тимчасова заглушка «Signed in» з кнопками «Add account» і «Sign out». Add-account відкривається як `.sheet` |

### Змінити

| Файл | Що і навіщо |
|---|---|
| `App/TunewaveApp.swift` | `@State private var session = AuthSession()`. Корінь `WindowGroup` перемикається за `session.state`: `.signedOut` → `SignInView(session:)`, `.signedIn` → `SignedInPlaceholderView(session:)`, `.keychainUnavailable(error)` → повідомлення з кнопкою «Try again» (`session.restore()`). Збільшити `minWidth/minHeight` під сторінку Google (≈ 520×640) |
| `docs/05-risks-and-scope.md` §2 п.4 («Credentials», у BA «§2.4») | переписати, текст у §6 |
| `docs/05-risks-and-scope.md` §4 #2 | закрити питання про кілька акаунтів, текст у §6 |

### Не змінювати

- `Packages/Auth/Package.swift` і `project.yml`: WebKit і Security лінкуються автоматично, entitlements, ключі `Info.plist` і capabilities не потрібні.
- `Packages/Auth/Sources/Auth/AuthModule.swift` і його тест лишаються. Видаляти їх не обов'язково, а тест — це smoke-тест пакета.
- `AppSettings`: `authUserIndex` живе в `Auth`. Пояснення в рішенні D5.

## 3. Порядок реалізації

1. **`SignInRules.swift` + `SignInRulesTests.swift`** (TDD): allowlist, фільтр доменів, предикат успіху. Ні від чого не залежить.
2. **`SessionCookies.swift` + `SessionCookiesTests.swift`** (TDD): кодек і `restore(from:now:)`. Залежить від `SignInRules.musicCookies` лише опосередковано.
3. **`KeychainItem.swift`**. Ручна перевірка на початку: одноразово (у Debug-збірці застосунку, не в тестах) переконатися, що запит із `kSecUseDataProtectionKeychain: true` повертає `errSecMissingEntitlement` (-34018), і записати результат у звіт розробки. У коді цього прапорця немає.
4. **`AuthSession.swift`** на кроках 1–3.
5. **`SignInView.swift`** на `AuthSession` і `SignInRules`.
6. **`App/SignedInPlaceholderView.swift`, `App/TunewaveApp.swift`**.
7. **Збірка й тести** командою з project_shape (§8).
8. **docs/05**: §2 п.4 і §4 #2.
9. **Go/no-go (виконує користувач, не агент)**: ручний AC8 і запис результату (AC9) у `docs/plans/auth-signin/` або docs/05 §1 #1. Цей крок блокує 1.2, але не цей PR.

## 4. Публічний контракт `Auth` (для App і 1.2)

```swift
@MainActor @Observable
public final class AuthSession {
    public enum State {
        case signedOut
        case signedIn(cookies: [HTTPCookie])     // для 1.2: SAPISID і заголовок Cookie
        case keychainUnavailable(KeychainError)  // читання відмовлено / збій, не «вийшов»
    }
    public private(set) var state: State
    public private(set) var signInError: (any Error)?     // збій encode / запису після входу (AC6)
    public private(set) var signOutError: KeychainError?  // збій видалення елемента під час виходу
    public var authUserIndex: Int                          // UserDefaults, ключ "authUserIndex", за замовчуванням 0
    public private(set) var isAddingAccount: Bool

    public init(keychain: KeychainItem = .session, defaults: UserDefaults = .standard)  // викликає restore()
    public func restore()
    public func addAccount()            // isAddingAccount = true, authUserIndex не змінює
    public func cancelAddAccount()
    public func signOut() async
    func completeSignIn(with cookies: [HTTPCookie]) -> Bool  // internal, викликає SignInView; false = набір ще неповний
}

public struct SignInView: View { public init(session: AuthSession) }
```

`HTTPCookie` — форма, яку дає платформа (BA: «Доступ до cookies»). 1.2 читає `authUserIndex` для `X-Goog-AuthUser`.

## 5. Ключові рішення

**D1. Подання входу на macOS 14: вміст головного `WindowGroup`, а не окрема `Window`-сцена.** Корінь вікна перемикається за `session.state`. Add-account відкривається як `.sheet` із `SignInView` і кнопкою «Cancel» на заглушці. Причини:
- закрите без входу вікно знову відкривається кліком на іконку в Dock або через File → New Window, перезапуск не потрібен;
- `Window("Sign in")` macOS відновлює під час запуску навіть у стані «увійшов»;
- модель не може викликати `openWindow`, тож `addAccount()` лише ставить прапорець, а sheet спостерігає за ним.

`WKWebView` вбудовується через `NSViewRepresentable`. Розмір мінімального вікна збільшується під сторінку Google.

**D2. Keychain з ad-hoc підписом: файловий login keychain, generic password.** Атрибути: `kSecClass: kSecClassGenericPassword`, `kSecAttrService: "dev.kruhlyk.tunewave.session"`, `kSecAttrAccount: "default"`, `kSecValueData`. Яких атрибутів немає і чому:
- `kSecUseDataProtectionKeychain`: без team ID і keychain-access-groups він дає `errSecMissingEntitlement` (-34018). Розробник перевіряє це на кроці 3;
- `kSecAttrAccessible`: файловий keychain його ігнорує;
- `kSecAttrSynchronizable`: елементи файлового keychain не синхронізуються з iCloud, тож NFR «не синхронізується» виконано за конструкцією.

Запис спочатку викликає `SecItemUpdate`, а при `errSecItemNotFound` — `SecItemAdd`. Так запис ідемпотентний, і елемент завжди один (повторний успіх і add-account). `delete()` ігнорує `errSecItemNotFound`. Наслідок ризику #11: після перезбирання macOS запитує доступ, бо ACL прив'язаний до cdhash. Це очікувано (AC8).

Модель загроз: `security find-generic-password -s dev.kruhlyk.tunewave.session -w` може прочитати елемент лише після запиту користувачу. Файли WebKit у `~/Library/WebKit/dev.kruhlyk.tunewave/` і `~/Library/HTTPStorages/dev.kruhlyk.tunewave*` доступні будь-якому процесу цього користувача. Це прийнято рішенням користувача №1 і фіксується в docs/05 §2 п.4.

**D3. Тести не створюють `KeychainItem` взагалі (AC5).** Навіть окремий тестовий service писав би в login keychain користувача з `swift test`. Шов для тестів — чиста функція `SessionCookies.restore(from: Data?, now: Date) -> RestoreOutcome`, `encode` і `SignInRules`. `AuthSession` у `swift test` не створюється, бо її `init` читає Keychain. Окремого протоколу чи mock-сховища немає (YAGNI). `AuthSession` і `KeychainItem` перевіряються вручну в AC8. Значення cookies у тестах синтетичні (`"test-value"`) і в `#expect` не виводяться: перевіряється рівність, сирі значення не друкуються.

**D4. Серіалізація: `[HTTPCookie.properties]` → binary property list.** `PropertyListSerialization.data(fromPropertyList: cookies.compactMap(\.properties), format: .binary)`, а відновлення через `HTTPCookie(properties:)`. Такий формат найповніший: зберігає всі атрибути, які платформа знає, зокрема `HttpOnly`, для якого немає публічного `HTTPCookiePropertyKey`. Тест AC3 перевіряє round-trip для `name`, `value`, `domain`, `path`, `expiresDate`, `isSecure`, `isHTTPOnly` і `sameSitePolicy`. Якщо `isHTTPOnly` або `sameSitePolicy` губляться, план B — `Codable`-структура з цих полів, яка ставить ключ `"HttpOnly"` вручну. Рішення фіксується за результатом тесту.

**D5. `authUserIndex` — в `Auth` на `UserDefaults`, а не в `AppSettings`.** За docs/02 §2 `Auth` і `AppSettings` — листи, а `InnerTube → Auth`. Якщо індекс лежатиме в `AppSettings`, 1.2 доведеться додати нове ребро графа. Значення не секретне. `signOut()` видаляє ключ (індекс знову 0). `addAccount()` індекс не змінює: індекс нового акаунта невідомий до `account_menu` (1.2).

**D6. Навігація (FR2) — лише main frame, точний збіг хоста.** Умови: `url.scheme == "https"`, `host` (у нижньому регістрі) точно входить до `allowedHosts` = `accounts.google.com`, `accounts.youtube.com`, `consent.google.com`, `consent.youtube.com`, `music.youtube.com`, `www.youtube.com`, `myaccount.google.com`, `www.google.com`. Суфіксного збігу немає, тож `google.com.evil.example` і `notyoutube.com` відхиляються. Інші правила:
- subframes (`navigationAction.targetFrame?.isMainFrame == false`) пропускаються: reCAPTCHA, `RotateCookiesPage`, `about:blank`/`about:srcdoc` на сторінках Google інакше зламали б вхід, і це виглядало б як no-go від Google;
- заблоковану main-frame навігацію лише скасовано (`.cancel`), у браузер вона не відкривається;
- `WKUIDelegate.webView(_:createWebViewWith:for:windowFeatures:)` повертає `nil`, тож popup-вікон немає;
- регіональні домени (`google.com.ua`) додаються лише за фактом go/no-go.

**D7. Визначення успіху (FR3) і час появи cookies.** Перевірка запускається у двох місцях:
- `webView(_:didFinish:)`;
- `WKHTTPCookieStoreObserver.cookiesDidChange(in:)`, поки `webView.url?.host == "music.youtube.com"`.

Обидва місця викликають `await store.allCookies()` → `SignInRules.isSignInComplete`. Предикат: хост `music.youtube.com` **і** `SAPISID` з нормалізованим доменом `youtube.com` (з домену знімається початкова крапка).

Вхід і перезапуск перевіряються за тим самим правилом. `completeSignIn` приймає набір лише тоді, коли `SessionCookies.restore(from: encode(set), now:)` дає `.signedIn`, тобто коли всі `requiredNames` вже є. Інакше `completeSignIn` повертає `false`, `didComplete` не ставиться, і observer перевіряє далі. Без цього неповний набір (`SID`/`SSID` з'являються пізніше за `SAPISID`) дав би «увійшов» зараз і «не увійшов» після перезапуску. Після прийнятого набору координатор ставить `didComplete = true` і більше не перевіряє, тож циклу немає. Після `await allCookies()` координатор повторно перевіряє, що вхід іще актуальний (`state == .signedOut || isAddingAccount`), і лише тоді викликає `session.completeSignIn(with: SignInRules.musicCookies(all))`. Cookies `google.com` не зберігаються.

**D8. Помилки входу (AC6, мережа).**
- Збій запису в Keychain (зокрема відмова в доступі): `signInError` встановлено, стан лишається, `didComplete` лишається `true`. Автоматичного повтору немає. Кнопка «Try again» скидає `didComplete` і `signInError`, а тоді перевіряє ще раз.
- Збій читання під час запуску (будь-який статус, крім `errSecItemNotFound`): `.keychainUnavailable(error)` з кнопкою «Try again». Елемент **не** видаляється, і стан **не** стає `.signedOut`: інакше сторінка входу автоматично увійшла б зі сховища WebKit і викликала новий запит Keychain, тобто вийшов би цикл.
- Payload пошкоджений (`.corrupt`) або обов'язкова cookie прострочена (`.signedOut` за наявного елемента): в обох випадках `try? keychain.delete()` і стан `.signedOut` (Story 2). Cookies без `expiresDate` вважаються валідними.
- Помилка завантаження сторінки (`didFail` / `didFailProvisionalNavigation`): оверлей «Couldn't load the sign-in page» з кнопкою «Reload». Ігноруються `NSURLErrorCancelled` (-999) і `WebKitErrorDomain` 102 (frame load interrupted by policy change), інакше кожна скасована allowlist-ом навігація показувала б помилку.

**D9. Вихід (FR6) і перегони.** Порядок:
1. `try keychain.delete()`;
2. видалити ключ `authUserIndex`;
3. `await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)`;
4. лише тепер `state = .signedOut`.

Якщо перемкнути стан раніше, `SignInView` з'явиться, поки cookies WebKit ще не очищено. Google тоді увійде автоматично, і сесія «воскресне» (Story 3). Якщо видалення з Keychain не вдалося, `signOut` записує помилку в `signOutError` (показує заглушка) і стан не змінює. Поки вихід триває, кнопка «Sign out» неактивна. Вихід лише локальний.

**D10. User-Agent.** `configuration.applicationNameForUserAgent = "Version/<v> Safari/605.1.15"`, де `<v>` — `CFBundleShortVersionString` з `Bundle(path: "/Applications/Safari.app")` або константа `"17.0"`, якщо прочитати не вдалося (коментар `shortcut:`). WebKit сам додає префікс `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)`, ідентичний Safari, тож жорстко зашитого повного рядка, який застаріває, немає. Обидва web view (вхід зараз і плеєр у 3.1) мають ставити один UA, тому значення живе в `SignInRules.safariApplicationName`.

**D11. URL.** `signInURL` = `https://accounts.google.com/ServiceLogin?ltmpl=music&service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F` (як в оригіналі, docs/01 §4.2). `addAccountURL` = `https://accounts.google.com/AddSession?ltmpl=music&service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F`. ServiceLogin з живою сесією одразу перенаправляє на `music.youtube.com`, тож add-account мовчки нічого б не зробив. `AddSession` — **[known]**, його перевіряють на go/no-go, і в звіт записують URL, який справді показав форму входу.

**D12. Без логування, без String Catalog.** Пакет `Auth` нічого не логує, тож значення cookies не можуть потрапити в логи. `KeychainError` містить лише `OSStatus` і системний текст. Рядки інтерфейсу — літерали в `Text`/`Button` (`LocalizedStringKey`), каталог не додається до рішення етапу 4. Кожна кнопка має текстову мітку (VoiceOver). Кольорів і шрифтів немає, крім системних. Dark Mode підтримується за замовчуванням.

## 6. Тексти для docs/05

**§2 п.4 (заміна):**

> 4. **Credentials.** Session cookies give full access to the Google account within YouTube. The Keychain item (`dev.kruhlyk.tunewave.session`, login keychain, not synchronized) is the source of the app's session state and the cookies InnerTube sends. The WebKit website data store (`WKWebsiteDataStore.default()`, under `~/Library/WebKit` and `~/Library/HTTPStorages`) is the browser session cache the sign-in window and the player share. Like Safari's, it is readable by any process of the same user; this is accepted for personal use. Sign-out clears both. Cookie values are never logged and never end up in fixtures, test output or crash reports.

**§4 #2 (закриття):**

> | 2 | ~~Whether multiple accounts are needed (`X-Goog-AuthUser`)~~ — **decided: yes.** Google keeps all accounts in one cookie session, so one Keychain item holds it; `Auth` stores the selected `authUserIndex` (default 0) and offers `addAccount()` (stage 1.1). The account list and switching UI come with `account_menu` (stage 1.2). Sign-out ends the session of every account | — |

## 7. Тести (Swift Testing, `Packages/Auth/Tests/AuthTests`)

| Тест | Перевіряє |
|---|---|
| `isSignInComplete` true: `music.youtube.com` + `SAPISID` на `.youtube.com` | AC1 |
| false: `SAPISID` лише на `.google.com`; хост `www.youtube.com`/`accounts.google.com`; немає cookie; `url == nil` | AC1 |
| `SAPISID` на `.youtube.com` є, `SSID` бракує: `isSignInComplete` → true, але `restore(from: encode(set))` → `.signedOut` (набір ще не приймається, D7) | AC1/AC4 |
| allowlist: усі хости з D6 по https → true; `http://accounts.google.com`, `https://google.com.evil.example`, `https://notyoutube.com`, `https://evil.example`, `about:blank` (main frame) → false; регістр хоста (`Accounts.Google.com`) → true | AC2 |
| `musicCookies`: залишає `youtube.com`, `.youtube.com`, `music.youtube.com`; відкидає `.google.com`, `www.youtube.com`, `notyoutube.com` | FR4 |
| round-trip `encode` → `restore`: усі атрибути з D4, у тому числі `isHTTPOnly == true`, `sameSitePolicy == .lax`, `expiresDate == nil` | AC3 |
| `restore`: повний непрострочений набір → `.signedIn`; бракує `SSID` → `.signedOut`; `SID` прострочена (`now` після `expires`) → `.signedOut`; обов'язкові cookies без `expires` → `.signedIn`; `Data("garbage".utf8)` → `.corrupt`; `nil` → `.signedOut` | AC4 |

Тести не створюють `KeychainItem` і `AuthSession` і не торкаються `WKWebsiteDataStore` (AC5). `AuthModuleTests` лишається.

## 8. Перевірка

- `xcodegen generate && xcodebuild -project Tunewave.xcodeproj -scheme Tunewave -destination 'platform=macOS,arch=arm64' -quiet build`. Нових warnings бути не повинно.
- `for p in Packages/*/; do (cd "$p" && swift test) || exit 1; done`.
- `grep -rn "print(\|Logger\|os_log\|NSLog" Packages/Auth` має дати порожній результат (AC5, D12).
- Перечитати змінені файли на ізоляцію `@MainActor` координатора. Делегати WebKit у SDK позначені `@MainActor`. Для `WKHTTPCookieStoreObserver` потрібна `@preconcurrency`-відповідність або `nonisolated` + `MainActor.assumeIsolated`, бо WebKit викликає його в main thread. `Task` у делегатах захоплює `[weak self]`.
- Ручний AC8 виконує користувач. Агент облікових даних не вводить.

## 9. Скіли під час реалізації

`apple-plugin:swiftui-conventions`, `apple-plugin:swiftui-state`, `apple-plugin:swiftui-navigation`, `apple-plugin:macos-app`, `apple-plugin:apple-testing`, `swift-foundation:swift-conventions`, `swift-foundation:swift-testing`, `swift-foundation:swift-tooling`, `superpowers:test-driven-development` (кроки 1–2), `superpowers:verification-before-completion`. `apple-plugin:ios-ipados` і `apple-plugin:watchos-app` не застосовуються, бо таргетів iOS і watchOS немає.

## 10. Ризики та граничні випадки

| Ризик | Як план його обробляє |
|---|---|
| Google блокує `WKWebView` (ризик #1) | Safari UA (D10), subframes не обмежено (D6). Якщо блокування лишається, це no-go, і користувач обирає fallback до 1.2 |
| Хост поза allowlist у реальному потоці входу (регіональний домен, інший піддомен Google) | помилки немає, навігацію просто скасовано. Хост додають за фактом go/no-go |
| `HttpOnly` / `sameSite` не переживають `properties` → plist, або реальні cookies WebKit мають у `properties` значення, яке не можна записати в plist (напр. `URL`), і `encode` кидає помилку під час AC8 | синтетичний тест AC3 виявить лише перше. Друге проявиться як «save failed» на go/no-go. План B в обох випадках — `Codable`-структура (D4) |
| Запит доступу до Keychain після кожної збірки (#11) | очікувано. Відмова не спричиняє циклу (D8) |
| `AddSession` не показує форму | перевіряють на go/no-go, URL виправляють у 1.2. Це не блокує вхід |
| Обов'язкові cookies (`SID`, `HSID`, `SSID`) фактично відсутні на `youtube.com` | `restore` тоді завжди дає `.signedOut`, що проявиться на першому ж перезапуску AC8. Перелік `requiredNames` оновлюють за фактом |
| Перегони «вихід під час входу» | порядок D9 і повторна перевірка стану після `await allCookies()` (D7) |
| Розбіжність Keychain і сховища WebKit | у 1.1 стан визначає лише Keychain. Синхронізацію розв'язує 3.1 (рішення користувача №2) |
| Passkey не працює у `WKWebView` | обхід — «Try another way → пароль», це не no-go |

## Contract for frontend

No frontend contract
