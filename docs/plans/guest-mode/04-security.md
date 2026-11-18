# Огляд безпеки: гостьовий режим (backlog 1.4)

## Підсумок
- Critical: 0 (у fix pass нічого)
- High: 0 (у fix pass нічого)
- Medium: 1. Це рекомендація, але **варто включити у fix pass**: виправлення в один рядок, вада з'явилася саме в цій зміні (як M1 в 1.2 і 1.3).
- Поза скоупом: Low 1, Info 8

Прямого шляху експлуатації немає. Облікові дані гостьового й авторизованого шляхів розділено **структурно**:
- `makeGuest` не має параметра cookies і не бачить `AuthSession`;
- `make`/`makeGet` не мають параметра `visitorData`.

`visitorData` валідується явним ASCII-allowlist (1...512 символів) у трьох місцях. Він живе лише в пам'яті під `OSAllocatedUnfairLock`, скидається на кожну зміну `isSignedIn`, а відповіді, що прийшли після скидання, відкидаються за `generation`. Ніде не логується, не зберігається й не показується.

Головна знахідка (M1) — гонка Cancel із входом, який саме завершується. `cancelSignIn` перевіряє стан лише на вході. Поки йде асинхронне очищення WebKit, `completeSignIn` може записати сесію в Keychain і перевести стан у `.signedIn`. У результаті Cancel користувача проігноровано, а у Keychain є сесія при порожньому WebKit. Саме цей кінцевий стан план (R-a) називав неприпустимим, тільки досягнутий у зворотному порядку.

## Що перевірено і виявилося чистим

| Перевірка | Результат |
|---|---|
| Гостьовий запит без облікових даних (`InnerTubeRequest.swift:24-36`, `:68-78`) | `makeGuest` будує запит через `unauthenticated`, який ставить лише `Origin`, `X-Origin`, `User-Agent` і `httpShouldHandleCookies = false`. Далі `attachPayload` (`:80-97`) додає тіло й `Content-Type`. Параметра cookies немає, `SignInRules`/`AuthSession` не викликаються, тож `Cookie`, `Authorization` і `X-Goog-AuthUser` у гостьовий запит потрапити не можуть, навіть якщо в Keychain є сесія (E1). Тести: `GuestRequestTests.swift:8-27`, `:93-101` |
| `X-Goog-Visitor-Id` в авторизованих запитах (`InnerTubeRequest.swift:9-22`, `:38-66`) | Ні `make`, ні `makeGet`, ні `signed` не мають параметра `visitorData` і не звертаються до `GuestVisitor`. Отже, гостьовий ідентифікатор не може поєднатися з `Cookie`/`SAPISIDHASH` у тому самому запиті. Тест: `GuestRequestTests.swift:71-77`. Наявні тести 1.2/1.3 не змінено |
| Транспорт (`InnerTubeClient.swift:23-29`, `:71-76`) | Сесія `ephemeral`, `httpCookieStorage = nil`, `httpShouldSetCookies = false`, `urlCache = nil`, редиректи відхиляє `RejectRedirects`. Тому `Set-Cookie` з гостьових відповідей (`VISITOR_INFO1_LIVE`, `YSC`) ніде не зберігається, відповідь не кешується, а 3xx дає `.httpStatus`. Кожен `InnerTubeClient` має власну сесію, тож у гостьового й авторизованого клієнтів немає спільного сховища |
| Валідація `visitorData` (`GuestVisitor.swift:29-38`) | Перевірка `unicodeScalars` проти явного набору `A–Z a–z 0–9 - _ % =`. CR/LF, пробіл, `:`, кирилиця й не-ASCII цифри відкидаються (`isLetter`/`isNumber` не використовуються). Коли всі скаляри ASCII, `count` дорівнює довжині в байтах, тож межа 512 — це 512 байт заголовка. Валідація виконується тричі: `connectAsGuest` (`InnerTubeClient.swift:46`), `accept` (`GuestVisitor.swift:23`) і `makeGuest` (`InnerTubeRequest.swift:31`). Ін'єкція заголовка неможлива. `%` іде в заголовок буквально, `URLSession` його не декодує. Тести: `GuestRequestTests.swift:38-51` |
| Невалідне значення не перезаписує попереднє (AC8) | `accept` повертається до взяття lock (`GuestVisitor.swift:23`). Тест: `GuestRequestTests.swift:53-59` |
| AC10: авторизовані відповіді не задають `visitorData` | `grep '\.accept('` знаходить єдиний виклик, `InnerTubeClient.swift:47`, у `connectAsGuest`. `accountMenu`/`accountSwitcher` `responseContext` не читають |
| Конкурентність (`GuestVisitor.swift:11-27`) | `OSAllocatedUnfairLock<Snapshot>`, де `Snapshot` — `Sendable` struct. Кожне читання й запис іде всередині `withLock`. `accept` валідує поза lock (чиста функція), а compare-and-set за `generation` робить атомарно всередині. Під lock немає викликів назовні й немає повторного входу. `reset` атомарно обнуляє значення й збільшує `generation` |
| Гард `generation` (E2) і порядок скидань | `connectAsGuest` бере `snapshot()` до відправки й передає його `generation` в `accept`. **Вхід** (скидання, на якому все тримається): коли гостьова відповідь приходить між `state = .signedIn` і `onChange`, значення записується, а потім `reset` його стирає. Коли вона приходить після `reset`, її відкидає `generation`. В обох порядках після входу значення `nil`. **Вихід**: під час `.signedIn` `accept` не викликається, тож значення вже `nil`. Якщо `.task` нового `GuestView` візьме знімок раніше, ніж кореневий `onChange` скине стан, буде відкинуто лише одне нове значення, тобто fail-safe: наступний запит піде без заголовка. **Не «виправляти»** це прибиранням гарда чи скидання при виході. Тест: `GuestRequestTests.swift:61-69`, `:86-91` |
| Не логується, не зберігається, не показується (AC22) | `grep` за `print(`, `Logger`, `os_log`, `NSLog`, `debugPrint`, `dump(`, `String(describing`, `UserDefaults` в `App/` і `Packages/**/Sources` нічого нового не знайшов. `GuestModel.State` (`GuestModel.swift:6`) — enum без payload, тому `GuestView` показує лише фіксовані рядки, без тексту помилки й без `visitorData`. Фікстури синтетичні (`"CgtTWU5USEVUSUMxMjM%3D"`, `"test-root"`) |
| `continueAsGuest` (`AuthSession.swift:72-75`) | Діє лише з `.keychainUnavailable` і Keychain не чіпає (AC19, тест `AuthSessionTests.swift:37-45`). З `.signedIn` нічого не робить (тест `:94-100`). `isSignedIn` лишається `false`, тож скидання `visitorData` не потрібне. Проте подальший Cancel входу в цьому стані стирає WebKit, див. Low 1 |
| Гард `cancelSignIn` проти setter'а аркуша (`AuthSession.swift:77-84`) | `guard case .signedOut = state, !isSigningOut`. Коли `completeSignIn` вже поставив `.signedIn`, корінь прибирає `GuestView`, а будь-який виклик setter'а → `cancel()` → `cancelSignIn()` потрапляє на гард. Тест: `AuthSessionTests.swift:57-65`; для `.keychainUnavailable` — `:102-109`. Зворотний порядок (вхід завершується **під час** очищення) не закрито, див. M1 |
| `signOut` (`AuthSession.swift:91-107`) | Порядок WebKit → Keychain і коментар збережено. `wipeWebData` (`:86-89`) — ті самі два рядки, що й раніше: `WKWebsiteDataStore.default()` всі типи плюс `URLCache.shared`. `isAddingAccount = false` ставиться до першого `await`, тож координатор add-account під час виходу `completeSignIn` не викличе |
| Шляхи `restore()` (`AuthSession.swift:39-57`) | Без змін. Помилка читання дає `.keychainUnavailable` без видалення (тест `AuthSessionTests.swift:84-92`). Пошкоджений чи прострочений запис дає `delete` і `authUserIndex = 0` (тест `:47-55`). WebKit на T3 не чиститься, це задокументовано (R-c, примітка 3.1) |
| Шов `KeychainStore` (`KeychainItem.swift:12-18`, `AuthSession.swift:28-37`) | Протокол `internal`, призначений `init(keychain:defaults:)` теж `internal`, а публічний `convenience init()` жорстко бере `KeychainItem.session`. Тож інші модулі (`App`) підмінити сховище не можуть. `KeychainSpy` — `private` у тестовому таргеті, у збірку застосунку він не лінкується. Запит до Keychain (`kSecClassGenericPassword`, service/account, доступність за замовчуванням, без синхронізації) не змінено, як і прийняте рішення docs/05 §2.4 |
| `TunewaveApp` (`TunewaveApp.swift:12-26`) | Вікно входу більше не відкривається автоматично (FR1). Екран `.keychainUnavailable` показує лише фіксований текст, без статусу помилки. `onChange(of: session.state.isSignedIn)` скидає `visitorData` на кожну зміну. Якщо вікон кілька, скидань теж кілька, і це нешкідливо |
| `GuestView` (`GuestView.swift:10-33`) | «Sign in» вимкнено, поки `isSigningOut` (`:59`), тож новий web view не вантажиться посеред очищення. Повторне натискання дає один аркуш. Cancel, Esc і закриття аркуша йдуть через `cancel()`. `SignInView` бере `signInURL`, бо `isAddingAccount == false`. Allowlist навігації не змінено |
| Тихі збої | `try?` у `GuestModel.connect` (`GuestModel.swift:13`) перетворюється на видимий `.failed` з Retry (FR13), а не на «Connected». `accept` мовчки відкидає застарілі й невалідні значення за задумом. `try? keychain.delete()` у `restore` з'явився раніше (1.1); якщо видалення не вдалося, наступний запуск повторить спробу |

## Critical findings (для fix pass)

Немає.

## High findings (для fix pass)

Немає.

## Medium recommendations (рекомендовано включити у fix pass)

### 1. Вхід, що завершується під час очищення WebKit після Cancel, зберігає сесію всупереч Cancel — `Packages/Auth/Sources/Auth/AuthSession.swift:110-123` (`completeSignIn`), разом з `:78-84` і `Packages/Auth/Sources/Auth/SignInView.swift:109-125`

**Fixed in fix pass:** `guard !isSigningOut else { return false }` на початку `completeSignIn`.

**Проблема (з'явилася в цій зміні).** Гард `cancelSignIn` перевіряє стан **лише на вході** в метод. Далі йде `await wipeWebData()`, тобто асинхронний `removeData`. Поки він виконується, MainActor вільний. Ні `SignInView.Coordinator.isSignInActive` (`SignInView.swift:122-125`), ні `completeSignIn` не перевіряють `isSigningOut`.

**Сценарій збою.**
1. Сторінка входу дійшла до `music.youtube.com`. `checkSignIn` запускає Task і чекає `await httpCookieStore.allCookies()` (`SignInView.swift:113`). Друге джерело того самого — `cookiesDidChange`.
2. Користувач натискає Cancel або Esc. `cancel()` ставить `isSigningIn = false`, а `cancelSignIn` проходить гард (стан ще `.signedOut`), ставить `isSigningOut = true` і призупиняється в `wipeWebData()`.
3. Task координатора продовжується. Координатор живий, поки йде анімація закриття аркуша. `isSignInActive == true`, бо стан `.signedOut`, тож `completeSignIn` пише cookies у Keychain і ставить `.signedIn`.
4. Очищення завершується: WebKit порожній.

Кінцевий стан такий: користувач натиснув Cancel, але увійшов, і сесія `youtube.com` збережена в Keychain. Сховища розійшлися (Keychain є, WebKit порожній): на InnerTube 1.4 це не впливає, але плеєр 3.1 гратиме як гість при UI «увійшов». Це саме той стан, від якого план захищався гардом R-a.

Вікно гонки вузьке, якщо вікно одне. Якщо вікон кілька (`WindowGroup` + спільний `session`, Cmd+N), воно ширшає: Cancel в аркуші одного вікна запускає очищення, яке триває, поки в іншому вікні може завершитися вхід.

**Рекомендоване виправлення (на рівні символу).** Перший рядок `AuthSession.completeSignIn(with:)`:

```swift
func completeSignIn(with cookies: [HTTPCookie]) -> Bool {
    // A cancel or sign-out is wiping WebKit; a completion landing now must not persist a session.
    guard !isSigningOut else { return false }
    do {
```

Потрібен саме `return false`, як і в контракті методу: «не завершено, спостерігай далі».
- Якщо вікно одне, координатор однаково знищується разом з аркушем, і значення ролі не грає.
- Якщо вікон кілька, аркуш іншого вікна, відкритий ще до очищення, лишається живим. З `return true` він поставив би `didComplete = true` і вже ніколи не завершив би вхід у цьому web view. З `false` він спостерігає далі, і після очищення (яке стирає й cookies цього аркуша) користувач може пройти вхід знову в тому самому аркуші.

Цей другий аркуш — єдиний шлях, де `completeSignIn` викликається при `isSigningOut == true`, і там відхилити завершення правильно: очищення однаково стирає його cookies. Інші шляхи гард не зачіпає:
- `signOut` ставить `isAddingAccount = false` до першого `await`, тож `isSignInActive` для `.signedIn` дає `false`;
- `addAccount` не стартує, поки `isSigningOut` (`:60`);
- «Sign in» в `GuestView` вимкнено.

Unit-тест неможливий: `isSigningOut` має `private(set)`, а встановлює його лише шлях з реальним `WKWebsiteDataStore`. Перевірка — рев'ю й наявні тести `AuthSessionTests` (`completeSignInPersistsAndSignsIn` має лишитися зеленим).

**Чому Medium, а не High.** Атакувальника немає, і нічого не витікає: креденшіали лишаються на цьому Mac, у тому самому Keychain. Потрібен збіг у часі. Наслідки такі: порушено явну дію користувача (Cancel) і розсинхронізовано сховища. Виправлення займає один рядок і не має побічних ефектів.

## Поза скоупом

### Low

1. **T6 («Continue without signing in») + Sign in + Cancel стирає WebKit-половину сесії, яку FR7 обіцяє зберегти. Примітка 3.1 «wipe on player start» зробила б те саме** (`AuthSession.swift:72-84`, `docs/06-backlog.md:46`, `docs/02-architecture.md:202`).
   - **Fixed in fix pass:** примітку 3.1 в `docs/06-backlog.md` переписано, уточнення додано в `docs/02-architecture.md` §6.
   - **Сценарій.**
     1. Keychain заблоковано (`errSecInteractionNotAllowed`), і користувач обирає «Continue without signing in». У Keychain лишається чинний запис, у WebKit — жива сесія Google.
     2. Він натискає «Sign in». Google одразу редиректить на `music.youtube.com`, бо сесія в WebKit жива, і `keychain.write` падає, бо Keychain досі заблоковано. Це T9, «Couldn't save your session».
     3. Природна реакція — Cancel, і `cancelSignIn` стирає WebKit.
     4. На наступному запуску Keychain читається, тож стан `.signedIn`, але WebKit порожній. Це той самий розсинхрон, що й у M1.
   - Інструкція в примітці 3.1 «verify and wipe on player start» у стані T6 так само мовчки знищила б WebKit-половину сесії, яку користувач не просив видаляти.
   - На 1.4 це не впливає: InnerTube бере cookies з Keychain, плеєра ще немає.
   - **Виправлення (документація, для fix pass або фази документації).**
     - Переписати примітку 3.1 в `docs/06-backlog.md:46` так, щоб вона розрізняла два випадки:
       - залишки, які треба стерти (T3 `restore()`, T9 + вихід з додатка, T14);
       - T6, де жива сесія належить користувачеві, а Keychain просто недоступний у цьому запуску, тому стирати не можна.

       Пропонований текст: «In guest state the player must not use a Google session left in the web view store. Prefer a `WKWebsiteDataStore.nonPersistent()` store for guest playback over wiping `default()`: after "Continue without signing in" (`.keychainUnavailable`) the default store holds the user's live session, which must be kept. 3.1 must also handle "signed in, web view store empty" (e.g. no `SAPISID` for `.youtube.com` in `WKHTTPCookieStore`): restore the `youtube.com` cookies from the Keychain into the store or offer sign-in».
     - У `docs/02-architecture.md:202` уточнити: «(this launch only; the Keychain entry is kept, but cancelling a later sign-in still wipes the web view store)».
   - **Альтернатива в коді (потребує рішення користувача, бо змінює OQ1).** В `AuthSession` запам'ятати, що поточний гість прийшов з `continueAsGuest`, і в цьому стані пропускати `wipeWebData()` у `cancelSignIn`. Не рекомендую без рішення: після T6 користувач міг увійти в аркуші в **інший** акаунт, і тоді часткова сесія лишилася б на диску.

### Info

1. **Примітка 3.1 неповна щодо джерел залишків** (`docs/06-backlog.md:46`).
   - У дужках названо лише `restore()` (T3). Є ще такі шляхи:
     - T9 + вихід з додатка (не Cancel): у WebKit лишається повна сесія Google, а Keychain порожній, тож наступний запуск — гість із живою сесією. Це порушує інваріант з коментаря в `signOut`.
     - T14: вихід посеред 2FA лишає частину cookies.
     - Збій процесу посеред `wipeWebData`.
     - `removeData` не повідомляє про невдачу, тож і нерезультативне очищення лишається тихим.
   - **Виправлення:** додати їх у примітку разом зі змінами з Low 1.
2. **Скидання `visitorData` прив'язане до вмісту вікна** (`App/TunewaveApp.swift:26`).
   - Скидання при вході — те, на якому все тримається. Сьогодні вхід можливий лише з аркуша у вікні, тож `onChange` завжди існує.
   - Якщо 4.1 чи 2.1 додадуть вхід або вихід поза головним вікном (команда меню, `MenuBarExtra`, автоматичний «401 → sign-in»), скидання треба перенести туди ж або на рівень, що не залежить від наявності вікна. Інакше значення до входу переживе вхід і з'явиться після виходу (FR11).
   - **Дій зараз не потрібно.** Можна додати рядок у `docs/02` §5.1: «the reset must run on every `isSignedIn` change, whichever UI triggers it».
3. **Кілька вікон: Cancel в одному аркуші стирає WebKit під входом в іншому** (`App/GuestView.swift:18`, `:29-32`, `AuthSession.swift:78-84`).
   - Результат fail-safe: вхід в іншому вікні втрачає cookies, і користувач входить заново.
   - Те саме розширює вікно гонки M1.
   - **Виправлення (4.1, необов'язково):** якщо додатку не потрібні кілька головних вікон, оголосити головну сцену як `Window` замість `WindowGroup`.
4. **Перенесено з 1.3 (Info 9): `docs/02` §5.1 досі каже, що `clientVersion` «taken from the page»** (`docs/02-architecture.md:157-158`), а в коді це константа до 2.1 (`InnerTubeRequest.swift:6-7`). Тепер цей рядок стоїть просто над новим описом гостьового запиту.
   - **Виправлення:** «`clientVersion` (a constant until 2.1, then taken from the page, key `INNERTUBE_CLIENT_VERSION` in `ytcfg`)».
5. **Перенесено з 1.3 (Info 7) + QA: немає runtime-перевірки `connectAsGuest` і відхилення редиректів** (`InnerTubeClient.swift:9-18`, `:41-48`).
   - Делегат той самий, тож поведінка та сама, що для авторизованих запитів.
   - **Виправлення (2.1):** шов для транспорту (`URLProtocol`-стаб у конфігурації сесії клієнта) і тести:
     - 302 → `.httpStatus(302)`;
     - 200 без `visitorData` → `.unexpectedResponse`;
     - 200 з невалідним `visitorData` → `.unexpectedResponse` без запису.
6. **Перенесено з 1.3 (Info 6): глибина вкладеності JSON** (`JSONValue.swift`). Тепер гостьова відповідь розбирається автоматично на кожній появі гостьового екрана, без входу. Межа довіри та сама: атакувальником має бути Google або MITM з довіреним CA. Виправлення те саме, що в 1.2/1.3.
7. **Кожен `InnerTubeClient` створює `URLSession` з делегатом і ніколи не викликає `invalidate`** (`InnerTubeClient.swift:23-29`, `GuestModel.swift:9`).
   - Кожна поява `GuestView` (наприклад, після кожного виходу) додає ще одну сесію, яка живе до кінця процесу.
   - Це лише витік пам'яті. Сесії ефемерні й окремі, тож спільного стану між гостем і акаунтом він не створює.
   - Шаблон з 1.2 (`AccountModel`). **Виправлення:** спільний клієнт через DI в 4.1 (R2), або `session.finishTasksAndInvalidate()` у `deinit`, якщо клієнти лишаються поштучними.
8. **Точність документів.**
   - `docs/02` §5.1 (`:164-166`), §6 п.1 (`:200-202`, з уточненням з Low 1) і §6 п.5 (`:214-215`) відповідають коду. `docs/05` ризик №12 (`:18`) точний: реклама для гостей прийнята, не блокується. `docs/06` 1.4 не позначено, це робить фаза документації.
   - Необов'язкові уточнення:
     - у §5.1 додати «validated: 1–512 chars of `A–Z a–z 0–9 - _ % =`; never sent on authorized requests, and authorized responses never set it»;
     - у `docs/05` §2.4 (`:33-38`) додати рядок: «Cancelling sign-in wipes the web view store (not the Keychain). After "Continue without signing in" the web view store still holds the live Google session while the app behaves as a guest».

## Зведення за severity

| Severity | Кількість | Що далі |
|---|---|---|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 1 | M1: `guard !isSigningOut else { return false }` на початку `AuthSession.completeSignIn` (`AuthSession.swift:110`). Рекомендовано включити у fix pass |
| Low | 1 | L1: розсинхрон T6 + Cancel; переписати примітку 3.1 (`docs/06-backlog.md:46`) і уточнити `docs/02:202`. Документація, для fix pass або фази документації; кодова альтернатива потребує рішення користувача |
| Info | 8 | поза скоупом. Info 1 і Info 4 — правки документів (разом з L1); решта — для 2.1 / 4.1 |
