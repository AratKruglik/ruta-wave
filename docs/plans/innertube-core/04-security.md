# Огляд безпеки: InnerTube core — WEB_REMIX, SAPISIDHASH, account_menu, екран акаунта (backlog 1.2)

## Підсумок
- Critical: 0
- High: 0
- Medium: 1 (рекомендація. Виправлення займає один рядок, тож оркестратор може включити його у fix pass, як M1 в 1.1)
- Поза скоупом: Low 6, Info 9

Прямого шляху експлуатації немає. Усі шляхи облікових даних у коді закриті:
- у Keychain лежать лише cookies `youtube.com`, а запит фільтрує їх ще раз;
- хост задано константою;
- редиректи відхиляються, тож заголовки сесії на інший хост не підуть;
- сесія `ephemeral`, сховище cookies і кеш вимкнено (`nil`);
- логування немає.

Головна знахідка (M1) стосується не безпеки, а тихого збою. Для правдоподібної форми відповіді `accounts_list` екран акаунта назавжди лишається в стані завантаження, без помилки і без «Retry».

## Що перевірено і виявилося чистим

| Перевірка | Результат |
|---|---|
| Які cookies і куди йдуть | `Cookie` будується з `SignInRules.musicCookies(cookies)` (`InnerTubeRequest.swift:20`). Фільтр пропускає лише домени `youtube.com` і `music.youtube.com` (`SignInRules.swift:26-28`), а Keychain і так містить тільки їх (`SignInView.swift:116`). Отже, фільтр подвійний. Cookies `google.com` / `accounts.google.com` у запит не потрапляють, і це фіксує тест `cookieHeaderDropsExpiredAndForeignDomains`. Хост фіксований: `origin` — константа (`:5`), `endpoint` — рядкові літерали в `InnerTubeClient.swift:32, 37` |
| `SAPISIDHASH` | `sha1("<ts> <SAPISID> <origin>")`, `ts` у секундах, `origin = "https://music.youtube.com"` (`SAPISIDHash.swift:6`, `InnerTubeRequest.swift:39`). `SAPISID` береться лише з cookie домену `youtube.com` / `.youtube.com` (`:17, 52-54`), а однойменна cookie на `music.youtube.com` ігнорується (тест `setsAuthHeadersFromRootSAPISID`). Якщо cookie немає, запит не будується (`.missingSAPISID`). Вектор у тесті синтетичний і обчислений незалежно |
| `X-Goog-AuthUser` | `"\(authUserIndex)"` від `Int` (`:42`), тож ін'єкції в заголовок бути не може. Те саме для індексу з `signinUrl`: `Int.init` (`AccountListItem.swift:45`). Межі див. L3 |
| Логування й персистентність (A09) | `grep` за `print(`, `Logger`, `os_log`, `NSLog`, `debugPrint`, `dump(`, `String(describing`, `.description`, `URLSession.shared`, `URLCache`, `HTTPCookieStorage`, `CFNETWORK` у `App/`, `Packages/*/Sources`, `Packages/*/Tests`, `project.yml`, plist і entitlements нічого не знайшов. `InnerTubeError` має лише `missingSAPISID`, `httpStatus(Int)` і `unexpectedResponse`, тобто без тіл, заголовків і cookies. `AccountModel` помилки не показує, а UI виводить фіксовані рядки |
| Конфігурація URLSession | `ephemeral`, `httpCookieStorage = nil`, `httpShouldSetCookies = false`, `urlCache = nil` (`InnerTubeClient.swift:24-28`). На запиті `httpShouldHandleCookies = false` (`InnerTubeRequest.swift:38`). `Set-Cookie` ігнорується, авторизовані відповіді на диск не кешуються. `urlCredentialStorage` лишається ефемерним у пам'яті й порожнім, бо облікових даних для challenge немає |
| Редиректи | `RejectRedirects.willPerformHTTPRedirection` повертає `nil` (`:9-18`). Отже, 3xx повертається як відповідь і стає `.httpStatus` (`:64`), а `Cookie`/`Authorization` на інший хост не йдуть. Це важливо, бо немає гарантії, що URLSession під час кросхостового редиректу прибере заголовки сесії, особливо вручну встановлений `Cookie` (поведінку платформи тут не перевірено). Runtime-перевірки теж немає (див. Info 1) |
| TLS / ATS | Ключів `NSAppTransportSecurity` немає (`GENERATE_INFOPLIST_FILE`, `project.yml` без змін), тож діє ATS за замовчуванням: TLS 1.2+ і валідний ланцюжок. Схема `https` зашита в `origin`. Пінінгу немає, і це правильно (Info 2) |
| Розбір JSON | `JSONValue` декодується за лінійний час: на кожному рівні одна спроба масиву, об'єкт відкидається одразу через type mismatch, тож експоненційних повторів немає. Доступ за ключем або індексом повертає `nil` замість падіння (`JSONValue.swift:28-36`). У парсерах немає force unwrap. Відсутній `accountName` дає `throw` (`AccountInfo.swift:16`), а не порожнє ім'я. Нерозбірне тіло дає `.unexpectedResponse`. Глибину вкладеності див. L4 |
| Рендеринг даних із відповіді | `Text(info.name)`, `Text(handle)`, `Text(account.name)`, `Text(byline)` отримують `String`, а не `LocalizedStringKey`, тож текст виводиться дослівно. Ін'єкції Markdown чи посилань немає |
| Перегони в `AccountModel` (AC8) | Модель `@MainActor`, тож усі записи `state` і `session.authUserIndex` відбуваються синхронно на MainActor після `await` і після перевірки `Task.isCancelled` (`AccountModel.swift:29, 33`). Між перевіркою і записом немає точки призупинення, тож чергування неможливе. `.task(id:)` скасовує попередню задачу до старту нової. Після «Sign out» `AccountView` зникає, задача скасовується, і нічого не записується. Через межу ізоляції йдуть `[HTTPCookie]` (`NS_SWIFT_SENDABLE`) та `Int`. `RejectRedirects` — `final class` без стану, тож `Sendable` коректний |
| FR14 (L1 з 1.1) | **Закрито.** `restore()` скидає індекс, коли відкидає елемент (`AuthSession.swift:51-54`). `completeSignIn` скидає індекс на звичайному вході (`:96`) до `state = .signedIn` |
| Вихід після змін 1.2 | **Облікові дані очищаються повністю.** `signOut()` (`AuthSession.swift:72-88`) не змінено: спершу `removeData` WebKit, потім Keychain, потім індекс 0 і `.signedOut`. M1 з 1.1 збережено: «Add account» вимкнено під час виходу (`AccountView.swift:30`). `InnerTubeClient` нічого не пише на диск, бо сесія ефемерна, а cookies і кеш вимкнено. Новий нечутливий залишок — аватар у дисковому `URLCache.shared` (L2) |
| Тести й фікстури | Синтетичні дані: `test-…`, `Test User`, `@testhandle`, `example.com`, `user@example.com`. Реальних cookies чи відповідей немає |
| L3 з 1.1 (`HTTPCookie.description`) | Досі актуальне застереження, але порушень немає: `session.state` і масиви cookies ніде не інтерполюються |

## Critical findings (для fix pass)

Немає.

## High findings (для fix pass)

Немає.

## Medium recommendations (у цьому прогоні не виправляються)

### 1. Екран акаунта нескінченно показує завантаження і мовчки скидає вибір акаунта — `App/AccountModel.swift:34-37`

**Проблема (тихий збій).** Розглянемо гілку FR15 у ситуації, коли список непорожній, але в ньому немає елемента з поточним `index`:

```swift
if !accounts.isEmpty, !accounts.contains(where: { $0.authUserIndex == index }) {
    session.authUserIndex = 0
    return
}
```

Якщо `index` уже дорівнює 0, присвоєння `0` не змінює `ReloadKey`, тож `.task(id:)` повторно не спрацьовує. `return` лишає `state == .loading`, встановлений на рядку 21. Користувач бачить нескінченний `ProgressView` без помилки і без «Retry» (кнопка є лише у `.failed`), і так буде на кожному запуску. Якщо `index = N ≠ 0`, застосунок мовчки перемикається на 0, а далі потрапляє в той самий глухий кут.

**Сценарій.** Це правдоподібна форма відповіді, а не атака. Активний акаунт у `accounts_list` може не мати `accountSigninToken.signinUrl` з `authuser`, бо щоб вибрати поточний акаунт, токен входу не потрібен. Тоді парсер відкидає його (`AccountListItem.swift:30-34`), а в списку лишаються інші акаунти сесії. Друга можливість: `requestType: "ACCOUNTS_LIST_REQUEST_TYPE_CHANNEL_SWITCHER"` повертає канали, індекси яких не збігаються з поточним. AC13(6) саме це і має перевірити. Але поки цього не перевірено, код має завершуватися видимим станом, а не зависати.

**Рекомендоване виправлення.** Змінити один рядок у `App/AccountModel.swift:34`:

```swift
if index != 0, !accounts.isEmpty, !accounts.contains(where: { $0.authUserIndex == index }) {
```

Тоді для `index == 0` код переходить до `state = .loaded(info, accounts)`. Для `index ≠ 0` FR15 спрацьовує як задумано: після перезавантаження з 0 екран показує дані. Якщо AC13 покаже, що активний елемент справді не має `authuser`, FR15 треба вимкнути повністю (запасний варіант (в) з відповіді №1, план §8). Інакше вибір акаунта N ніколи не зберігатиметься.

**Чому відкладено.** Це не вразливість, а доступність єдиного екрана. «Sign out» і «Add account» лишаються доступними, і AC13 цей випадок виявить. Проте зміна займає один рядок без побічних ефектів, тож її варто включити у fix pass.

Статус: Fixed in fix pass (`index != 0,` додано в `AccountModel.swift:34`).

## Поза скоупом

### Low

1. **URL аватара не перевіряється** (`Packages/InnerTube/Sources/InnerTube/AccountInfo.swift:29-31`, використання в `App/AccountView.swift:82`). `URL(string:)` приймає будь-яку схему: `file:`, `data:`, будь-який `https`-хост. `AsyncImage` вантажить через `URLSession.shared`, тобто через спільні `HTTPCookieStorage.shared` і `URLCache.shared`. Відповідно:
   - `file:///…` покаже локальне зображення (ексфільтрації немає);
   - `https://<будь-який хост>` дає GET без контролю з IP користувача.

   План (AC11) стверджує, що аватар вантажиться «без cookies сесії». Чи ділить на macOS сховище `WKWebsiteDataStore.default()` cookies з `HTTPCookieStorage.shared`, тут **не перевірено**. Якщо ділить, URL на `*.youtube.com` / `*.google.com` отримав би cookies сесії, хоч і лише від самого Google. Атакувальник має контролювати відповідь `music.youtube.com`, тобто бути Google або зламати TLS, тому Low.

   **Виправлення:** у `lastThumbnailURL` приймати лише `https` і хост із суфіксом `ggpht.com`, `googleusercontent.com` або `ytimg.com`, а для всього іншого повертати `nil` (буде заглушка):
   ```swift
   func lastThumbnailURL(_ photo: JSONValue) -> URL? {
       guard let url = photo["thumbnails"]?.array?.last?["url"]?.string.flatMap(URL.init(string:)),
             url.scheme == "https", let host = url.host?.lowercased(),
             ["ggpht.com", "googleusercontent.com", "ytimg.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) })
       else { return nil }
       return url
   }
   ```
   Фікстури в `AccountParsingTests` (`https://example.com/…`) треба замінити на синтетичні `https://yt3.ggpht.com/test-avatar` і додати один кейс, де `file:`/`example.com` дає `nil`. Список хостів звірити з живою відповіддю на AC13. Якщо URL там protocol-relative (`//yt3.ggpht.com/…`), дописувати `https:`.

   Статус: Fixed in fix pass (`AccountInfo.swift`, `lastThumbnailURL`; фікстури оновлено, додано тест відхилення).

2. **Після виходу аватар лишається в дисковому кеші** (`Packages/Auth/Sources/Auth/AuthSession.swift:79`, `App/AccountView.swift:82`). `AsyncImage` кешує відповідь у `URLCache.shared`, тобто в `~/Library/Caches/dev.kruhlyk.tunewave/` (`Cache.db`, `fsCachedData`): зображення профілю та його URL. `removeData(ofTypes:)` очищає лише сховище WebKit. Облікових даних там немає, тільки персональні дані. Залишок Info 7 з 1.1. **Виправлення:** у `signOut()` одразу після рядка 79 додати `URLCache.shared.removeAllCachedResponses()`.

   Статус: Fixed in fix pass (`AuthSession.swift:80`).

3. **Межі `authuser`** (`Packages/InnerTube/Sources/InnerTube/AccountListItem.swift:44-46`). `Int.init` приймає `"-1"`, і від'ємний індекс потрапить в `authUserIndex`, у `UserDefaults` і в `X-Goog-AuthUser`. Наслідок: 4xx і стан помилки. Ін'єкції немає. **Виправлення:** `….value.flatMap(Int.init).flatMap { $0 >= 0 ? $0 : nil }`.

4. **Глибина вкладеності JSON** (`JSONValue.swift:11-26`, `AccountListItem.swift:15-24`, `InnerTubeClient.swift:66`). Рекурсивне `Decodable`, рекурсивний обхід `accountItems` і деініціалізація глибокого enum виконуються на потоці кооперативного пулу з невеликим стеком. Ліміт глибини в `JSONDecoder` (у swift-foundation, імовірно, 512) тут **не перевірено**. Якщо його немає або він завеликий, відповідь на кшталт `[[[[…]]]]` призведе до переповнення стеку, тобто до падіння (DoS), без корупції пам'яті. Атакувальником знову має бути Google або MITM. **Виправлення (за потреби):** один тест у `JSONValueTests` на 1000 рівнів `[`. Якщо він падає, перед `decode` відкидати тіло з глибиною понад 128 (сканування `[`/`{` поза рядками) як `.unexpectedResponse`.

5. **Збій списку акаунтів проковтується в `[]`** (`App/AccountModel.swift:23`). Мережевий збій чи 4xx `accounts_list` неможливо відрізнити від сесії з одним акаунтом: перемикання просто зникає без сигналу. Це свідоме рішення (D5), і `[]` блокує FR15, тож шкоди немає. Коли в 2.1 з'явиться модель помилок, повертати `Result` і показувати «Couldn't load the account list».

6. **docs/05 §4 #2 подає непідтверджене як вирішене** (`docs/05-risks-and-scope.md:60`). У тексті сказано «The account list comes from `account/accounts_list`», хоча семантику (`CHANNEL_SWITCHER`, `authuser` у `signinUrl`) ще не перевірено (план D5, §8). **Виправлення:** дописати «(pending manual check AC13; fallback: active account only, switching moves to a new backlog row)».
   Статус: Fixed in fix pass (`docs/05-risks-and-scope.md` §4 #2).

### Info

1. **Відхилення редиректів не перевірено в runtime.** Транспорт без тестів, за планом. Спрацювання делегата сесії для async `data(for:)` і async-варіант `willPerformHTTPRedirection` тут не перевірено. Тест з `URLProtocol`-стабом (відповідь 302 на `https://example.com` → `.httpStatus(302)`) варто додати, коли в 2.1 з'явиться шов для транспорту.
2. **Пінінгу сертифікатів немає, і це правильно.** Google ротує сертифікати, а ризик (корпоративний MITM з довіреним root CA) такий самий, як у браузера.
3. **Розмір і час відповіді не обмежені.** `data(for:)` буферизує все тіло, а `timeoutIntervalForResource` за замовчуванням дорівнює 7 дням, тож сервер, який повільно віддає дані, тримає спінер. Від Google це нереалістично.
4. **`Cookie` ігнорує path і host-only.** FR4 обіцяє «стандартні правила», а фільтр перевіряє лише домен і строк дії. Якщо `SAPISID` є і на `.youtube.com`, і на `music.youtube.com`, заголовок містить обидві cookies, а хеш рахується від кореневої. Витоку поза `youtube.com` немає. Коректність перевіряє AC13.
5. **Дублікати `id` у `ForEach`** (`AccountView.swift:55`). Якщо `accounts_list` поверне кілька елементів з однаковим `authuser` (канали одного акаунта), `id: authUserIndex` зіткнуться. Наслідок для UI невизначений, але без падіння.
6. **Кнопки перемикання акаунта не вимкнені під час `isSigningOut`** (`AccountView.swift:56-57`). Перемикання під час виходу лише запускає зайвий запит. Після успішного виходу індекс однаково 0.
7. **`URLSession` не інвалідовується** (`InnerTubeClient.swift:28`). Сесія тримає делегат до `invalidate…`, тож кожен `AccountModel` залишає її в пам'яті. `@State private var model = AccountModel()` (`AccountView.swift:12`) обчислюється при кожному `init` в'ю, тож створюються ще й тимчасові екземпляри. Даних сесії ці об'єкти не тримають (cookies й кеш вимкнено). Це витік ресурсів, а не безпека.
8. **Помилка `JSONSerialization` на тілі запиту** мапиться в `.unexpectedResponse` (`InnerTubeRequest.swift:33-37`). Назва вводить в оману, шкоди немає.
9. **Точність docs/02:**
   - §5.1 досі каже `X-Goog-AuthUser: 0`, а тепер це вибраний `authUserIndex` (за замовчуванням 0);
   - у §5.2 немає рядка `account/accounts_list`;
   - §7 («images use `AsyncImage` plus `URLCache`») і §6 п.4 («Sign-out: clear the Keychain and `WKWebsiteDataStore`») разом означають, що кеш зображень після виходу лишається, див. L2;
   - §6 п.1 уточнено правильно.

   docs/05 §2 п.4 щодо облікових даних лишається точним: InnerTube не створює нових сховищ cookies.

## Зведення за severity

| Severity | Кількість | Що далі |
|---|---|---|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 1 | рекомендація: `index != 0` в `AccountModel.swift:34` (одна зміна, можна включити у fix pass) |
| Low | 6 | поза скоупом. L1 (allowlist аватара) і L2 (`URLCache` у `signOut`) дешеві, їх варто зробити до 2.1 |
| Info | 9 | поза скоупом |
