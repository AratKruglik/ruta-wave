# Огляд безпеки: список акаунтів і перемикання (backlog 1.3)

## Підсумок
- Critical: 0 (у fix pass нічого)
- High: 0 (у fix pass нічого)
- Medium: 1. Рекомендація, але **варто включити у fix pass**: виправлення займає кілька рядків, як M1 в 1.2. Вада з'явилася саме в цій зміні.
- Поза скоупом: Low 2, Info 9

Прямого шляху експлуатації немає. Знахідку автоматичного рев'ю 1.2 (regex `accounts.google.(com.|co.)?<cc>` пропускав хости, які можуть не належати Google) **закрито**:
- regex видалено;
- регіональні хости приймаються лише зі знімка `supported_domains`;
- на них дозволено тільки точний шлях `/accounts/SetSID`.

Знімок я звірив із живим списком 2026-11-18: 187 записів, ті самі й у тому самому порядку.

Новий запит `GET /getAccountSwitcherEndpoint` іде тим самим захищеним транспортом, що й `account_menu`:
- хост задано константою;
- cookies лише `youtube.com`;
- редиректи відхиляються;
- сесія ефемерна;
- нічого не логується.

`authuser` із відповіді потрапляє в заголовок лише як `Int ≥ 0`, тож ін'єкція неможлива. Підроблена чи дивна відповідь сама може перемкнути користувача **тільки на акаунт 0** (через FR15). На ненульовий індекс він переходить лише після власного кліку.

Головна знахідка (M1) стосується не безпеки, а тихого збою, який з'явився саме в цій зміні. Якщо `account_menu` для вибраного індексу стабільно падає, стан `.failed` ховає список, і повернутися на робочий акаунт можна лише через «Sign out» усіх акаунтів.

## Що перевірено і виявилося чистим

| Перевірка | Результат |
|---|---|
| Allowlist main frame: структура (`SignInRules.swift:22-32`) | Спершу схема `https`, потім хост у нижньому регістрі. Хост має або точно збігатися з `allowedHosts` (`:7-13`), або бути `accounts.` + запис зі знімка, і тоді шлях має бути **точно** `/accounts/SetSID` (`:28-32`). Суфіксного чи шаблонного збігу немає. `evil.accounts.google.com.ua` дає після `dropFirst` рядок `accounts.google.com.ua`, а `accounts.google.com.ua.evil.com` дає `google.com.ua.evil.com`. Жодного з них у знімку немає. `accounts.accounts.google.de` теж відхиляється |
| Нормалізація URL | Делегат отримує `navigationAction.request.url` (`SignInView.swift:76-80`), і цей URL WebKit уже канонізував за WHATWG: схема й хост у нижньому регістрі, IDN переведено в punycode (UTS46), percent-encoding у хості декодовано, dot-сегменти (зокрема `%2e%2e`) у шляху розгорнуто, `\` замінено на `/`. Отже, перевіряється саме той хост і шлях, куди піде запит, і розбіжності парсерів немає. Окремі трюки: (1) **userinfo** `https://evil@accounts.google.de/…` має хост `accounts.google.de`, а `https://accounts.google.de@evil.com/` має хост `evil.com`, тобто відмова; (2) **кінцева крапка** `accounts.google.de.` не входить у множину, тож відмова (fail-closed); (3) **IDN / гомогліфи**: punycode-хост не збігається з ASCII-записами. Kelvin `K` (U+212A) UTS46 перетворює на `k` ще до делегата, тобто на справжній домен Google; (4) **percent-encoding у шляху**: `/accounts/%53etSID` порівнюється з `path(percentEncoded: true)` дослівно, тож відмова; (5) **регістр шляху**, `//`, кінцевий `/`, додатковий сегмент дають відмову (тести `SignInRulesTests.swift:50-53`); (6) **порт** не обмежено: `:8443` дозволено свідомо (`:54`), див. Info 1 |
| Кожен хоп редиректу | Серверні редиректи main frame теж проходять `decidePolicyFor`. Емпірично це доводить QA 1.2: регіональний SetSID і `gds.google.com` скасовувались саме на редиректі (WebKit 102). Тому відкритий редирект на дозволеному хості (`www.google.com/url?q=…`, `continue=` у SetSID) не виводить main frame за allowlist |
| Знімок доменів (`GoogleSupportedDomains.swift:2-36`) | 187 записів, усі мають вигляд `google.<tld>`. Звірено з `https://www.google.com/supported_domains` (WebFetch 2026-11-18): ті самі записи в тому самому порядку. WebFetch пропускає сторінку через модель-підсумовувач, тож друге незалежне джерело — завантаження розробника (план, додаток A, HTTP 200, 187 записів). Кожен запис — зареєстрований Google домен, під яким Google обслуговує пошук, тож `accounts.<запис>` контролює Google. Дублікати в літералі `Set` не призводять до падіння (`init(arrayLiteral:)` їх пропускає) |
| Чи виправдано знімок і `gds.google.com` | Знімок потрібен, бо SetSID веде на регіональний домен країни користувача, а країна наперед невідома. Широту знімка компенсує обмеження одним шляхом. `gds.google.com` — точний хост Google, доданий у 1.2 за фактом QA (редирект після пароля в «Add account», `innertube-core/03-qa.md:39`). У цій зміні він не змінювався. Обмеження шляху для нього див. Info 3 |
| Запит `GET /getAccountSwitcherEndpoint` (`InnerTubeRequest.swift:39-48`, `InnerTubeClient.swift:35-39`) | URL `origin + path`, а `path` — рядковий літерал, тож хост не контролюється ззовні. Заголовки беруться зі спільного `signed` (`:50-72`), тому з POST вони розійтися не можуть: `Cookie` лише з `SignInRules.musicCookies` (домени `youtube.com` / `music.youtube.com`) і без прострочених, `SAPISIDHASH` від кореневої `SAPISID` з origin `https://music.youtube.com`, а також `Origin`, `X-Origin`, `httpShouldHandleCookies = false`. Тіла немає, `Content-Type` немає. Тести: `InnerTubeRequestTests.swift:77-103` |
| `X-Goog-AuthUser` | Значення `"\(authUserIndex)"` береться від `Int` (`InnerTubeRequest.swift:65`), тож CR/LF у ньому неможливі. Для списку це завжди `0` (`AccountModel.swift:23`), як затвердив користувач. Активний рядок визначається за `session.authUserIndex`, а не за `isSelected` (`AccountView.swift:27`). Тому застарілий індекс не ламає запит списку, а `isSelected` з відповіді на логіку не впливає |
| Редиректи й сесія | `RejectRedirects` (`InnerTubeClient.swift:9-18`) діє на рівні сесії, отже і для GET. 3xx стає `.httpStatus` (`:61`), а `Cookie` і `Authorization` на інший хост не йдуть. Сесія `ephemeral`, `httpCookieStorage = nil`, `urlCache = nil` (`:24-28`), тож авторизовану відповідь не буде закешовано на диск. Runtime-перевірки досі немає (Info 7 нижче, Info 1 з 1.2) |
| XSSI і розбір JSON (`JSONValue.swift:28-37`) | Відкидається рівно 4-байтовий префікс `)]}'`, а `\n` після нього `JSONDecoder` сприймає як пробільний символ. Відповідь без префікса розбирається як раніше. Будь-яке інше сміття, інший префікс (наприклад `)]}',`) чи HTML-сторінка згоди з кодом 200 дають `.unexpectedResponse` і далі «Couldn't load other accounts». Отже, система не падає, а лише стає менш доступною (fail-safe). Декодування `JSONValue` лінійне, повторних спроб немає. Тести: `JSONValueTests.swift:35-43` |
| Довіра до парсера (`AccountListItem.swift:35-52`) | `signinUrl` **ніколи не завантажується**: з нього береться лише `authuser`. Тому абсолютний URL на чужий хост у відповіді не дає ні SSRF, ні відкритого редиректу. `Int.init` приймає лише ASCII-цифри (з `+`/`-`), а `authUser >= 0` відсікає від'ємні значення (закрито Low 3 з 1.2). `URLComponents` декодує `%31`, тобто `1`, і це коректно. Brand визначається так: є `pageIdToken` будь-де в елементі **або** параметр `pageid`. Brand відкидається **до** дедуплікації (`:42-44`, `:24`), тож brand з `authuser=0` не витіснить особистий акаунт 0. Brand з X-Goog-AuthUser без `X-Goog-PageId` однаково означав би акаунт 0, тому відкидати його правильно. Дедуплікація за індексом дає унікальні `id` у `ForEach` (закрито Info 5 з 1.2) |
| Аватари (`AccountInfo.swift:29-37`) | Повторно використовується `lastThumbnailURL`: лише `https` і хост `ggpht.com`, `googleusercontent.com` чи `ytimg.com` або їхній піддомен. `https://yt3.ggpht.com@evil.com/` має хост `evil.com`, тож відмова. `yt3.ggpht.com.` не має суфікса `.ggpht.com` і теж відхиляється. Тести: `AccountListTests.swift:93-103`. `AsyncImage` вантажить через `URLSession.shared`, який не має спільних cookies із `WKWebsiteDataStore`. Кеш очищається в `signOut()` (`AuthSession.swift:80`) |
| Чи може відповідь «перекинути» на інший акаунт (`AccountModel.swift:18-35`, `AccountListItem.swift:29-33`) | `fallbackIndex` повертає або `current`, або `0`, тож **сама відповідь не може встановити ненульовий індекс**. Ненульовий індекс записує лише клік користувача (`AccountView.swift:29`). Підробленим чи «дивним» списком, з якого зник поточний індекс, можна лише повернути користувача на основний акаунт 0, і це задокументована поведінка FR7. Циклу немає: після скидання маємо `index == 0`, а `fallbackIndex(0, …)` повертає 0. Порожній список або збій скидання не викликають. Неоднозначна мітка рядка описана в Low 1 |
| Перегони | Модель `@MainActor`, і кожен запис у `state` / `session.authUserIndex` іде після `await` і перевірки `Task.isCancelled` (`:26, :33`), без точки призупинення між ними. Під час завантаження `state == .loading`, рядків немає, тож клікнути інший рядок посеред завантаження неможливо. Застаріла задача ще до скасування може записати хіба що `0`, що збігається з `signOut()` (`AuthSession.swift:87`). Після виходу `.signedIn` зникає, задача скасовується. Рядки вимкнено під час `isSigningOut` (`AccountView.swift:28`, закрито Info 6 з 1.2). Коли `return` іде після скидання, `async let menu` неявно скасовується й очікується |
| Рендеринг | `Text(item.name)` і `Text(byline)` отримують `String`, тож текст виводиться дослівно, без Markdown чи посилань. Byline часто містить email: він лише на екрані, нікуди не пишеться |
| Логування (AC12) | `grep` за `print(`, `Logger`, `os_log`, `NSLog`, `debugPrint`, `dump(`, `String(describing`, `.description`, `URLSession.shared`, `HTTPCookieStorage` в `App/` і `Packages/**` нічого не знайшов. `InnerTubeError` не містить ні тіл, ні заголовків. Фікстури синтетичні (`Test User N`, `test0@example.com`, `yt3.ggpht.com/test-*`, `example.com`) |
| Проковтнуті помилки | `try?` у `AccountModel.swift:23-24` свідомі: збій списку видно як «Couldn't load other accounts» з Retry (FR8, закрито Low 5 з 1.2), а збій меню дає `.failed`. Нейтральне значення `[]` див. Low 2 |

## Critical findings (для fix pass)

Немає.

## High findings (для fix pass)

Немає.

## Medium recommendations (рекомендовано включити у fix pass)

### 1. `.failed` ховає список: після перемикання на «зламаний» акаунт повернутися можна лише через вихід з усіх акаунтів — `App/AccountModel.swift:34`, `App/AccountView.swift:37-39`

**Проблема (тихий збій, з'явився в цій зміні).** Якщо меню повернуло `nil`, `load` записує `state = .failed`, і список `accounts` відкидається, навіть якщо його вже успішно завантажено:

```swift
state = info.map { .loaded($0, accounts: accounts) } ?? .failed
```

Гілка `.failed` в `AccountView` показує лише «Couldn't load your account», Retry, «Add account» і «Sign out», без рядків акаунтів. До 1.3 рядків не було взагалі, тож перейти на «зламаний» індекс було неможливо. Тепер можливо.

**Сценарій збою.**
1. Користувач перемикається на акаунт 1.
2. Згодом сесія акаунта 1 у Google вимагає повторного входу (зміна пароля, політика Workspace) або Google віддає для цього індексу HTTP 200 без `activeAccountHeaderRenderer` (discovery P1 саме так описує індекс поза межами).
3. Список (запит з `X-Goog-AuthUser: 0`) і далі містить `authuser=1`, тому FR15 не скидає індекс.
4. `account_menu(1)` падає, і настає `.failed`. Retry повторює те саме, «Add account» індекс не змінює (`AuthSession.swift:97`). Вийти можна тільки через «Sign out», а він завершує сесію **всіх** акаунтів.
5. Так буде на кожному запуску, бо індекс збережено в `UserDefaults`.

Другий тригер — `authuser` без верхньої межі (`AccountListItem.swift:39-40`). Рядок з дуже великим індексом (дивна відповідь) після кліку приводить до того самого глухого кута. Окремої межі не треба: виправлення нижче закриває обидва випадки.

**Рекомендоване виправлення (на рівні символів).**
- `App/AccountModel.swift`:
  - у `State` замінити `case failed` на `case failed(accounts: [AccountListItem]?)`;
  - рядок 34 замінити на `state = info.map { .loaded($0, accounts: accounts) } ?? .failed(accounts: accounts)`.
- `App/AccountView.swift`:
  - блок `if accounts.count > 1 { ForEach(accounts) { AccountRow(...) } }` (`:23-32`) винести в `private struct AccountRows: View { let accounts: [AccountListItem]; let session: AuthSession }` з тим самим тілом (`isActive`, `isDisabled: session.isSigningOut`, `onSelect`);
  - у `.loaded` викликати `AccountRows(accounts: accounts, session: session)` замість інлайн-блоку;
  - гілку `case .failed:` замінити на `case .failed(let accounts):`, лишити текст і Retry, а під ними `if let accounts { AccountRows(accounts: accounts, session: session) }`.

Активний «зламаний» рядок лишається вимкненим з галочкою, а клік на інший рядок повертає користувача на робочий акаунт. Тест неможливий, бо таргета для `App/` немає. Перевірка: рев'ю, а вручну, якщо вдасться відтворити, — акаунт, що потребує повторного входу.

**Статус: Fixed in fix pass.** `.failed(accounts:)` + спільний `AccountRows` у `.loaded` і `.failed`.

**Чому Medium, а не High.** Це не атака і не витік. Обхідний шлях є («Sign out»), а умова специфічна: індекс є в списку, але `account_menu` для нього стабільно падає. Проте зміна мала і без побічних ефектів, тож її варто взяти у fix pass, як M1 в 1.2.

## Поза скоупом

### Low

1. **Індекс рядка залежить від порядку словника, якщо в елементі кілька `signinUrl`** (`Packages/InnerTube/Sources/InnerTube/AccountListItem.swift:37`, `:55-66`).
   - **Сценарій.** `values(forKey:)` обходить `dict.values`, а їхній порядок у Swift `Dictionary` випадковий для кожного процесу (hash seeding). Розробник і QA про це знають (`02-development.md:25`, `03-qa.md:28`). Якщо Google додасть в `accountItem` другий `signinUrl` з іншим `authuser` (наприклад, у вкладеному токені повторного входу), між запусками рядок «Акаунт A» може отримувати індекс акаунта B. Тоді клік перемикає не туди. Заголовок показує справжнє ім'я з `account_menu`, тож розбіжність видно, і всі акаунти належать тому самому користувачеві. Проте історію прослуховування й надалі лайки буде записано не в той акаунт. Discovery зафіксувала по одному `signinUrl` на елемент, тож поки ризик гіпотетичний.
   - **Виправлення.** У `item(_:)` зібрати всі `signinUrl`:
     ```swift
     let urls = json.values(forKey: "signinUrl").compactMap(\.string).compactMap(URLComponents.init(string:))
     let indices = Set(urls.compactMap { $0.queryItems?.first(where: { $0.name == "authuser" })?.value.flatMap(Int.init) })
     guard indices.count == 1, let authUser = indices.first, authUser >= 0 else { return nil }
     ```
     `isBrand` має перевіряти `pageid` в **усіх** `urls`. Неоднозначний елемент відкидається, тобто fail-closed. Тест у `AccountListTests`: елемент з `authuser=0` і `authuser=1` відкидається, а з двома однаковими `authuser=1` лишається.

   - **Статус: Fixed in fix pass.** `item(_:)` відкидає елемент, якщо `signinUrl` дають різні `authuser`; `pageid` перевіряється в усіх URL; додано 2 тести.

2. **Порожній розібраний список `[]` не відрізнити від зміни формату** (`App/AccountModel.swift:25-34`, `App/AccountView.swift:22-23`).
   - **Сценарій.** Google перейменовує `signinUrl`, `accountItem` або додає `pageIdToken` до особистих елементів. Парсер повертає `[]`, перемикач мовчки зникає, повідомлення немає, FR15 вимкнено. Сесія з входом завжди має принаймні акаунт 0, тож справжній `[]` означає, що парсер зламався.
   - **Можливе виправлення.** У `load` трактувати `[]` як `nil`: `let accounts = await list.flatMap { $0.isEmpty ? nil : $0 }`. Тоді показується «Couldn't load other accounts».
   - **Чому відкладено.** Це суперечить AC5 / FR7 («порожній список … скидання не викликають», `[]` як валідний стан без помилки) і рішенню BA. Потрібне рішення користувача.

   - **Статус: Fixed in fix pass** (рішення користувача: збій). `AccountModel.load` трактує `[]` як `nil`: показується «Couldn't load other accounts» з Retry, індексний fallback не спрацьовує.

### Info

1. **Порт на регіональному SetSID не обмежено** (`SignInRules.swift:23-31`, тест `SignInRulesTests.swift:54`). `https://accounts.google.de:8443/accounts/SetSID` дозволено. Хост однаково належить Google, TLS-ланцюжок перевіряє ATS, а атакувальник не може змусити Google слухати чужий порт. Нічого не робити. Якщо колись знадобиться суворіше правило, додати `url.port == nil`.
2. **Застереження для fix pass щодо AC14 (7): шлях SetSID ще не перевірено вживу.** Вхід через регіональний SetSID досі чекає ручної перевірки (`03-qa.md:20`). Якщо він зависне, бо Google веде на інший шлях регіонального хоста (наприклад, `/accounts/SetSIDFrame` чи інший регістр), треба **додати саме цей точний шлях** у `isRegionalSetSID` (`SignInRules.swift:31`) разом із тестом. **Не можна** прибирати перевірку шляху чи повертатися до правила «будь-який шлях на хості»: це знову відкриє знахідку автоматичного рев'ю. Те саме стосується `;params` у шляху. На macOS 14+ `path(percentEncoded:)` їх, імовірно, включає (тоді fail-closed), але в runtime це не перевірено.
3. **`gds.google.com` без обмеження шляху** (`SignInRules.swift:12`). Точний хост Google, доданий у 1.2 за фактом QA і в цій зміні не змінений. Редиректи з нього однаково перевіряє allowlist. Посилення (необов'язкове, після AC14): дозволяти лише шляхи з префіксом `/web/`, як `isRegionalSetSID`, з тестом `gds.google.com/web/landing` → true, `gds.google.com/x` → false.
4. **Процедура оновлення знімка задокументована лише в коді** (`GoogleSupportedDomains.swift:2`). Застарілий знімок дає fail-closed: вхід через новий ccTLD зависне, а не стане небезпечним. Але в `docs/02` §6 та `docs/05` немає жодного рядка про те, що регіональний SetSID приймається лише зі знімка і що його треба оновлювати вручну. **Виправлення (фаза документації):** один рядок у `docs/02-architecture.md` §6 п.1: «The sign-in window allows exact Google hosts plus `accounts.<google domain>/accounts/SetSID` for domains from an embedded snapshot of google.com/supported_domains; refresh the snapshot when a regional sign-in hangs.» Також закрити security note 1.3 у `docs/06-backlog.md:29`.
   - **Статус: Fixed in fix pass** (рядок у `docs/02-architecture.md` §6 додано; `docs/06-backlog.md` не чіпали, лишається фазі документації).
5. **XSSI-префікс приймається лише в точній формі `)]}'`** (`JSONValue.swift:30-31`). Інша форма дає `.unexpectedResponse` і «Couldn't load other accounts». Це fail-safe, дій не потрібно, поки Google не змінить формат.
6. **Глибина вкладеності JSON (L4 з 1.2) досі не перевірена** (`JSONValue.swift:11-26`, `AccountListItem.swift:55-66`). Тепер додалася ще одна рекурсія, `values(forKey:)`, яка на кожному рівні робить конкатенацію масивів (O(n·глибина) копіювань). Атакувальником має бути Google або MITM з довіреним CA. Виправлення те саме, що в 1.2: тест на 1000 рівнів `[`, а якщо він падає, відкидати тіла з глибиною понад 128 до `decode`.
7. **Відхилення редиректів для GET не перевірено в runtime** (`InnerTubeClient.swift:9-18`, Info 1 з 1.2). Делегат спільний, тож поведінка та сама, що для POST. Тест з `URLProtocol`-стабом (302 → `.httpStatus(302)`) варто додати, коли в 2.1 з'явиться шов для транспорту.
8. **Індекс з `UserDefaults` не обмежено** (`AuthSession.swift:35`, `AccountListItem.swift:29-30`). Від'ємне чи величезне значення може записати лише локальний користувач через `defaults write`. Для непорожнього списку `fallbackIndex` повертає 0. Якщо список недоступний, від'ємний індекс піде в заголовок як `"-1"`, а меню дасть `.failed`. Межі довіри тут немає, дій не потрібно.
9. **Точність документів.** Обидва документи точні:
   - `docs/02-architecture.md:163-165` (вибраний `authUserIndex`, GET без тіла, необов'язковий `)]}'`, список завжди з `X-Goog-AuthUser: 0`) і `:178` (рядок ендпоінта, `authuser` з `signinUrl`, brand пропускаються) відповідають коду;
   - `docs/05-risks-and-scope.md:61` відповідає рішенню: список з `getAccountSwitcherEndpoint`, перемикання лише через `X-Goog-AuthUser`, brand поза скоупом, вихід завершує сесію всіх акаунтів.

   Дрібні уточнення (необов'язкові):
   - у docs/05 посилання «(AC13)» стосується QA 1.2, а повторну перевірку `accounts_list` у 1.3 зроблено в discovery P2. Краще «(1.2 AC13; re-checked in 1.3 discovery)»;
   - `docs/02` §5.1 каже, що `clientVersion` «taken from the page», а в коді це константа до 2.1. Це було й до цієї зміни.

   §2 п.4 у docs/05 (два сховища, Keychain лише з `youtube.com`) лишається точним: нових сховищ і копіювання cookies `google.com` немає.

## Зведення за severity

| Severity | Кількість | Що далі |
|---|---|---|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 1 | M1: `.failed(accounts:)` і рядки у стані помилки (`AccountModel.swift:34`, `AccountView.swift:37-39`). Рекомендовано включити у fix pass |
| Low | 2 | L1 — детермінований `authuser` (відкидати неоднозначні елементи); L2 — `[]` як збій, потрібне рішення користувача |
| Info | 9 | поза скоупом. Info 2 (не послаблювати перевірку шляху SetSID, якщо AC14 (7) не пройде) і Info 4 (рядок у docs/02 §6 та закриття security note в backlog) — для fix pass і фази документації |
