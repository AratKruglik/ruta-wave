# План розробки: InnerTube core — WEB_REMIX, SAPISIDHASH, account_menu, екран акаунта (backlog 1.2)

Джерело вимог: `01-business-analysis.md` разом із «Відповідями на відкриті питання» від 2026-11-18. Вони мають пріоритет над рекомендаціями BA:
- список акаунтів береться з `account/accounts_list`, лише Google-акаунти, а якщо AC13 не підтвердить шляхи, показуємо тільки активний акаунт;
- після «Add account» лишаємось на поточному акаунті;
- 401 веде в стан помилки без автовиходу;
- `hl`/`gl` беруться з локалі, запасні значення `en`/`US`;
- `clientVersion` — константа;
- brand-акаунти не показуються.

## 1. Форма проєкту

| Ключ | Значення |
|---|---|
| Система проєкту | XcodeGen (`project.yml`, `sources: [App]`). `Tunewave.xcodeproj` у gitignore. Нові файли в `App/` підхоплюються після `xcodegen generate`, pbxproj руками не правимо |
| Таргети | один `Tunewave` (macOS application), deployment target macOS 14.0. Extensions немає |
| Swift | `SWIFT_VERSION 6.0`, пакети на `swift-tools-version: 6.0` (strict concurrency Swift 6). Тулчейн Swift 6.4.2 |
| UI | SwiftUI App lifecycle, один `WindowGroup`, корінь перемикається за `session.state` |
| Стан | Observation (`@MainActor @Observable`), як `AuthSession` |
| Персистентність | Keychain (cookies), `UserDefaults` (`authUserIndex`). Нової немає |
| Навігація | немає, корінь `WindowGroup` |
| Модулі | локальні SPM-пакети `Packages/*`, граф `InnerTube → Auth` уже є в `Package.swift` |
| Локалізація | String Catalog немає, рядки англійською в коді, як в 1.1 |
| Дизайн-система | немає, системні шрифти й кольори |
| Тести | Swift Testing у пакетах. У застосунку тестового таргета немає |
| Залежності | сторонніх немає. Додаються лише системні `CryptoKit` (SHA-1) і `Foundation` (`URLSession`) |

## 2. Файли

### Створити

| Файл | Тип | Призначення, ключові сигнатури |
|---|---|---|
| `Packages/InnerTube/Sources/InnerTube/JSONValue.swift` | model | `enum JSONValue: Decodable, Sendable, Equatable { case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null }`. `subscript(key: String) -> JSONValue?`, `subscript(index: Int) -> JSONValue?` (повертають `nil` для відсутнього ключа, індексу поза межами чи не того типу), `var string: String?`, `var double: Double?`, `var bool: Bool?`, `var array: [JSONValue]?`. Декодування через `singleValueContainer` у порядку `null → Bool → Double → String → [JSONValue] → [String: JSONValue]`. Тип `internal`, бо застосунку він не потрібен |
| `Packages/InnerTube/Sources/InnerTube/SAPISIDHash.swift` | service (чиста функція) | `enum SAPISIDHash { static func make(sapisid: String, timestamp: Int, origin: String) -> String }` повертає `"<ts>_<sha1 hex>"` через `Insecure.SHA1` з CryptoKit |
| `Packages/InnerTube/Sources/InnerTube/InnerTubeRequest.swift` | client (чиста логіка) | `enum InnerTubeRequest`: `static let origin = "https://music.youtube.com"`, `static let clientVersion = "1.20261115.14.00"`, `static func make(endpoint: String, body: [String: String] = [:], cookies: [HTTPCookie], authUserIndex: Int, now: Date, locale: Locale) throws(InnerTubeError) -> URLRequest`. Деталі в D3 |
| `Packages/InnerTube/Sources/InnerTube/InnerTubeClient.swift` | client | `public actor InnerTubeClient`: `public init()`, `public func accountMenu(cookies: [HTTPCookie], authUserIndex: Int) async throws -> AccountInfo`, `public func accountsList(cookies: [HTTPCookie], authUserIndex: Int) async throws -> [AccountListItem]`, приватний `post(...) async throws -> JSONValue`. Тут також `public enum InnerTubeError: Error, Sendable { case missingSAPISID, httpStatus(Int), unexpectedResponse }` і приватний `final class RejectRedirects: NSObject, URLSessionTaskDelegate, Sendable` |
| `Packages/InnerTube/Sources/InnerTube/AccountInfo.swift` | model + parser | `public struct AccountInfo: Sendable, Equatable { name: String; handle: String?; avatarURL: URL? }`, `init(accountMenu json: JSONValue) throws(InnerTubeError)`. Шлях за [YM]: `actions[0].openPopupAction.popup.multiPageMenuRenderer.header.activeAccountHeaderRenderer`. Тут же `internal` хелпери `text` (`runs[0].text` або `simpleText`) і `lastThumbnailURL`, спільні з парсером списку |
| `Packages/InnerTube/Sources/InnerTube/AccountListItem.swift` | model + parser | `public struct AccountListItem: Sendable, Equatable, Identifiable { name; byline: String?; avatarURL: URL?; authUserIndex: Int; isSelected: Bool; id: Int { authUserIndex } }`, `static func list(accountsList json: JSONValue) -> [AccountListItem]`. Парсер толерантний: збирає всі об'єкти `accountItem` у відповіді (рекурсивний обхід, бо точний шлях не підтверджено, див. D5). Індекс береться з параметра `authuser` у `serviceEndpoint.selectActiveIdentityEndpoint.supportedTokens[].accountSigninToken.signinUrl`. Елемент відкидається, якщо в нього є `pageIdToken` (brand), немає `accountName` або немає індексу, що розбирається |
| `Packages/InnerTube/Tests/InnerTubeTests/JSONValueTests.swift` | test | AC1 |
| `Packages/InnerTube/Tests/InnerTubeTests/SAPISIDHashTests.swift` | test | AC2, вектор у §6 |
| `Packages/InnerTube/Tests/InnerTubeTests/InnerTubeRequestTests.swift` | test | AC3, AC4 |
| `Packages/InnerTube/Tests/InnerTubeTests/AccountParsingTests.swift` | test | AC5, AC6. Синтетичні фікстури як raw-string літерали (`#"""…"""#`) у файлі тесту. Ресурси й зміни `Package.swift` не потрібні |
| `App/AccountModel.swift` | model | `@MainActor @Observable final class AccountModel`: `enum State { case loading, loaded(AccountInfo, [AccountListItem]), failed }`, `private(set) var state: State = .loading`, `@ObservationIgnored private let client = InnerTubeClient()`, `func load(session: AuthSession) async`. Деталі в D6 |

### Змінити

| Файл | Що і навіщо |
|---|---|
| `App/SignedInPlaceholderView.swift` → **`App/AccountView.swift`** (перейменування, **потрібне погодження**, див. §8) | `struct AccountView: View { let session: AuthSession; @State private var model = AccountModel(); @State private var attempt = 0 }`. Вміст за станом: `.loading` → `ProgressView`; `.loaded` → `AccountHeader` (аватар через `AsyncImage` із заглушкою `person.crop.circle`, ім'я, handle) і список акаунтів, де кожен рядок — кнопка перемикання з позначкою `isSelected`; `.failed` → «Couldn't load your account» і кнопка «Retry» (`attempt += 1`). Під станом завжди є «Add account», «Sign out» і повідомлення `signOutError`, як зараз, разом із sheet add-account без змін. `.task(id: ReloadKey(index: session.authUserIndex, attempt: attempt)) { await model.load(session: session) }`. `.onChange(of: session.isAddingAccount) { _, adding in if !adding { attempt += 1 } }`. `#Preview` лише для `AccountHeader` на синтетичних даних, бо `AuthSession()` читає справжній Keychain |
| `App/TunewaveApp.swift` | `.signedIn` → `AccountView(session:)` |
| `Packages/Auth/Sources/Auth/AuthSession.swift` | FR14: (а) у `restore()`, гілка `.signedOut, .corrupt`, `if data != nil { try? keychain.delete(); authUserIndex = 0 }`; (б) у `completeSignIn`, перед `state = .signedIn`, `if !isAddingAccount { authUserIndex = 0 }` |
| `docs/05-risks-and-scope.md` §4 #2 | виправити: список акаунтів береться з `account/accounts_list`, а не з `account_menu`; brand-акаунти поза 1.2 |
| `docs/02-architecture.md` §6 п.1 | уточнити: у 1.2 unauthorized-відповідь показує помилку з Retry/Sign out, а перехід до входу з'явиться в 2.1 (відповідь користувача №3) |

### Не змінювати

- `Packages/InnerTube/Package.swift`: CryptoKit системний, фікстури inline. `project.yml`, entitlements, `Info.plist`: мережа без sandbox не потребує нічого нового.
- `InnerTubeModule.swift` і його smoke-тест лишаються, як `AuthModule` в 1.1.
- `docs/06-backlog.md`: статус оновлює фаза документації.

## 3. Рішення

- **D1. Клієнт отримує знімок, а не `AuthSession`** (FR6). Методи клієнта приймають `cookies: [HTTPCookie]` і `authUserIndex: Int`. `HTTPCookie` у SDK позначено `NS_SWIFT_SENDABLE`, тож межа `@MainActor → actor` чиста без обгорток. Окремий тип `InnerTubeAuth` не додаємо: два параметри простіші. Шов в `AuthSession` / `KeychainItem` не потрібен.
- **D2. Actor без змінного стану.** Зараз він тримає лише `URLSession`. Actor лишається, бо так визначено в docs/02 §5.3 і backlog, а 2.1 додасть у нього кеш версії. Логіку запиту винесено в чисту `InnerTubeRequest.make`, щоб тести не потребували мережі.
- **D3. Побудова запиту** (`InnerTubeRequest.make`):
  - URL `https://music.youtube.com/youtubei/v1/<endpoint>?prettyPrint=false`, метод `POST`. Хост фіксований, `endpoint` задає лише код пакета.
  - Тіло — `JSONSerialization` словника `{"context":{"client":{clientName, clientVersion, hl, gl}}}` разом з `body`. `hl` = `locale.language.languageCode?.identifier ?? "en"`, `gl` = `locale.region?.identifier ?? "US"`.
  - `Cookie` = `HTTPCookie.requestHeaderFields(with:)` від `SignInRules.musicCookies(cookies)`, з яких відкинуто прострочені (`expiresDate ?? .distantFuture > now`). Повторно використовуємо фільтр доменів з 1.1, а Keychain і так містить лише ці домени.
  - `SAPISID` береться лише з cookie домену `youtube.com` / `.youtube.com` (FR5). Однойменна cookie на `music.youtube.com` ігнорується, а тест це фіксує. Якщо cookie немає, запит не будується: `throw .missingSAPISID`.
  - `Authorization: SAPISIDHASH <SAPISIDHash.make(…, timestamp: Int(now.timeIntervalSince1970), origin:)>`, `X-Goog-AuthUser: "\(authUserIndex)"`, `Origin` і `X-Origin` = origin, `Content-Type: application/json`, `User-Agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) " + SignInRules.safariApplicationName`.
  - `request.httpShouldHandleCookies = false`: інакше URLSession може замінити наш `Cookie`.
- **D4. Транспорт без слідів на диску** (NFR, Info 7 з [S1]):
  - `URLSessionConfiguration.ephemeral` з `httpCookieStorage = nil`, `httpShouldSetCookies = false`, `urlCache = nil`, тож `Set-Cookie` ігнорується;
  - редіректи відхиляються делегатом (`willPerformHTTPRedirection` → `nil`), тому 3xx стає `httpStatus` і заголовки сесії не йдуть на інший хост;
  - не-2xx дає `.httpStatus(code)`, нерозбірний JSON — `.unexpectedResponse`;
  - помилки не містять тіл, заголовків чи cookies, а логування немає зовсім.
- **D5. Список акаунтів** (FR8, відповідь №1). Запит `account/accounts_list` з тілом `context` + `requestType: "ACCOUNTS_LIST_REQUEST_TYPE_CHANNEL_SWITCHER"`, `callCircumstance: "SWITCHING_USERS_FULL"`. Ці поля й шляхи `accountItem` за [YJ] мають статус **[known, verify at AC13]**. Парсер шукає `accountItem` рекурсивно, а не жорстким шляхом, щоб невеликий зсув структури не ламав список. Збій або порожній список **не фатальні**: модель показує лише активний акаунт без перемикання, що й є запасним варіантом (в) з відповіді №1. Так що б не показала AC13, код однаково коректний.
- **D6. Модель екрана й перегони** (FR9, FR11–FR13, FR15, AC8):
  - `load(session:)` бере `cookies` з `session.state` (якщо там не `.signedIn`, нічого не робить) і `index = session.authUserIndex`. Далі `state = .loading`, `account_menu` і `accounts_list` виконуються паралельно через `async let`. Збій списку перетворюється на `[]`.
  - Після `await` стоїть `guard !Task.isCancelled else { return }`. `.task(id:)` скасовує попередню задачу, коли змінюється `authUserIndex` або `attempt`, а при «Sign out» `AccountView` зникає разом із задачею і моделлю. Тому відповідь для A не перезапише B, а після виходу нічого не запишеться. Лічильник поколінь не потрібен.
  - FR15 спрацьовує лише тоді, коли список непорожній, задача не скасована і `index` відсутній серед `authUserIndex` елементів. Тоді виконується `session.authUserIndex = 0`, і `.task(id:)` перезавантажує екран сам. Елементи без розібраного індексу парсер уже відкинув (D5). Якщо список порожній (запасний варіант), скидання не відбувається, щоб помилковий парсер не повертав користувача на акаунт 0 після кожного перемикання.
  - Перемикання — це `session.authUserIndex = item.authUserIndex`. Сесія в Keychain не змінюється.
  - «Add account» оновлює список, коли закривається sheet (`isAddingAccount` → `false`), і активний акаунт не змінюється (відповідь №2). Скасування sheet теж дає одне перезавантаження. Це свідомий компроміс замість окремого сигналу «успіх».
  - Будь-яка помилка `accountMenu` переводить екран у `.failed`. Автовиходу немає (відповідь №3).
- **D7. `clientVersion` = `"1.20261115.14.00"`.** Значення отримано 2026-11-18 неавторизованим `curl` публічної сторінки `music.youtube.com` (grep `INNERTUBE_CLIENT_VERSION`). Перед реалізацією його треба перечитати, а AC13(6) його підтверджує. Біля константи стоїть коментар `shortcut: fixed version, replaced by page discovery in 2.1`.
- **D8. `JSONValue` лише в межах потреб 1.2:** доступ за ключем та індексом і скалярні аксесори. Хелпери `runs`/`continuation` не додаються (2.1/2.2). `text` і `lastThumbnailURL` — `internal` функції в `AccountInfo.swift`.

## 4. Порядок реалізації (TDD для чистих частин)

1. `JSONValue` + `JSONValueTests`.
2. `SAPISIDHash` + `SAPISIDHashTests`.
3. `InnerTubeRequest` + `InnerTubeRequestTests`.
4. `AccountInfo`, `AccountListItem` + `AccountParsingTests`.
5. `InnerTubeClient` (транспорт).
6. `AuthSession` FR14.
7. `AccountModel`, `AccountView`, `TunewaveApp`.
8. Правки docs/05 і docs/02.
9. Перевірка командою з §7.

## 5. Покриття AC

| AC | Як задовольняється | Перевірка |
|---|---|---|
| AC1 | `JSONValue` (D8) | `JSONValueTests`: вкладені об'єкти й масиви; `true`, `false`, `0`, `1`, `1.5` декодуються у правильні випадки (`0`/`1` — це `.number`, а не `.bool`); `null`; відсутній ключ, індекс поза межами, ключ на масиві та індекс на об'єкті дають `nil` |
| AC2 | `SAPISIDHash.make` | вектор у §6 і перевірка формату `^\d+_[0-9a-f]{40}$` |
| AC3 | D3 | `InnerTubeRequestTests`: метод, повний URL, тіло, розібране через `JSONValue` (`clientName == "WEB_REMIX"`, непорожні `clientVersion`/`hl`/`gl`), `hl`/`gl` для `Locale(identifier: "uk_UA")` і запасні значення для `Locale(identifier: "")` |
| AC4 | D3 | синтетичні cookies (значення `test-…`): `SAPISID` на `.youtube.com`, `SAPISID` з іншим значенням на `music.youtube.com`, прострочена cookie та cookie `.google.com`. Перевіряємо: `Cookie` без простроченої й `google.com`; `Authorization` дорівнює `SAPISIDHASH ` + `make` від значення з `.youtube.com` при фіксованому `now`; `X-Goog-AuthUser == "1"`; `Origin`/`X-Origin`; `httpShouldHandleCookies == false`; без `SAPISID` — `throws .missingSAPISID` |
| AC5 | `AccountInfo(accountMenu:)` | повна фікстура → `name`/`handle`/`avatarURL` (остання мініатюра); без `channelHandle` і `accountPhoto` → лише `name`; без `accountName` → `throws` |
| AC6 | `AccountListItem.list` | фікстура: два Google-акаунти (`authuser=0` вибраний, `authuser=1`) і brand-елемент з `pageIdToken` → 2 елементи з правильними індексами та `isSelected`; елемент без `authuser` відкинуто; `JSONValue.null` → `[]` |
| AC7 | D4, D6 | рев'ю + ручна перевірка (вимкнути мережу → «Retry») |
| AC8 | D6 (`.task(id:)` + `Task.isCancelled`) | рев'ю + ручна перевірка (швидке перемикання, Sign out під час завантаження) |
| AC9 | правка `AuthSession` | рев'ю (шва немає, за рішенням BA) |
| AC10 | D6 | рев'ю: логіка — один `guard` у моделі застосунку, а тестового таргета в застосунку немає |
| AC11 | D4, NFR | рев'ю + `grep -rnE 'print\(|Logger|os_log|NSLog|debugPrint|dump\(' Packages/*/Sources Packages/*/Tests App` (очікувано порожньо), `grep -rn 'HTTPCookieStorage.shared\|URLCache.shared\|URLSession.shared' Packages/*/Sources App` (очікувано порожньо; `AsyncImage` вантажить аватар без cookies сесії), огляд фікстур на синтетичні дані |
| AC12 | — | команда з §7 |
| AC13 | — | ручна перевірка користувачем (§6). Результат записується в `docs/plans/innertube-core/` |

## 6. Тестова стратегія

- **Unit (`swift test` у `Packages/InnerTube`)**: усе з таблиці §5 для AC1–AC6. Мережі, Keychain і `UserDefaults` немає. Фікстури зібрано вручну, вони синтетичні: `Test User`, `@testhandle`, `Second User`, `https://example.com/avatar.png`, cookies зі значеннями `test-…`. Це не очищені реальні відповіді.
- **Вектор SAPISIDHASH**: `SAPISID = "test-sapisid-value"`, `ts = 1700000000`, `origin = "https://music.youtube.com"` → `1700000000_0c0d2e2ebe5f3603ce622ae1dceaa2917419aeb8`. Очікуване значення обчислено незалежно двома інструментами: `printf '%s' '1700000000 test-sapisid-value https://music.youtube.com' | shasum -a 1` і `| openssl dgst -sha1`, обидва дали однаковий результат. Вхідні дані й команда записуються коментарем біля тесту.
- **Auth**: наявні тести не змінюються, FR14 перевіряється рев'ю.
- **Мережевий транспорт** (`InnerTubeClient.post`: не-2xx, редірект) unit-тестами не покривається, бо `URLProtocol`-стаб означав би новий шов заради двох рядків. Перевіряється рев'ю й AC13.
- **Ручна перевірка (AC13, користувач)**: (1) ім'я та аватар після входу; (2) ⌘Q → запуск → ім'я без входу; (3) «Add account» з реальним другим акаунтом → акаунт у списку; (4) перемикання змінює ім'я й аватар і зберігається після перезапуску; (5) «Sign out» → вхід; (6) робочий `clientVersion`, приймання `SAPISIDHASH` і **семантика `accounts_list`** (чи це Google-акаунти сесії з `authuser`, а не канали поточного акаунта). Шляхи JSON звіряються у DevTools браузера на `music.youtube.com` (запит `accounts_list` у меню «Switch account»), а відповідь у репозиторій не зберігається. Для пунктів 1–4 корисно (не обов'язково) вимкнути мережу і перевірити «Retry».

## 7. Перевірка

`xcodegen generate && xcodebuild -project Tunewave.xcodeproj -scheme Tunewave -destination 'platform=macOS,arch=arm64' -quiet build && for p in Packages/*/; do (cd "$p" && swift test) || exit 1; done`. Усі помилки й нові warnings Swift 6 виправляються до звіту.

## 8. Ризики та що потребує рішення користувача

**Потребує погодження:**
1. **Перейменувати `App/SignedInPlaceholderView.swift` на `App/AccountView.swift`** (через `git mv`, а не видалення плюс новий файл). BA каже «замінює», але правило конвеєра забороняє видаляти файли без явного дозволу. Альтернатива — лишити ім'я файлу й змінити лише вміст, що теж працює, але вводить в оману.

**Ризики:**
- **Семантика `accounts_list` не підтверджена** [known з youtubei.js]. Тіло запиту, шляхи `accountItem` і спосіб отримати `authuser` (параметр у `signinUrl`) — найкраще наявне знання, але не перевірене. Якщо AC13(6) не підтвердить, що список містить Google-акаунти сесії з індексами, у тому ж рядку беклогу вимикається і список, і FR15 (запасний варіант (в), відповідь №1): `AccountModel` просто не викликає `accountsList`. Залишати FR15 увімкненим на непідтвердженому списку не можна (D6 і так блокує скидання при порожньому списку).
- **URLSession і зарезервовані заголовки.** Apple документує `Authorization` і `Cookie` як заголовки, якими керує система завантаження. Відповідь — `httpShouldHandleCookies = false` на запиті й конфігурації. Чи доходить `Authorization` без змін, підтверджує AC13 (ім'я завантажилось).
- **`SAPISIDHASH` без `SAPISID1PHASH`/`SAPISID3PHASH`.** Якщо AC13 покаже 401 або 403, формат розширять (BA, «Граничні випадки»).
- **`clientVersion` застаріває.** Це свідомий борг до 2.1, а значення треба перечитати перед реалізацією.
- **Ротація cookies** (ризик #8): `Set-Cookie` ігнорується, тож з часом можливий 401, який дасть стан помилки. Обробка — у 2.1.
- **Context7 не використано**: інструменти Context7 у цій сесії недоступні. Відомості про youtubei.js і ytmusicapi взято з BA ([YM], [YJ]) і загальних знань, тому вони мають статус [known, verify at AC13].
