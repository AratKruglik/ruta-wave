# План реалізації: гостьовий режим (backlog 1.4)

Прохід: PLAN. Код ще не змінено. Джерела: `_brief.md`, `01-business-analysis.md` (розділи «Результати проби A–D» і «Відповіді користувача» мають пріоритет над раніше запропонованими варіантами BA), `docs/02-architecture.md`, поточний код `Packages/Auth`, `Packages/InnerTube`, `App/`.

## 1. Форма проєкту

XcodeGen (`project.yml`, `sources: [App]` — нові файли в `App/` підхоплюються після `xcodegen generate`). Один macOS-таргет `Tunewave`, macOS 14, `SWIFT_VERSION 6.0`, пакети на tools 6.0 (мова Swift 6, strict concurrency). SwiftUI app lifecycle, Observation (`@MainActor @Observable`). Локальні SPM-пакети `Packages/{Auth,InnerTube,...}`; `InnerTube` залежить від `Auth`, не навпаки. Тести лише в пакетах, на Swift Testing; тестового таргета для `App/` немає. String Catalog немає (англійські літерали, як в 1.2/1.3). Дизайн-системи немає.

## 2. Що вирішили проба й користувач

- Гостьовий `browse FEmusic_home` без `X-Goog-Visitor-Id` дає 200, `responseContext.visitorData` (48 символів, URL-safe + `%`), без `Set-Cookie`. Перше значення береться з першої відповіді (OQ7 знято).
- Сервер щоразу видає новий `visitorData` → зберігаємо останній валідний (E4).
- `visitorData` лише в заголовку `X-Goog-Visitor-Id`, тіло не змінюється (OQ3).
- Тільки пам'ять, скидання на вхід і вихід (OQ4).
- Cancel гостьового входу чистить `WKWebsiteDataStore.default()` без Keychain (OQ1).
- `.keychainUnavailable`: «Try again» + «Continue without signing in» лише на цей запуск, без видалення (OQ2).
- `.signedOut` не перейменовуємо (OQ6), повідомлення «Session expired» — у 2.1 (OQ5).

## 3. Файли

### Створити

| Файл | Тип | Зміст |
|---|---|---|
| `Packages/InnerTube/Sources/InnerTube/GuestVisitor.swift` | service | `final class GuestVisitor: Sendable` — єдине місце `visitorData` на процес. Деталі в D2 |
| `App/GuestModel.swift` | model | `@MainActor @Observable final class GuestModel { enum State { case connecting, connected, failed }; private(set) var state: State = .connecting; @ObservationIgnored private let client = InnerTubeClient(); func connect() async }` (D5) |
| `App/GuestView.swift` | screen | Гостьова заглушка: назва додатка, кнопка «Sign in», рядок статусу, «Retry»; аркуш входу (D6). `#Preview` для трьох станів статусу |
| `Packages/InnerTube/Tests/InnerTubeTests/GuestRequestTests.swift` | test | AC6, AC7, AC8, AC9, E2 (§6) |
| `Packages/Auth/Tests/AuthTests/AuthSessionTests.swift` | test | AC2, AC19, AC20, гард Cancel (§6) |

### Змінити

| Файл | Що і навіщо |
|---|---|
| `Packages/InnerTube/Sources/InnerTube/InnerTubeRequest.swift` | D1. Новий `static func makeGuest(endpoint: String, body: [String: String] = [:], visitorData: String?, locale: Locale) throws(InnerTubeError) -> URLRequest`. Спільна частина `signed` (`Origin`, `X-Origin`, `User-Agent`, `httpShouldHandleCookies = false`) виноситься в `private static func unauthenticated(_ url: URL) -> URLRequest`; `signed` викликає її і додає `Cookie`, `Authorization`, `X-Goog-AuthUser`. Побудова POST-тіла й `Content-Type` виноситься з `make` у `private static func attachPayload(_ request: inout URLRequest, body:locale:) throws(InnerTubeError)`, яку викликають і `make`, і `makeGuest`. Сигнатури `make`/`makeGet` не змінюються |
| `Packages/InnerTube/Sources/InnerTube/InnerTubeClient.swift` | `public func connectAsGuest() async throws` (D3) і `public static func resetGuestVisitor()` → `GuestVisitor.shared.reset()`. Авторизовані `accountMenu`/`accountSwitcher`, `send`, налаштування `URLSession` не змінюються |
| `Packages/Auth/Sources/Auth/KeychainItem.swift` | D7. Внутрішній `protocol KeychainStore: Sendable { func read() throws(KeychainError) -> Data?; func write(_ data: Data) throws(KeychainError); func delete() throws(KeychainError) }`, `KeychainItem: KeychainStore`. Більше нічого |
| `Packages/Auth/Sources/Auth/AuthSession.swift` | D4. `State.isSignedIn`; `continueAsGuest()`; `cancelSignIn() async`; WebKit-очищення з `signOut` виноситься в `private func wipeWebData() async`; `init(keychain: any KeychainStore, defaults:)` |
| `App/TunewaveApp.swift` | `.signedOut` → `GuestView(session:)`; `.keychainUnavailable` → додається `Button("Continue without signing in") { session.continueAsGuest() }`; `.onChange(of: session.state.isSignedIn) { InnerTubeClient.resetGuestVisitor() }` на `Group` (D2) |
| `docs/02-architecture.md` | §5.1: пункт «Headers of a guest request» (`Content-Type`, `Origin`, `X-Origin`, `User-Agent`, `X-Goog-Visitor-Id` якщо відомий; без `Cookie`/`Authorization`/`X-Goog-AuthUser`; `visitorData` з `responseContext.visitorData` гостьової відповіді, лише пам'ять). §6 п.1 переписується: без сесії — гостьовий екран, вхід — аркуш за кнопкою, Cancel чистить WebKit, вихід веде в гостя, `.keychainUnavailable` → Try again / Continue without signing in. Новий пункт §6: «`AuthSession.State.isSignedIn` — єдине джерело рішення "сховати дію / запропонувати вхід"; `.signedOut` означає гостя» + перелік споживачів (2.1, 2.4, 3.2, 4.1, 4.5, 4.6) |
| `docs/06-backlog.md` | Лише примітка безпеки в рядку 3.1: «In guest state the web view store must hold no Google session: verify and wipe on player start (restore() drops an expired Keychain entry without wiping WebKit)». Позначку `[x] 1.4` ставить фаза документації, як в 1.2/1.3 |

### Не змінювати

- `SignInView.swift`: він уже бере `signInURL`, коли `isAddingAccount == false`, а `isSignInActive` уже вважає `.signedOut` активним входом. Гостьовий вхід працює без змін.
- `AccountView.swift`, `AccountModel.swift`: «Sign out» уже веде в `.signedOut`, тобто тепер у гостя (FR6, AC15–AC17).
- `project.yml`, `Package.swift`, `Info.plist`, entitlements, privacy manifest: нових залежностей, ключів і capabilities немає. Мережевий доступ уже є (hardened runtime без sandbox).

## 4. Рішення

- **D1. Гостьовий запит без входу для cookies.** `makeGuest` не має параметра cookies і не бачить `AuthSession`, тож `Cookie`/`Authorization`/`X-Goog-AuthUser` у ньому неможливі структурно (FR8). Авторизований `make` не має параметра `visitorData`, тож `X-Goog-Visitor-Id` там теж структурно неможливий (FR12, AC9). Спільні `unauthenticated` і `attachPayload` гарантують однакові `Origin`/`X-Origin`/`User-Agent`/тіло. `X-Goog-Visitor-Id` ставиться лише для значення, що пройшло `GuestVisitor.validated` (D2), тож ін'єкції CR/LF у заголовок немає.

- **D2. `GuestVisitor` — одне місце на процес.**
  ```swift
  final class GuestVisitor: Sendable {
      static let shared = GuestVisitor()
      struct Snapshot: Sendable { let value: String?; let generation: Int }
      private let lock = OSAllocatedUnfairLock(initialState: Snapshot(value: nil, generation: 0))
      func snapshot() -> Snapshot
      func reset()                                       // value = nil, generation += 1
      func accept(_ raw: String?, generation: Int)       // пише лише валідне значення і лише якщо generation не змінився
      static func validated(_ raw: String?) -> String?   // 1...512 символів, лише ASCII A–Z a–z 0–9 - _ % =
  }
  ```
  - `OSAllocatedUnfairLock` (macOS 13+) замість `Mutex` (macOS 15+, вище за deployment target). Синхронний API, тож скидання можна викликати з `onChange` без `Task`.
  - Валідація — явний ASCII-набір через `unicodeScalars`, не `isLetter`/`isNumber` (ті пропускають кирилицю й не-ASCII цифри). Межа 512: проба дала 48, BA просить «порядку сотень».
  - Невалідне значення ігнорується, попереднє лишається (AC8).
  - **Гонка E2.** Гостьовий запит бере `snapshot()` до відправки і передає його `generation` в `accept`. Скидання збільшує `generation`, тож відповідь, що прийшла після входу чи виходу, мовчки відкидається (запит при цьому не вважається невдалим). AC15 тримається на скиданні при вході (T8) плюс цьому гарду; скидання при виході — друга сітка безпеки.
  - **Хто скидає.** `Auth` не знає про `InnerTube`, тому скидання робить корінь застосунку: `TunewaveApp` слухає `session.state.isSignedIn` і викликає `InnerTubeClient.resetGuestVisitor()` на кожну зміну (вхід T8 і вихід T12). Перехід `.keychainUnavailable` → гість значення `isSignedIn` не змінює й скидання не потребує.
  - Тести створюють власні `GuestVisitor()`, а не `.shared`, щоб паралельні тести не ділили стан.
  - Значення ніде не логується й не показується в UI.

- **D3. `connectAsGuest()` — мінімальний доказ.**
  ```swift
  public func connectAsGuest() async throws {
      let snapshot = GuestVisitor.shared.snapshot()
      let request = try InnerTubeRequest.makeGuest(endpoint: "browse", body: ["browseId": "FEmusic_home"],
                                                   visitorData: snapshot.value, locale: .current)
      let raw = try await send(request)["responseContext"]?["visitorData"]?.string
      guard GuestVisitor.validated(raw) != nil else { throw InnerTubeError.unexpectedResponse }
      GuestVisitor.shared.accept(raw, generation: snapshot.generation)
  }
  ```
  - Вміст сторінки не розбирається (FR13): 2xx + JSON + валідний `visitorData` достатньо. Не-2xx дає `.httpStatus`, не-JSON — `.unexpectedResponse`, редиректи вже відхиляються (E6).
  - Тип результату `Void`: у 2.2 метод стане `home()` з розбором полиць; зараз нічого спекулятивного не повертаємо.
  - **AC10 структурний.** `accept` викликається лише тут; авторизовані `accountMenu`/`accountSwitcher` його не викликають. Перевірка — рев'ю єдиного місця виклику (`grep accept(`), а не мережевий тест.
  - Те, що кожна модель досі створює свій `InnerTubeClient()`, не заважає: стан у `GuestVisitor.shared`, а не в клієнті. Повний DI — 4.1 (R2).

- **D4. `AuthSession`.**
  - `extension AuthSession.State { public var isSignedIn: Bool }` — `true` лише для `.signedIn` (FR14). Правило живе на `State`, тож тестується без Keychain; у коді звертаємося як `session.state.isSignedIn`. Інших `case .signedIn`-перевірок у новому UI немає.
  - `public func continueAsGuest()`: якщо `state` — `.keychainUnavailable`, ставить `.signedOut`. Keychain не чіпає (FR7, AC19). Наступний запуск знову викликає `restore()`.
  - `public func cancelSignIn() async`:
    - `guard case .signedOut = state, !isSigningOut else { return }` — **обов'язковий гард у `AuthSession`, а не у view**. Коли `completeSignIn` ставить `.signedIn`, корінь прибирає `GuestView`, і SwiftUI може викликати setter прив'язки аркуша з `false`. Без гарда це стерло б WebKit одразу після вдалого входу: cookies у Keychain, а у WebKit порожньо, що ламає плеєр 3.1 (docs/02 §6.3).
    - `signInError = nil`. Інакше після T9 + Cancel наступне відкриття аркуша одразу показало б «Couldn't save your session».
    - `isSigningOut = true` на час `await wipeWebData()` (`defer` скидає). Прапорець уже означає «йде очищення сесійних даних»: наявні гарди (`addAccount`) його поважають, а `GuestView` вимикає «Sign in», поки він `true`. Так новий web view не завантажиться у сховище посеред очищення. Новий прапорець не вводимо.
  - `wipeWebData()` = наявні два рядки з `signOut` (`WKWebsiteDataStore.default().removeData(...)`, `URLCache.shared.removeAllCachedResponses()`). `signOut` викликає її в тому ж місці, порядок WebKit → Keychain і коментар лишаються.

- **D5. `GuestModel`** повторює `AccountModel`:
  ```swift
  func connect() async {
      state = .connecting
      let ok = (try? await client.connectAsGuest()) != nil
      guard !Task.isCancelled else { return }
      state = ok ? .connected : .failed
  }
  ```
  `guard !Task.isCancelled` обов'язковий: скасований `URLSession`-запит кидає `URLError(.cancelled)`, а не `CancellationError`. Без гарда старий запит після Retry (рестарт `.task(id:)`) перезаписав би новий стан на `failed`. Помилка гостьового запиту не трактується як «потрібен вхід» (E6). Стан — enum, без `any Error`: UI показує одне повідомлення на всі помилки (FR13).

- **D6. `GuestView`.**
  ```swift
  struct GuestView: View {
      let session: AuthSession
      @State private var model = GuestModel()
      @State private var attempt = 0
      @State private var isSigningIn = false
  }
  ```
  - `VStack(spacing: 12)`: `Text("Tunewave").font(.largeTitle)`, рядок статусу (`Label`/`Text` із `ProgressView` для `.connecting`; «Connected to YouTube Music as a guest»; «Couldn't reach YouTube Music» + `Button("Retry") { attempt += 1 }`), `Button("Sign in") { isSigningIn = true }.disabled(session.isSigningOut)`.
  - `.task(id: attempt) { await model.connect() }` — рівно один запит на появу екрана (AC4), Retry повторює (AC5).
  - Аркуш як в `AccountView`: `.sheet(isPresented: Binding(get: { isSigningIn }, set: { if !$0 { cancel() } }))` з `VStack { SignInView(session:); Button("Cancel") { cancel() }.keyboardShortcut(.cancelAction) }.frame(minWidth: 520, minHeight: 640)`. `cancel()` = `isSigningIn = false; Task { await session.cancelSignIn() }`. Esc і закриття аркуша йдуть через setter (AC13).
  - Успіх входу: `state` стає `.signedIn`, корінь показує `AccountView`, аркуш зникає разом з `GuestView` (AC12). Гард з D4 не дає setter'у стерти WebKit.
  - Повторне натискання «Sign in» лише лишає `isSigningIn = true` — один аркуш (E9).
  - Доступність: текстові кнопки, статус — текст (не лише колір чи іконка); рядок статусу `.accessibilityElement(children: .combine)`. Кольори й шрифти системні.

- **D7. Тестовий шов для Keychain.** AC19 прямо вимагає перевірити, що подвійник Keychain не отримав `delete`, а змусити справжній `KeychainItem.read()` кинути помилку в тесті неможливо. Тому додаємо внутрішній протокол `KeychainStore` з трьома наявними методами; `KeychainItem` його реалізує, публічний `AuthSession.init()` не змінюється. Цей шов також дає протестувати AC2 (`restore` видаляє пошкоджений запис і ставить індекс 0). Подвійник — `final class KeychainSpy: KeychainStore, @unchecked Sendable` лише в тестах.

## 5. Як виконується кожен AC

| AC | Як |
|---|---|
| AC1 | `TunewaveApp`: `.signedOut` → `GuestView`; `SignInView` лише в аркуші за кнопкою |
| AC2 | Наявний `restore()`; тест через `KeychainSpy` з пошкодженими даними: `deleteCount == 1`, `authUserIndex == 0`, `.signedOut` |
| AC3 | Без змін (`.signedIn` → `AccountView`) |
| AC4, AC5 | `GuestModel.connect` + `.task(id: attempt)`; `connectAsGuest` кидає на не-2xx, не-JSON, без валідного `visitorData` |
| AC6 | Тест `makeGuest`: немає `Cookie`/`Authorization`/`X-Goog-AuthUser`, `httpShouldHandleCookies == false`, є `Origin`/`X-Origin`/`User-Agent`; структурно — немає параметра cookies (D1) |
| AC7 | Тест: `GuestVisitor()` без значення → `makeGuest(visitorData: snapshot.value)` без заголовка; після `accept(valid, generation:)` → заголовок дорівнює синтетичному значенню |
| AC8 | Параметризований тест `validated`: `""`, 513 символів, `"a\r\nb"`, `"a b"`, `"Жabc"`, `"١٢٣"` → `nil`; `accept` невалідного не перезаписує попереднє |
| AC9 | Тест: `make(...)` без `X-Goog-Visitor-Id`; наявні тести 1.2/1.3 не змінюються |
| AC10 | Структурно (D3): `accept` викликається лише в `connectAsGuest`; перевірка рев'ю |
| AC11 | `GuestView` відкриває `SignInView`, `isAddingAccount == false` → `signInURL`; є Cancel |
| AC12 | Наявний `completeSignIn` (`authUserIndex = 0` при `!isAddingAccount`); `GuestView` зникає з кореня |
| AC13 | `cancel()` → `cancelSignIn()` (WebKit wipe, `signInError = nil`); Esc через `.cancelAction` і setter аркуша |
| AC14 | Наявний оверлей `SignInView`; стан лишається `.signedOut`, Cancel повертає гостя |
| AC15 | Наявний `signOut` → `.signedOut` → `GuestView`; `onChange` скидає `visitorData`; гард `generation` (E2) |
| AC16, AC17 | Без змін |
| AC18 | `TunewaveApp`: «Couldn't access the saved session», «Try again», «Continue without signing in» |
| AC19 | Тест: `KeychainSpy.read` кидає → `.keychainUnavailable`; `continueAsGuest()` → `.signedOut`, `deleteCount == 0` |
| AC20 | Тест `State.isSignedIn` для трьох case'ів |
| AC21 | Оновлення `docs/02` §5.1 і §6 (§3) |
| AC22 | Нового логування немає; фікстури синтетичні (`"CgtTWU5USEVUSUMxMjM%3D"`, `"test-root"`) |

## 6. Стратегія тестування

Усе в пакетах, Swift Testing, без мережі.

- `GuestRequestTests.swift` (`@testable import InnerTube`):
  - AC6: заголовки й метод `makeGuest`, URL `.../youtubei/v1/browse?prettyPrint=false`, тіло з `browseId` і `context.client` (`WEB_REMIX`, `hl`, `gl`), без `visitorData` у тілі (OQ3).
  - AC7: без значення — без заголовка; після `accept` — з заголовком.
  - AC8: `@Test(arguments:)` для невалідних рядків; валідні `"CgtTWU5USEVUSUMxMjM%3D"`, `"abc_-="`; невалідний `accept` лишає попереднє.
  - E2: `accept` зі старим `generation` після `reset()` нічого не пише; `reset()` очищає значення.
  - AC9: `make(...)` (наявні синтетичні cookies) без `X-Goog-Visitor-Id`.
- `AuthSessionTests.swift` (`@MainActor @Suite`, `@testable import Auth`, `UserDefaults(suiteName: UUID().uuidString)` з видаленням):
  - AC20: `State.isSignedIn` для `.signedIn(cookies: [])`, `.signedOut`, `.keychainUnavailable(KeychainError(status: errSecInteractionNotAllowed))`.
  - AC19: `read` кидає → `continueAsGuest()` → `.signedOut`, `deleteCount == 0`.
  - AC2: пошкоджені дані (`Data("x".utf8)`) → `deleteCount == 1`, `authUserIndex == 0`.
  - Гард Cancel: сесія з повним синтетичним набором cookies (`SessionCookies.encode` як у `SessionCookiesTests`) → `.signedIn`; `await cancelSignIn()` лишає `.signedIn`. Шлях з реальним очищенням WebKit у тестах не запускається.
- `GuestModel`/`GuestView` — без unit-тестів (тестового таргета для `App/` немає, логіка — три рядки поверх `connectAsGuest`); `#Preview` для трьох станів і ручна перевірка.
- Команда: `test_command` з контексту (`xcodegen generate`, `xcodebuild ... platform=macOS,arch=arm64 build`, `swift test` у кожному пакеті).
- Ручна перевірка (⛔, користувач): чистий запуск → «Connected» → Sign in → акаунт → Sign out → «Connected» → Sign in → Cancel → гість; Esc у аркуші; «Continue without signing in» (якщо вдасться відтворити заблокований Keychain).

## 7. Ризики

- **R-a. Setter аркуша при успішному вході.** Закрито гардом `state == .signedOut` у `cancelSignIn` (D4) і тестом. `GuestView` зникає саме через зміну `state`, тож будь-який виклик setter'а після цього потрапляє на гард. Ручна перевірка: після входу акаунт-екран завантажується, а повторний запуск лишається `.signedIn`.
- **R-b. Скидання через `onChange` у корені.** Залежить від того, що вікно існує під час входу/виходу (так і є: обидва — дії у вікні). Гард `generation` прикриває запізнілі відповіді.
- **R-c. Залишки WebKit (R1 з BA).** T3 (`restore()` видаляє прострочений запис без очищення WebKit) не виправляється в 1.4; лише примітка в 3.1.
- **R-d. Застарілий `clientVersion` (E12) і зміна формату відповіді.** Гостьовий статус покаже «Couldn't reach…», якщо `responseContext.visitorData` зникне; розв'язується в 2.1.
- **R-e. `isSigningOut` як прапорець очищення при Cancel.** Свідоме перевикористання; якщо в 4.1 знадобиться розрізняти «виходить» і «скасовує вхід», прапорець перейменовується тоді.

## 8. Потребує рішення користувача

1. **Тестовий шов `KeychainStore` (D7).** Додає внутрішній протокол заради AC19 і AC2. Альтернатива — не додавати, а AC19 перевіряти лише рев'ю (`continueAsGuest` не звертається до Keychain) і вручну; тоді це відхилення від AC19. Рекомендація: шов додати.
2. **Межа довжини `visitorData` — 512.** Проба дала 48; якщо потрібна жорсткіша межа (наприклад, 128), скажіть.

## Затвердження (користувач, 2026-11-18)

План затверджено. Обидва рішення з розділу про відкриті питання прийнято за рекомендацією:
- внутрішній шов `KeychainStore` додається, і `KeychainItem` його реалізує;
- ліміт довжини `visitorData` становить 512 символів.
