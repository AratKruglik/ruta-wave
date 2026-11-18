# План реалізації: список акаунтів і перемикання (backlog 1.3)

Прохід: PLAN. Код ще не змінено. Джерела: `_brief.md`, `00-discovery.md`, `01-business-analysis.md` (з розділом «Результати discovery і відповіді», він має пріоритет), `innertube-core/02-development-plan.md` (D5, D6).

## 1. Форма проєкту

XcodeGen (`project.yml`, `xcodegen generate`), один macOS-таргет `Tunewave` (macOS 14), Swift 6 (tools 6.0 у пакетах), SwiftUI app lifecycle, Observation (`@MainActor @Observable`), локальні SPM-пакети `Packages/{Auth,InnerTube,...}`, тести на Swift Testing лише в пакетах (тестового таргета для `App/` немає), String Catalog немає (рядки англійською літералами, як у 1.2), дизайн-системи немає (системні кольори й шрифти).

## 2. Рішення discovery, яких дотримується план

- Список дає лише `GET https://music.youtube.com/getAccountSwitcherEndpoint`, з тими самими заголовками, що й `account_menu`, без тіла. Відповідь може починатися з `)]}'`.
- Fallback C3 (перебір `account_menu`) **не робимо** (рішення користувача). Хост `www.youtube.com` **не додаємо**.
- Перемикання — лише зміна `X-Goog-AuthUser` (gate AC2 пройдено). Індекс поза межами дає для `account_menu` HTTP 200 без `activeAccountHeaderRenderer`, а отже `AccountInfo` кидає `.unexpectedResponse`.

## 3. Файли

### Створити

| Файл | Тип | Зміст |
|---|---|---|
| `Packages/InnerTube/Sources/InnerTube/AccountListItem.swift` | model + parser | `public struct AccountListItem: Sendable, Equatable, Identifiable { public let name: String; public let byline: String?; public let avatarURL: URL?; public let authUserIndex: Int; public let isSelected: Bool; public var id: Int { authUserIndex } }` (+ public memberwise `init` для превʼю). `static func list(accountSwitcher json: JSONValue) -> [AccountListItem]`. `public static func fallbackIndex(current: Int, accounts: [AccountListItem]?) -> Int`. Деталі в D3 і D4 |
| `Packages/Auth/Sources/Auth/GoogleSupportedDomains.swift` | data | `enum GoogleSupportedDomains { static let all: Set<String> = [...] }`: 187 записів без початкової крапки (додаток A). Однорядковий коментар з URL джерела й датою знімка 2026-11-18 |
| `Packages/InnerTube/Tests/InnerTubeTests/AccountListTests.swift` | test | AC3, AC4, AC5, AC7 (див. §6) |

### Змінити

| Файл | Що і навіщо |
|---|---|
| `Packages/InnerTube/Sources/InnerTube/InnerTubeRequest.swift` | Спільні заголовки авторизації переносимо в `private static func signed(_ url: URL, cookies:authUserIndex:now:) throws(InnerTubeError) -> URLRequest`: пошук кореневого `SAPISID`, живі music-cookies, `Cookie`, `Authorization: SAPISIDHASH` (origin `https://music.youtube.com`), `X-Goog-AuthUser`, `Origin`, `X-Origin`, `User-Agent`, `httpShouldHandleCookies = false`. `make(endpoint:body:cookies:authUserIndex:now:locale:)` лишає сигнатуру й поведінку: `signed` + `POST` + тіло + `Content-Type`. Новий `static func makeGet(path: String, cookies:authUserIndex:now:) throws(InnerTubeError) -> URLRequest`: URL `origin + path`, метод `GET`, без тіла, без `Content-Type`, без `prettyPrint` |
| `Packages/InnerTube/Sources/InnerTube/JSONValue.swift` | `init(response data: Data) throws(InnerTubeError)`: якщо дані починаються з байтів `)]}'`, відкидає ці 4 байти (решта з `\n` декодується, перевірено `JSONDecoder` локально), далі `JSONDecoder().decode`, будь-яка помилка → `.unexpectedResponse` |
| `Packages/InnerTube/Sources/InnerTube/InnerTubeClient.swift` | `post(...)` ділиться на побудову запиту й спільний `private func send(_ request: URLRequest) async throws -> JSONValue` (перевірка статусу без змін, декодування через `JSONValue(response:)`). Новий `public func accountSwitcher(cookies: [HTTPCookie], authUserIndex: Int) async throws -> [AccountListItem]` = `AccountListItem.list(accountSwitcher: send(InnerTubeRequest.makeGet(path: "/getAccountSwitcherEndpoint", ...)))`. `RejectRedirects` діє і для GET |
| `Packages/Auth/Sources/Auth/SignInRules.swift` | `isRegionalAccountsHost` (regex) видаляється. Замість нього `private static func isRegionalSetSID(_ url: URL, host: String) -> Bool`: `host.hasPrefix("accounts.")`, `GoogleSupportedDomains.all.contains(String(host.dropFirst(9)))` **і** `url.path(percentEncoded: true) == "/accounts/SetSID"`. `isAllowedMainFrameNavigation`: `allowedHosts.contains(host) \|\| isRegionalSetSID(url, host: host)`. `allowedHosts` без змін |
| `Packages/Auth/Tests/AuthTests/SignInRulesTests.swift` | AC10 (див. §6) |
| `App/AccountModel.swift` | `State`: `.loading`, `.loaded(AccountInfo, accounts: [AccountListItem]?)`, `.failed`. `nil` означає збій списку. Новий порядок `load` (D5) |
| `App/AccountView.swift` | Аватар виноситься в `private struct AccountAvatar: View { let url: URL?; let size: CGFloat }`, його використовують і `AccountHeader`, і рядки. Під `AccountHeader`: при `accounts == nil` текст «Couldn't load other accounts» і `Button("Retry") { attempt += 1 }`. При `accounts.count > 1` йде `ForEach(accounts)` з `AccountRow` (D6). Превʼю `AccountRow` на синтетичних даних |
| `docs/02-architecture.md` | §5.1: `X-Goog-AuthUser` = вибраний `authUserIndex` (не завжди 0), окремий пункт про `GET /getAccountSwitcherEndpoint` (ті самі заголовки, без тіла, необовʼязковий XSSI-префікс). §5.2: рядок `GET /getAccountSwitcherEndpoint` (список Google-акаунтів сесії, `authuser` з `signinUrl`) |
| `docs/05-risks-and-scope.md` §4 #2 | Замінити «list moved to 1.3» на фактичне рішення: список з `getAccountSwitcherEndpoint`, перемикання через `X-Goog-AuthUser`, `accounts_list` не працює, brand-акаунти поза скоупом |

### Не змінювати

- `AuthSession`: FR9 уже виконано в 1.2 (`completeSignIn` не чіпає індекс при `isAddingAccount`, а `onChange(of: isAddingAccount)` у `AccountView` перечитує екран і список).
- `project.yml`, `Package.swift` обох пакетів, `Info.plist`, entitlements: нових файлів у `App/` немає, нові файли пакетів підхоплюються автоматично, нових залежностей немає.
- `TunewaveApp.swift`.
- `docs/06-backlog.md`: позначку «1.3 виконано» ставить фаза документації, як і в 1.2.

## 4. Рішення

- **D1. GET — окремий білдер поверх спільного підписувача.** Мінімальна зміна: POST-контракт і його тести не змінюються, а GET отримує ті самі заголовки з одного місця, тож розійтися вони не можуть. Параметр `method` у `make` не додаємо, бо тіло й `Content-Type` для GET безглузді.
- **D2. XSSI знімається в одному місці (`JSONValue(response:)`)** для всіх відповідей. Для JSON від `youtubei` префікса немає, тож поведінка `account_menu` не змінюється. Інший префікс або сміття дає `.unexpectedResponse`.
- **D3. Парсер (D5 з 1.2 з уточненнями discovery).** Точних шляхів discovery не зафіксувала, тому всі пошуки рекурсивні. Додаємо в `AccountListItem.swift` один `fileprivate` хелпер `JSONValue.values(forKey:) -> [JSONValue]` (рекурсивний обхід обʼєктів і масивів). Для кожного `accountItem`:
  - `name` = `text(accountName)`, якщо немає, елемент відкидається;
  - `byline` = `text(accountByline) ?? text(channelHandle)` (відповідь на питання 7);
  - `avatarURL` = `lastThumbnailURL(accountPhoto)` (наявний allowlist хостів);
  - `isSelected` = `isSelected?.bool ?? false`;
  - `signinUrl` — перший рядок `values(forKey: "signinUrl")`, розбирається `URLComponents(string:)` (відносний шлях працює, перевірено). Індекс = query-параметр `authuser` → `Int`, `>= 0`, інакше елемент відкидається;
  - brand = є ключ `pageIdToken` будь-де в елементі **або** у `signinUrl` є параметр `pageid`. Brand відкидається **до** дедуплікації, бо в discovery brand має `authuser=0`, як і особистий акаунт 0;
  - дедуплікація за індексом (лишається перший), сортування за зростанням індексу;
  - немає жодного `accountItem` → `[]` без помилки.
- **D4. Активний акаунт і FR15 — чиста функція в InnerTube**, бо тестів для `App/` немає, а AC7 вимагає `swift test`. `fallbackIndex(current:accounts:) -> Int`:
  - `accounts == nil` (збій) або `[]` → `current`;
  - `current < 0` → 0;
  - `current` є серед `authUserIndex` → `current`;
  - інакше → 0.
  Повторного скидання в межах одного завантаження немає: після скидання наступне завантаження йде з 0, а для `current == 0` функція повертає 0, тобто без змін. «Активний» у UI визначається як `item.authUserIndex == session.authUserIndex` (FR4). `isSelected` парситься лише заради AC3 і в логіці не бере участі. Вибраний елемент без токена `authuser` парсер відкидає (D3), тому FR4 (а) і (б) виконуються автоматично: індекс 7 при списку [0, 1] → 0 незалежно від того, що Google позначив вибраним.
- **D5. `AccountModel.load`: паралельно, але FR15 вирішує список.** Обидва запити стартують одночасно (як у 1.2), список чекаємо першим:
  ```swift
  async let list = try? client.accountSwitcher(cookies: cookies, authUserIndex: index)
  async let menu = try? client.accountMenu(cookies: cookies, authUserIndex: index)
  let accounts = await list
  guard !Task.isCancelled else { return }
  let resolved = AccountListItem.fallbackIndex(current: index, accounts: accounts)
  if resolved != index { session.authUserIndex = resolved; return }  // menu скасовується неявно, .task(id:) перезапускає load
  let info = await menu
  guard !Task.isCancelled else { return }
  state = info.map { .loaded($0, accounts: accounts) } ?? .failed
  ```
  Причина: із застарілим індексом `account_menu` кидає помилку, тож FR15 має спрацювати до неї, інакше AC14 (5) застрягне на «Couldn't load your account». Збій меню сам по собі скидання не викликає (FR7), скидання вирішує лише успішний непорожній список. `try?` свідомий: збій списку не фатальний і показується в UI (FR8), збій меню дає `.failed`. Нічого не логуємо. Перегони й вихід закриває `.task(id: ReloadKey)` + `Task.isCancelled`, як у 1.2 D6.
- **D6. Рядки — `Button`, а не `List(selection:)`.** `private struct AccountRow: View { let item: AccountListItem; let isActive: Bool; let isDisabled: Bool; let onSelect: () -> Void }`, сесію рядок не знає (превʼю не створює `AuthSession`, який читає справжній Keychain). `AccountView` передає `isActive: item.authUserIndex == session.authUserIndex`, `isDisabled: session.isSigningOut`, `onSelect: { session.authUserIndex = item.authUserIndex }`. Тіло: `Button(action: onSelect) { label: { HStack { AccountAvatar(url:, size: 28); VStack(alignment: .leading) { Text(name); if let byline { Text(byline).foregroundStyle(.secondary) } }; Spacer(); if isActive { Image(systemName: "checkmark").accessibilityHidden(true) } } }`, `.buttonStyle(.plain)`, `.disabled(isActive || isDisabled)`, `.accessibilityElement(children: .combine)` і `.accessibilityAddTraits(isActive ? .isSelected : [])`. Причини: `List(selection:)` перемикає акаунт на кожне натискання стрілки (серія мережевих перезавантажень) і потребує фіксованої висоти всередині `VStack`. Кнопки доступні з клавіатури через Tab, коли в macOS увімкнено Keyboard navigation (стандартна поведінка платформи), і через VoiceOver. Список ховається, коли акаунт один (FR5).
- **D7. Регіональні хости.** Точне порівняння шляху з `path(percentEncoded: true)`: застарілий `url.path` відкидає кінцевий `/` і декодує `%53` (перевірено локально), а BA вимагає точного збігу. Query довільний. Знімок лише вбудований, мережі немає.
- **D8. Логування.** Нового логування немає. Debug-код зондів у PR не потрапляє (відповідь 5).

## 5. Покриття AC

| AC | Як | Перевірка |
|---|---|---|
| AC1, AC2 | `00-discovery.md` | вже виконано |
| AC3 | D3 | `AccountListTests`: синтетична фікстура (два акаунти 0 вибраний і 1, brand з `pageIdToken` і `authuser=0`, brand лише з `pageid` у `signinUrl`, дублікат індексу 1, `authuser=-1`, елемент без імені, аватар `https://example.com`). Очікування: рівно `[0, 1]`, правильні `isSelected`, byline (email-подібний синтетичний `test0@example.com` і fallback на handle), аватар з недозволеного хоста дає `nil` |
| AC4 | D3 + D4 | вибраний елемент без `signinUrl` відкидається; `fallbackIndex(current: 7, accounts: [1])` → 0 |
| AC5 | D2, D3 | список без `accountItem` → `[]`; `JSONValue(response:)` з `)]}'\n{...}`, без префікса, з «сміттям» → `.unexpectedResponse`. Не-2xx: спільний `send` з наявною перевіркою статусу, лише рев'ю (URLProtocol-стабу в тестах немає, вводити його не будемо) |
| AC6 | D1 | `InnerTubeRequestTests`: `makeGet` → `GET`, URL `https://music.youtube.com/getAccountSwitcherEndpoint`, `httpBody == nil`, немає `Content-Type`, `Authorization`/`X-Goog-AuthUser`/`Origin`/`X-Origin` як у POST, `Cookie` без чужих доменів. Частина про C3 знята |
| AC7 | D4 | параметризований тест `fallbackIndex`: у списку → без змін; поза непорожнім → 0; поза списком при вибраному без токена → 0; `[]` → без змін; `nil` → без змін; `current 0` поза списком → 0 (без циклу); від'ємний → 0 |
| AC8 | D5, D6 | рев'ю + вручну |
| AC9 | без змін коду (1.2) | вручну |
| AC10 | D7 | `SignInRulesTests.allowlist`: дозволено `accounts.google.{com.ua,de,co.uk,cat}/accounts/SetSID` і `.../accounts/SetSID?continue=x`; відхилено `accounts.google.de/ServiceLogin`, `accounts.google.com.ua/`, `accounts.google.de/accounts/SetSID/`, `accounts.google.xyz/accounts/SetSID`, lookalike-хости **зі шляхом** `/accounts/SetSID` (`accounts.google.com.evil.ua`, `evil.accounts.google.com.ua`, `accounts.google.com.ua.evil.com`), `http://accounts.google.de/accounts/SetSID`. Наявні точні хости лишаються. `.cat` доводить, що працює список, а не regex (regex пропускав лише 2-літерні TLD) |
| AC11 | D7 | рев'ю + `grep -n "wholeMatch\|isRegionalAccountsHost" Packages` порожній |
| AC12 | D8 | рев'ю + `grep -rn "print(\|Logger\|os_log" Packages/*/Sources App` |
| AC13 | — | `test_command` з контексту |
| AC14 | — | вручну користувачем, результат у `03-qa.md` |
| AC15 | §3 docs | рев'ю |

## 6. Стратегія тестів

- Лише Swift Testing у наявних тестових таргетах пакетів, синтетичні фікстури як raw-string літерали у файлі тесту (як `AccountParsingTests`). Імена `Test User 0/1`, `@testhandle`, `test0@example.com`, аватари `https://yt3.ggpht.com/test-*`.
- Нові тести: `AccountListTests` (AC3, AC4, AC5-парсер, AC7), `JSONValueTests` +1 (XSSI), `InnerTubeRequestTests` +1 (GET), `SignInRulesTests` (AC10). Наявні тести POST не змінюються.
- Мережа й Keychain у тестах не використовуються. Модель і UI перевіряються вручну (AC8, AC9, AC14).

## 7. Порядок реалізації

1. `GoogleSupportedDomains` + `SignInRules` + тести (TDD).
2. `JSONValue(response:)` + тест.
3. `InnerTubeRequest` (`signed`, `makeGet`) + тест.
4. `AccountListItem` (парсер, `fallbackIndex`) + `AccountListTests`.
5. `InnerTubeClient` (`send`, `accountSwitcher`).
6. `AccountModel`, `AccountView`.
7. docs/02, docs/05.
8. `test_command`.

## 8. Відхилення від BA

- XSSI-префікс **необовʼязковий** (discovery). Рядок BA «відповідь без префікса нерозбірна» не виконуємо.
- C3 і його частини FR3/AC6 знято (рішення користувача). `www.youtube.com` не додаємо.
- FR7 трактується так: скидання вирішує лише успішний непорожній список. Збій `account_menu` сам по собі його не викликає, але й не блокує, якщо список показав відсутність індексу (інакше AC14 (5) неможливий).

## 9. Ризики

- **Поведінка switcher зі застарілим індексом (наприклад, 7) не перевірялась.** Якщо він поверне помилку або порожньо, FR15 не спрацює і AC14 (5) застрягне на «Couldn't load your account». Можливе пом'якшення (не погоджено, див. §10): слати запит списку з `authUserIndex: 0`, бо `authuser` у `signinUrl` наскрізні для сесії, а активність визначаємо за індексом, не за `isSelected`. Перевіряється в AC14 (5).
- Рекурсивний парсер може підхопити «чужі» `accountItem`, якщо Google додасть їх в інший розділ. Brand/дедуп це обмежують, а ризик #2 [K] лишається.
- Акаунт, що потребує повторного входу: його `account_menu`, ймовірно, дасть `.failed` з Retry. Вічного завантаження немає, але явного стану теж (2.1).
- Знімок доменів застаріває, тож для нового ccTLD вхід через SetSID буде скасовано. Знімок оновлюють вручну.
- Якщо список прийшов, а меню вже впало, запит меню все одно витрачено. Це дешево.

## 10. Потрібне від користувача

- Погодити D6 (кнопки замість `List(selection:)`).
- Якщо AC14 (5) не пройде через поведінку switcher зі застарілим індексом: чи слати запит списку завжди з `X-Goog-AuthUser: 0` (відхилення від FR2)?
- Погодити, що відмітку в `docs/06-backlog.md` ставить фаза документації.
- AC14 вручну, особливо пункт (5), який перевіряє ризик з §9.

## Додаток A. Знімок Google supported domains

Джерело: `https://www.google.com/supported_domains`, завантажено 2026-11-18, HTTP 200, 187 записів. У коді записи йдуть без початкової крапки. Містить `google.cat` і `google.com`.

```
"google.com", "google.ad", "google.ae", "google.com.af", "google.com.ag", "google.al", 
"google.am", "google.co.ao", "google.com.ar", "google.as", "google.at", "google.com.au", 
"google.az", "google.ba", "google.com.bd", "google.be", "google.bf", "google.bg", 
"google.com.bh", "google.bi", "google.bj", "google.com.bn", "google.com.bo", "google.com.br", 
"google.bs", "google.bt", "google.co.bw", "google.by", "google.com.bz", "google.ca", 
"google.cd", "google.cf", "google.cg", "google.ch", "google.ci", "google.co.ck", 
"google.cl", "google.cm", "google.cn", "google.com.co", "google.co.cr", "google.com.cu", 
"google.cv", "google.com.cy", "google.cz", "google.de", "google.dj", "google.dk", 
"google.dm", "google.com.do", "google.dz", "google.com.ec", "google.ee", "google.com.eg", 
"google.es", "google.com.et", "google.fi", "google.com.fj", "google.fm", "google.fr", 
"google.ga", "google.ge", "google.gg", "google.com.gh", "google.com.gi", "google.gl", 
"google.gm", "google.gr", "google.com.gt", "google.gy", "google.com.hk", "google.hn", 
"google.hr", "google.ht", "google.hu", "google.co.id", "google.ie", "google.co.il", 
"google.im", "google.co.in", "google.iq", "google.is", "google.it", "google.je", 
"google.com.jm", "google.jo", "google.co.jp", "google.co.ke", "google.com.kh", "google.ki", 
"google.kg", "google.co.kr", "google.com.kw", "google.kz", "google.la", "google.com.lb", 
"google.li", "google.lk", "google.co.ls", "google.lt", "google.lu", "google.lv", 
"google.com.ly", "google.co.ma", "google.md", "google.me", "google.mg", "google.mk", 
"google.ml", "google.com.mm", "google.mn", "google.com.mt", "google.mu", "google.mv", 
"google.mw", "google.com.mx", "google.com.my", "google.co.mz", "google.com.na", "google.com.ng", 
"google.com.ni", "google.ne", "google.nl", "google.no", "google.com.np", "google.nr", 
"google.nu", "google.co.nz", "google.com.om", "google.com.pa", "google.com.pe", "google.com.pg", 
"google.com.ph", "google.com.pk", "google.pl", "google.pn", "google.com.pr", "google.ps", 
"google.pt", "google.com.py", "google.com.qa", "google.ro", "google.ru", "google.rw", 
"google.com.sa", "google.com.sb", "google.sc", "google.se", "google.com.sg", "google.sh", 
"google.si", "google.sk", "google.com.sl", "google.sn", "google.so", "google.sm", 
"google.sr", "google.st", "google.com.sv", "google.td", "google.tg", "google.co.th", 
"google.com.tj", "google.tl", "google.tm", "google.tn", "google.to", "google.com.tr", 
"google.tt", "google.com.tw", "google.co.tz", "google.com.ua", "google.co.ug", "google.co.uk", 
"google.com.uy", "google.co.uz", "google.com.vc", "google.co.ve", "google.co.vi", "google.com.vn", 
"google.vu", "google.ws", "google.rs", "google.co.za", "google.co.zm", "google.co.zw", 
"google.cat", 
```

## Затвердження (користувач, 2026-11-18)

План затверджено з однією зміною. Запит `getAccountSwitcherEndpoint` **завжди** надсилається з `X-Goog-AuthUser: 0`. Активний рядок визначається за `AuthSession.authUserIndex`, а не за `isSelected` з відповіді. Пункт про застарілий індекс у §9/§10 тим самим закрито. D6 (кнопки) погоджено. Відмітку в беклозі ставить фаза документації.
