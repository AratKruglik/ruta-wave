# Business Analysis: Guest mode (backlog 1.4)

## Executive summary

Додаток більше не змушує входити в Google під час запуску. Без сесії в Keychain він відкривається в **гостьовому режимі**. Вхід стає необов'язковою кнопкою, а `InnerTubeClient` отримує шлях запитів без облікових даних: без `Cookie`, `Authorization` і `X-Goog-AuthUser`, з `X-Goog-Visitor-Id`, щойно відомий `visitorData`.

Це фундамент. UI перегляду, пошуку й відтворення ще немає (2.2+, 3.x, 4.x). Тому видимий доказ мінімальний: гостьовий екран показує статус одного неавтентифікованого запиту. Також фіксується одне правило «чи користувач увійшов» для наступних етапів.

## Джерела, на які спирається аналіз

| Що | Звідки |
|---|---|
| Поточний потік: `.signedOut` → `SignInView`, `.signedIn` → `AccountView`, `.keychainUnavailable` → «Try again» | `App/TunewaveApp.swift` |
| Стан і переходи сесії, порядок очищення WebKit → Keychain | `Packages/Auth/Sources/Auth/AuthSession.swift` (`restore`, `signOut`, `completeSignIn`) |
| Вибір URL входу через `isAddingAccount`; `isSignInActive` вважає `.signedOut` активним входом | `Packages/Auth/Sources/Auth/SignInView.swift` |
| Будь-який запит підписується; без `SAPISID` кидається `missingSAPISID` | `Packages/InnerTube/Sources/InnerTube/InnerTubeRequest.swift` (`signed`) |
| Ephemeral `URLSession`: `httpCookieStorage = nil`, `httpShouldSetCookies = false`, редиректи відхиляються | `Packages/InnerTube/Sources/InnerTube/InnerTubeClient.swift` |
| Кожна модель створює власний `InnerTubeClient()` | `App/AccountModel.swift` |
| Ризик №12: гості чують рекламу, вона не блокується | `docs/05-risks-and-scope.md` |
| 2.1, 4.1 і 4.5 мають працювати для гостей | `docs/06-backlog.md` |
| Заголовки авторизованого запиту, endpoints | `docs/02-architecture.md` §5.1–5.2 |

Як інші проєкти працюють з гостьовими (неавтентифікованими) запитами:

- **ytmusicapi** без заголовка `X-Goog-Visitor-Id` завантажує HTML music.youtube.com і бере `VISITOR_DATA` з `ytcfg.set(...)`. Потім шле це значення **тільки в заголовку** `X-Goog-Visitor-Id`, у `context` тіла його немає. Контекст `WEB_REMIX` складається з `clientName` і `clientVersion` (`helpers.get_visitor_id`, `initialize_context`) [1][2].
- **youtubei.js** за замовчуванням бере visitor data з `https://www.youtube.com/sw.js_data`, а якщо не вдалося, генерує локально (protobuf від випадкового id і часу). Значення шле в тілі `context.client.visitorData`, а заголовок `X-Goog-Visitor-Id` ставить на запит `config`. Також є опція `visitor_data` для сталого значення, «щоб YouTube підлаштовував вміст для неавтентифікованої сесії» [3][4].
- **yt-dlp / youtube-dl** беруть visitor data в такому порядку: значення користувача, `ytcfg.VISITOR_DATA`, `INNERTUBE_CONTEXT.client.visitorData`, `responseContext.visitorData`. Значення шлють у `X-Goog-Visitor-Id`. Гайд PO Token: logged-out сесія прив'язана до Visitor ID; той самий ідентифікатор живе в cookie `VISITOR_INFO1_LIVE` [5][6]. **[вторинне джерело, не звірено з поточним yt-dlp]**
- **pear-desktop** (оригінал) завантажує сам сайт у вікні (docs/01 §…, «The window loads the URL from the config»). Гостьовий режим там дає сам сайт, InnerTube-логіки для гостей немає. Позичати нічого.

**[не перевірено]** Чи повертає перший гостьовий `browse` без `X-Goog-Visitor-Id` статус 2xx і непорожній `responseContext.visitorData`. Це перевіряє проба нижче.

## Functional requirements

**FR1. Запуск без входу.** Після запуску вікно входу не відкривається автоматично. Без чинної сесії в Keychain додаток показує гостьовий екран.

**FR2. Стан «гість».** Наявний стан `AuthSession.State.signedOut` означає гостьовий режим. Перейменування не потрібне (див. OQ6).

**FR3. Необов'язковий вхід.**
- На гостьовому екрані є помітна кнопка «Sign in». Вона відкриває наявний `SignInView` поверх гостьового екрана, з кнопкою Cancel. Прецедент — аркуш «Add account» в `AccountView`.
- Гостьовий вхід завантажує `SignInRules.signInURL`, а не `addAccountURL`, і після успіху ставить `authUserIndex = 0`.
- Тому гостьовий вхід **не повинен** вмикати `isAddingAccount`: цей прапорець змінює URL і не дає скинути індекс.

**FR4. Завершення входу.** Коли `completeSignIn` успішний, стан стає `.signedIn`. Тоді додаток показує екран акаунта (як зараз), і аркуш входу зникає.

**FR5. Скасування входу.** Cancel, Esc або закриття аркуша повертають у гостьовий режим. Стан лишається `.signedOut`. Що робити з WebKit-даними, вирішує OQ1.

**FR6. Вихід веде в гостя.** Успішний `signOut()` повертає на гостьовий екран, а не на екран входу. Якщо Keychain не вдалося очистити, поведінка лишається як є: стан `.signedIn` і `signOutError`.

**FR7. Keychain недоступний.**
- Стан `.keychainUnavailable` лишається окремим екраном з «Try again».
- Він не стає гостем мовчки: користувач чекає, що він увійшов, і не має випадково опинитися серед реклами без бібліотеки.
- Додається дія «Continue without signing in». Вона переводить у гостьовий режим до кінця цього запуску і **не видаляє** запис у Keychain. Під час наступного запуску `restore()` пробує знову (див. OQ2).

**FR8. Гостьовий запит у `InnerTubeClient`.**
- Клієнт уміє виконати запит без облікових даних: без `Cookie`, `Authorization` і `X-Goog-AuthUser`.
- Заголовки `Origin`, `X-Origin`, `User-Agent` і `Content-Type`, а також тіло з `context.client` (`WEB_REMIX`, `clientVersion`, `hl`, `gl`) — такі самі, як в авторизованого запиту.
- `httpShouldHandleCookies = false`, як і зараз.
- На гостьовому шляху **немає входу для cookies**: ні параметра, ні доступу до `AuthSession`. Тому витік cookies неможливий структурно, а не лише через фільтр.

**FR9. `visitorData`.**
- Гостьовий запит шле `X-Goog-Visitor-Id`, щойно `visitorData` відомий. Тіло запиту не змінюється (OQ3).
- Джерело в 1.4 — `responseContext.visitorData` попередньої **гостьової** відповіді.
- Відповіді на авторизовані запити `visitorData` не задають. Інакше гостьова активність після виходу зв'язалася б з акаунтом.

**FR10. Валідація `visitorData` на межі довіри.** Значення приймається, тільки якщо воно:
- непорожнє;
- обмеженої довжини (порядку сотень символів);
- складається лише з символів токена: латиниця, цифри, `-`, `_`, `%`, `=`.

Інакше його ігнорують: попереднє відоме значення лишається, а запит іде без заголовка. Значення ніколи не логується.

**FR11. Час життя `visitorData`.**
- За замовчуванням (OQ4) значення живе тільки в пам'яті процесу і не зберігається на диску.
- Воно спільне для всіх гостьових запитів у межах запуску. Сьогодні кожна модель створює свій `InnerTubeClient()`, тож це вимога до спільного місця зберігання; як саме, вирішує розробник.
- Значення скидається, коли сесія переходить у `.signedIn`, і коли `signOut()` успішно завершується.

**FR12. Авторизований шлях не змінюється.**
- `accountMenu` і `accountSwitcher` будують ті самі заголовки, що й зараз.
- `X-Goog-Visitor-Id` в авторизованих запитах **немає**.
- Наявні тести 1.2/1.3 проходять без змін.

**FR13. Видимий доказ на гостьовому екрані.**
- Мінімальна заглушка до 4.1: назва додатка, кнопка «Sign in» і рядок статусу.
- Статус залежить від одного гостьового запиту `browse` з `browseId: FEmusic_home`. Цей запит знадобиться і в 2.2/4.2. Можливі стани:
  - «Connecting…»;
  - «Connected to YouTube Music as a guest», якщо відповідь 2xx, тіло — JSON і `responseContext.visitorData` непорожній;
  - «Couldn't reach YouTube Music» з кнопкою «Retry» на будь-яку помилку.
- Вміст сторінки не розбирається: парсери з'являться у 2.2.

**FR14. Єдине правило «чи увійшов».**
- В `AuthSession` є одне обчислюване місце. Воно повертає `true` **тільки** для `.signedIn`; для `.signedOut` і `.keychainUnavailable` — `false`.
- Наступні етапи беруть рішення «сховати дію або запропонувати вхід» лише звідти. Свої перевірки `case .signedIn` в UI вони не пишуть.
- Розробник фіксує правило в `docs/02-architecture.md` §6 як новий пункт. Туди ж іде абзац про гостьовий потік, а §6 п.1 («If the Keychain has no cookies, a window … is shown») оновлюється.

**FR15. Документація.**
- Оновити `docs/02` §5.1: додати заголовки гостьового запиту.
- Оновити `docs/02` §6: потік гість ↔ вхід ↔ вихід і правило з FR14.
- Відмітити 1.4 у `docs/06`.
- Додати до 3.1 у `docs/06` примітку безпеки про WebKit-залишки (див. Ризики).

## Non-functional requirements

- **Performance.**
  - Гостьовий екран з'являється так само швидко, як сьогодні екран входу.
  - Запит статусу асинхронний і не блокує UI.
  - Після Retry або повторної появи екрана відповідь не кешується (`urlCache = nil` уже стоїть).
- **Security / privacy.**
  - Гостьові запити ніколи не несуть cookies youtube.com/google.com, навіть якщо в Keychain є сесія. Це перевіряється тестом (AC6).
  - `Set-Cookie` з гостьових відповідей (наприклад, `VISITOR_INFO1_LIVE`, `YSC`) відкидається: їх ніде не зберігають.
  - `visitorData` — ідентифікатор відстеження. Його не логують, не показують в UI, у фікстурах він синтетичний.
- **Compliance.** Реклама для гостей не блокується і не пропускається (ризик №12, ухвалено). Обхід PoToken не потрібен: відтворення йде через web view (docs/02 §3).
- **Accessibility.** Кнопка «Sign in», «Retry» і рядок статусу мають зрозумілі VoiceOver-мітки. Статус оголошується як текст, а не тільки кольором чи іконкою.
- **Тестованість.** Логіку збирання гостьового запиту й валідації `visitorData` покривають unit-тести без мережі.

## Стани застосунку і переходи

«Стан» тут — `AuthSession.state` плюс видимий екран. «Signing in» — це не новий стан `AuthSession`, а показаний аркуш входу поверх гостя.

| # | Вихідний стан | Подія | Наступний стан / екран | Що зберігається |
|---|---|---|---|---|
| T1 | запуск | Keychain містить чинні cookies | `.signedIn` → екран акаунта | без змін |
| T2 | запуск | Keychain порожній | `.signedOut` → гостьовий екран | — |
| T3 | запуск | у Keychain прострочені або пошкоджені дані | `restore()` видаляє запис, `authUserIndex = 0` → гостьовий екран, без автоматичного входу (OQ5 про повідомлення) | запис Keychain видалено; WebKit не чиститься (Ризик R1) |
| T4 | запуск | `keychain.read()` кидає помилку | `.keychainUnavailable` → екран «Couldn't access the saved session»: «Try again» і «Continue without signing in» | нічого не видаляється |
| T5 | `.keychainUnavailable` | «Try again» | повтор `restore()` → T1/T2/T3/T4 | — |
| T6 | `.keychainUnavailable` | «Continue without signing in» | гостьовий екран до кінця запуску; правило FR14 повертає `false` | Keychain не чіпаємо |
| T7 | гість | «Sign in» | signing in: аркуш `SignInView` з `signInURL` | — |
| T8 | signing in | вхід успішний, Keychain записано | `.signedIn`, `authUserIndex = 0`, аркуш зникає → екран акаунта; гостьовий `visitorData` скинуто | cookies в Keychain |
| T9 | signing in | Keychain не записався (`signInError`) | стан лишається `.signedOut`, у `SignInView` оверлей «Couldn't save your session / Try again»; далі Try again → T8/T9 або Cancel → T10 | у WebKit можуть лишитися cookies Google (R1) |
| T10 | signing in | Cancel / Esc / закриття аркуша | гостьовий екран; за OQ1 очищається WebKit-сховище | за OQ1 — нічого |
| T11 | signing in | збій завантаження сторінки входу | наявний оверлей «Couldn't load the sign-in page / Reload»; Cancel → T10 | — |
| T12 | `.signedIn` | «Sign out», успіх | `.signedOut` → гостьовий екран, `visitorData` скинуто | Keychain і WebKit очищено (як зараз) |
| T13 | `.signedIn` | «Sign out», помилка видалення з Keychain | лишається `.signedIn` + «Couldn't clear the saved session» (як зараз) | WebKit уже очищено |
| T14 | signing in | вихід з додатка з відкритим аркушем | наступний запуск → T2 (або T1, якщо Keychain встиг записатися) | — |
| T15 | гість | вихід з додатка | наступний запуск → T2; новий `visitorData` (OQ4) | — |

Множинні акаунти (1.3) не змінюються. «Add account» і перемикання існують тільки в `.signedIn`.

## User stories (Gherkin)

### Story 1: Запуск без входу
**As a** новий користувач
**I want** відкрити додаток і не входити в Google
**So that** я можу слухати музику без акаунта

**Acceptance criteria:**
- **AC1.** Given у Keychain немає сесії, When додаток запускається, Then показується гостьовий екран з кнопкою «Sign in», і вікно входу не відкривається.
- **AC2.** Given у Keychain прострочена або пошкоджена сесія, When додаток запускається, Then запис у Keychain видаляється, `authUserIndex` дорівнює 0, і показується гостьовий екран.
- **AC3.** Given у Keychain чинна сесія, When додаток запускається, Then показується екран акаунта, як в 1.3.

### Story 2: Гостьовий запит працює
**As a** гість
**I want** бачити, що додаток дістається до YouTube Music без входу
**So that** я знаю, що гостьовий режим живий

**Acceptance criteria:**
- **AC4.** Given гостьовий екран, When він з'являється, Then виконується рівно один гостьовий `browse` `FEmusic_home`. Статус спершу «Connecting…», а після відповіді 2xx з непорожнім `responseContext.visitorData` — «Connected to YouTube Music as a guest».
- **AC5.** Given запит завершився мережевою помилкою, не-2xx, не-JSON або без `visitorData`, Then показується «Couldn't reach YouTube Music» і «Retry», а Retry повторює запит.
- **AC6 (unit).** Given в `AuthSession`/Keychain є сесія з `SAPISID`, When будується гостьовий запит, Then у ньому немає заголовків `Cookie`, `Authorization` і `X-Goog-AuthUser`, `httpShouldHandleCookies == false`, а `Origin`, `X-Origin` і `User-Agent` присутні.
- **AC7 (unit).** Given `visitorData` ще невідомий, Then гостьовий запит без `X-Goog-Visitor-Id`. Given гостьова відповідь містила валідний `responseContext.visitorData`, Then наступний гостьовий запит несе `X-Goog-Visitor-Id` з тим самим значенням (синтетичним у тесті).
- **AC8 (unit).** Given `visitorData` у відповіді порожній, задовгий або містить символи поза дозволеним набором (наприклад, CR/LF чи пробіл), Then він ігнорується, і попереднє відоме значення не перезаписується.
- **AC9 (unit).** Given відомий гостьовий `visitorData`, When будуються `accountMenu` або `accountSwitcher`, Then у них немає `X-Goog-Visitor-Id`, а решта заголовків збігається з 1.3. Наявні тести 1.2/1.3 зелені без змін.
- **AC10 (unit).** Given авторизована відповідь містить `responseContext.visitorData`, Then гостьовий `visitorData` не змінюється.

### Story 3: Вхід за бажанням
**As a** гість
**I want** увійти, коли мені потрібна бібліотека або Premium без реклами
**So that** я отримую свій акаунт без перезапуску

**Acceptance criteria:**
- **AC11.** Given гість, When натискаю «Sign in», Then відкривається аркуш з `SignInView` на `SignInRules.signInURL` (не AddSession) і з кнопкою Cancel.
- **AC12.** Given аркуш входу, When вхід завершено, Then стан `.signedIn`, `authUserIndex == 0`, аркуш закрито, і видно екран акаунта з ім'ям і аватаром.
- **AC13.** Given аркуш входу, When натискаю Cancel або Esc, Then я на гостьовому екрані, стан `.signedOut`, і статус гостьового запиту показується знову. Додатково, якщо OQ1 прийнято: сховище `WKWebsiteDataStore.default()` очищене.
- **AC14.** Given у WebKit вхід успішний, але запис у Keychain не вдався, Then у `SignInView` показується «Couldn't save your session». Стан лишається гостьовим, Cancel повертає на гостьовий екран, а «Try again» повторює запис.

### Story 4: Вихід повертає в гостя
**As a** користувач, що увійшов
**I want** вийти й лишитися в додатку як гість
**So that** я можу слухати далі без акаунта

**Acceptance criteria:**
- **AC15.** Given `.signedIn`, When «Sign out» успішний, Then показується гостьовий екран (не вікно входу), а наступний гостьовий запит іде без `X-Goog-Visitor-Id`, отриманого до входу.
- **AC16.** Given видалення з Keychain не вдалося, Then лишається екран акаунта з «Couldn't clear the saved session», як в 1.3.
- **AC17.** Given після виходу додаток перезапущено, Then показується гостьовий екран.

### Story 5: Keychain недоступний і правило для наступних етапів
**As a** розробник наступних етапів (і користувач із заблокованим Keychain)
**I want** одне джерело правди «чи увійшов» і зрозумілий вихід зі збою Keychain
**So that** дії лише для акаунта поводяться однаково, а збій Keychain не блокує додаток

**Acceptance criteria:**
- **AC18.** Given `keychain.read()` кидає помилку, Then показуються «Couldn't access the saved session», «Try again» і «Continue without signing in».
- **AC19.** Given AC18, When «Continue without signing in», Then показується гостьовий екран, а запис Keychain не видалено: тест-подвійник Keychain не отримав `delete`.
- **AC20 (unit).** Правило «чи увійшов» дає `true` тільки для `.signedIn` і `false` для `.signedOut` та `.keychainUnavailable`.
- **AC21.** `docs/02-architecture.md` §6 описує гостьовий потік і називає це правило єдиним джерелом для прихованих дій та пропозиції увійти. §5.1 перелічує заголовки гостьового запиту.
- **AC22.** У логах, тестах і фікстурах немає cookies, `Authorization`, справжнього `visitorData` чи інших персональних даних. Значення в тестах синтетичні, наприклад `"CgtTWU5USEVUSUMxMjM%3D"`-подібні рядки, згенеровані вручну.

**Ручна перевірка (⛔, користувач):** чистий запуск → гість «Connected» → Sign in → акаунт → Sign out → гість «Connected» → Sign in → Cancel → гість.

## Data model sketch

- **`AuthSession.State`** — без нових case'ів (`signedOut` = гість). Додається одне обчислюване правило «чи увійшов» (FR14) і дія «продовжити як гість» для `.keychainUnavailable` (FR7). Форму визначає розробник.
- **Гостьовий `visitorData`** — рядок-токен. Живе в пам'яті протягом запуску, одне значення на процес, і скидається на T8/T12. На диск не пишеться (OQ4).
- **Статус гостьового підключення** — модель екрана з трьома станами: connecting / connected / failed. Узгоджується з принципом docs/02 §7 «кожен екран має `@Observable` модель».

## API contract sketch

- **Гостьовий** `POST https://music.youtube.com/youtubei/v1/browse?prettyPrint=false`
  - Заголовки: `Content-Type: application/json`, `Origin` і `X-Origin: https://music.youtube.com`, `User-Agent` (Safari-рядок, як зараз), `X-Goog-Visitor-Id: <visitorData>` (якщо відомий).
  - Не надсилати: `Cookie`, `Authorization`, `X-Goog-AuthUser`.
  - Тіло: `{"browseId":"FEmusic_home","context":{"client":{"clientName":"WEB_REMIX","clientVersion":"<constant>","hl":"…","gl":"…"}}}`.
  - Відповідь: 2xx JSON. Береться тільки `responseContext.visitorData`. **[не перевірено для гостя]**
- Авторизовані `account/account_menu` і `GET /getAccountSwitcherEndpoint` не змінюються.

### Проба для оркестратора (структура без значень; агенти не викликають live endpoints)

Запускати без cookies. Друкувати тільки структуру, довжини й булеві значення, **ніколи** не самі значення.

- **A.** Гостьовий запит вище без `X-Goog-Visitor-Id`. Вивести:
  - HTTP-статус;
  - список ключів верхнього рівня;
  - чи існує `responseContext.visitorData` і його довжину;
  - символи, з яких він складається (класи: `[A-Za-z0-9_-]`, `%`, `=`, інші так/ні);
  - **лише імена** cookies з `Set-Cookie`.
- **B.** Той самий запит з `X-Goog-Visitor-Id`, взятим з A. Вивести статус і чи `responseContext.visitorData` у B дорівнює значенню з A (true/false).
- **C (опційно).** Як B, але значення в `context.client.visitorData` замість заголовка. Вивести статус і рівність (true/false).
- **D (опційно).** Як A, але з `gl` країни ЄЕЗ (наприклад, `DE`). Вивести статус і чи з'являються ключі, схожі на consent (true/false).

Що вирішує проба:
- A без 2xx або без `visitorData` → FR13 треба інше джерело (див. OQ7);
- B рівне → `visitorData` справді приймається з заголовка;
- C ≠ B → відповідь на OQ3;
- D → ризик R4.

## Edge cases & error scenarios

- **E1.** Сесія є в Keychain, але гостьовий запит будується (наприклад, гостьова модель живе під час переходу T8). Cookies не потрапляють у запит структурно (FR8, AC6).
- **E2.** Вхід завершився, поки гостьовий запит ще летить. Його результат більше не показується: екран змінився. Отриманий `visitorData` не має пережити T8. Тут можлива гонка: відповідь приходить після скидання. Розробник гарантує, що значення, отримане після переходу в `.signedIn`, не зберігається.
- **E3.** Два гостьові запити паралельно, коли `visitorData` ще невідомий. Обидва йдуть без заголовка, і кожна відповідь може встановити значення. Прийнятно: сайт і так видає нове значення; береться будь-яке валідне.
- **E4.** `responseContext.visitorData` змінився між відповідями. Береться останнє валідне (так робить сайт). **[не перевірено, проба B]**
- **E5.** Невалідний `visitorData`: CR/LF, юнікод, порожній, дуже довгий. Його ігнорують (AC8), і ін'єкції заголовка немає.
- **E6.** Немає мережі, таймаут, 4xx/5xx або редирект (редиректи вже відхиляються) → статус «Couldn't reach…» + Retry. Помилку гостьового запиту **не можна** трактувати як «потрібен вхід» (сигнал для 2.1).
- **E7.** Cancel у середині 2FA, коли Google уже поставив частину cookies у `WKWebsiteDataStore.default()` → R1, OQ1.
- **E8.** T9 + Cancel. Повна сесія Google є в WebKit, але не в Keychain. Наступне «Sign in» завершиться миттєво без форми (наявна поведінка `SignInView`), що може здивувати користувача. За OQ1 це закривається очищенням WebKit на Cancel.
- **E9.** Користувач натискає «Sign in» двічі або «Sign out» під час виходу. Відкривається один аркуш, а наявні `isSigningOut`-guard'и лишаються.
- **E10.** `.keychainUnavailable` → «Continue without signing in» → «Sign in». Запис у Keychain теж може не вдатися, тоді T9 і «Couldn't save your session». Якщо запис удався, нова сесія перезаписує старий недоступний запис. Це прийнятно: користувач сам увійшов.
- **E11.** Регіон ЄЕЗ: гостьові відповіді можуть містити вимогу згоди (consent). **[не перевірено]** Проба D. Для 1.4 достатньо статусу «Connected», якщо 2xx + `visitorData`.
- **E12.** Застарілий `clientVersion` (константа з 1.2) може дати гостю інший результат, ніж авторизованому. Це те саме обмеження, яке 2.1 знімає page discovery.

## Risks & dependencies

- **R1. Залишки WebKit по дорозі в гостя.**
  - `signOut()` тримає інваріант: «порожній Keychain поруч із живими cookies google.com — неприпустимо» (коментар у `AuthSession.signOut`).
  - Гостьовий режим додає нові шляхи його порушити: Cancel посеред входу (E7), T9 + Cancel (E8).
  - Наявний шлях T3: `restore()` видаляє пошкоджений або прострочений запис, але WebKit не чистить.
  - В 1.4 це не впливає на запити InnerTube: їхня сесія ephemeral і без cookie storage.
  - Але плеєр 3.1 використає `WKWebsiteDataStore.default()` (docs/02 §4.1). Тоді він гратиме як авторизований, поки додаток вважає користувача гостем.
  - Пропозиція:
    - Cancel чистить WebKit (OQ1);
    - для T3 і загалом додати в `docs/06` примітку безпеки до 3.1: «у гостьовому стані сховище web view не містить сесії Google; перевірити й очистити на старті плеєра».
- **R2. Розкидані екземпляри `InnerTubeClient`.** Зараз `AccountModel` створює власний клієнт. Спільний `visitorData` (FR11) потребує одного місця на процес. Це мінімальний борг 1.4. Повноцінний DI клієнта — у 4.1.
- **R3. Залежність від 2.1.**
  - Сторінкове джерело `ytcfg.VISITOR_DATA` (як у ytmusicapi) природно належить 2.1: там однаково завантажують сторінку заради `INNERTUBE_CLIENT_VERSION`.
  - 2.1 також має **не** вмикати сценарій «401 → вхід» для гостьових запитів.
- **R4. Consent у ЄЕЗ / bot-check для гостей.** Можлива деградація гостьових відповідей. Не перевірено; проба D. Interstitial згоди в player web view — це 3.1.
- **R5. Реклама** для гостей — ризик №12, ухвалено. 1.4 нічого не відтворює.
- **Споживачі правила FR14 (майбутні етапи):**
  - 2.1 — без «401 → вхід» для гостя;
  - 2.4 — мутації like/playlist тільки для тих, хто увійшов;
  - 3.2 — `setLike`;
  - 4.1 — кнопка «Sign in» у shell, Library в sidebar;
  - 4.5 — Library: пропозиція увійти;
  - 4.6 — пункти контекстних меню «Like», «Add to playlist».
- **Залежить від:** 1.2 (клієнт, `InnerTubeRequest`), 1.3 (аркуш входу, `authUserIndex`). Обидва змерджено.

## Open questions for stakeholders

1. **OQ1. Чи очищати `WKWebsiteDataStore.default()` при Cancel гостьового входу?**
   - *Рекомендація: так*, тим самим очищенням, що й `signOut()`, але без Keychain. Тоді часткова сесія Google не лишається на диску (E7, E8, R1).
   - Мінус: якщо Cancel натиснуто після T9, вдалий вхід у WebKit пропадає, і доведеться входити заново.
2. **OQ2. Що робити, коли Keychain недоступний?**
   - *Рекомендація:* окремий екран з «Try again» і «Continue without signing in» лише на цей запуск, нічого не видаляючи (FR7).
   - Альтернатива — мовчки гість. Відхилено: користувач не дізнається, що його сесія «зникла».
3. **OQ3. Де передавати `visitorData`: тільки в заголовку `X-Goog-Visitor-Id` чи ще й у `context.client.visitorData`?**
   - *Рекомендація: тільки заголовок.* Так у брифі й у ytmusicapi [2].
   - Тіло — лише якщо проба C покаже, що заголовок не приймається.
4. **OQ4. Чи зберігати `visitorData` між запусками?**
   - *Рекомендація: ні*, тільки пам'ять. Значення скидається на вхід і вихід, тож гостьові сесії до входу й після виходу не пов'язані між собою, а на диску немає ідентифікатора відстеження.
   - Альтернатива — `UserDefaults`, щоб гостьовий Home був персоналізований між запусками (як опція `visitor_data` у youtubei.js [4]). Можна переглянути у 4.2.
5. **OQ5. Повідомляти, що сесія закінчилась (T3)?**
   - *Рекомендація: ні в 1.4.* Гостьовий екран і так показує «Sign in».
   - Повідомлення «Session expired» доречне разом з обробкою 401 у 2.1.
6. **OQ6. Перейменувати `State.signedOut` на `.guest`?**
   - *Рекомендація: ні.* Змінився б API Auth і зачепив би `SignInView` та тести без поведінкової користі. Значення фіксується в docs/02.
7. **OQ7. Якщо проба A не дасть 2xx + `visitorData` без попереднього значення, звідки брати перше значення?**
   - *Рекомендація:* перенести в 1.4 завантаження HTML music.youtube.com і `ytcfg.VISITOR_DATA` (як ytmusicapi [1]).
   - Не генерувати локально (youtubei.js [3]): це наслідування внутрішнього формату Google.

## Deferred (поза 1.4)

| Що | Куди |
|---|---|
| `visitorData` зі сторінки (`ytcfg`), обробка 401 без входу для гостей | 2.1 |
| Парсинг Home, показ полиць для гостя | 2.2 / 4.2 |
| Мутації тільки для тих, хто увійшов | 2.4 |
| Гарантія «немає сесії Google у web view в гостьовому стані», consent interstitial, гостьова реклама в плеєрі | 3.1 (примітка безпеки в docs/06) |
| `setLike` тільки для тих, хто увійшов | 3.2 |
| Shell з кнопкою «Sign in», спільний `InnerTubeClient` через DI | 4.1 |
| Library → пропозиція увійти | 4.5 |
| Контекстні меню з діями для акаунта | 4.6 |
| Блокування реклами | відхилено (ризик №12) |

## Estimated complexity

**small–medium.** Зміни такі:
- гостьовий шлях запиту в `InnerTubeRequest`/`InnerTubeClient` плюс валідація й спільне зберігання `visitorData`;
- одне правило й одна дія в `AuthSession`;
- гостьовий екран-заглушка з аркушем входу;
- гілка `TunewaveApp` і дія на `.keychainUnavailable`;
- unit-тести й оновлення docs/02, docs/06.

Основний ризик — не обсяг, а неперевірена поведінка live-сервісу (проба A–D).

## Sources

1. ytmusicapi `helpers.get_visitor_id` / `initialize_context`: https://github.com/sigma67/ytmusicapi/blob/main/ytmusicapi/helpers.py
2. ytmusicapi API reference (`get_visitor_id`): https://ytmusicapi.readthedocs.io/en/latest/reference/api/ytmusicapi.html
3. youtubei.js `Session.ts` (`sw.js_data`, `encodeVisitorData`, `context.client.visitorData`, `X-Goog-Visitor-Id` на `config`): https://github.com/LuanRT/YouTube.js/blob/main/src/core/Session.ts
4. youtubei.js `SessionOptions.visitor_data`: https://www.ytjs.dev/api/type-aliases/SessionOptions
5. yt-dlp PO Token Guide (logged-out сесія прив'язана до Visitor ID; `VISITOR_INFO1_LIVE` / `visitorData` / `ytcfg.VISITOR_DATA`): https://notabug.org/yt-dlp/yt-dlp-wiki/src/master/PO%20Token%20Guide.md
6. youtube-dl mirror commit «Use X-Goog-Visitor-Id» / `_extract_visitor_data` (вторинне джерело): https://gitea.smoothnet.org/nhyatt/youtube-dl/commit/21fff051217d1c14a7d50fa752052eadbcafee4e

## Результати проби A–D (оркестратор, 2026-11-18)

Запити йшли без cookies на `POST music.youtube.com/youtubei/v1/browse` з `browseId: FEmusic_home` та клієнтом `WEB_REMIX` `1.20261115.14.00`. Друкувались лише структура, довжини й булеві значення.

- **A** (без `X-Goog-Visitor-Id`):
  - HTTP 200;
  - ключі верхнього рівня: `background`, `contents`, `maxAgeStoreSeconds`, `responseContext`, `trackingParams`;
  - `responseContext.visitorData` є, довжина 48;
  - символи лише URL-safe і `%`, без `=` та інших;
  - заголовків `Set-Cookie` немає;
  - 2 полиці `musicCarouselShelfRenderer`.
- **B** (з `X-Goog-Visitor-Id` = значення з A): HTTP 200. `visitorData` у відповіді **відрізняється** від A.
- **C** (`context.client.visitorData` = значення з A): HTTP 200. `visitorData` у відповіді теж **відрізняється** від A.
- **D** (`gl: DE`): HTTP 200, ознак consent немає, 2 полиці.

**Висновки:**
- Гостьовий `browse` працює без попереднього `visitorData`, тож OQ7 знімається: перше значення береться з першої відповіді.
- Сервер щоразу видає нове `visitorData`. Діє правило E4: беремо останнє валідне.
- Чи «приймається» заголовок, з відповіді не видно. Залишаємо заголовок, як у сайту. OQ3: лише заголовок, без тіла.
- Ризик R4 (consent у ЄЕЗ) для `browse` не підтвердився.
- Видимий доказ «Connected» реальний: гостьова головна має непорожні полиці.

## Відповіді користувача на відкриті питання (2026-11-18)

1. **OQ1:** так. Cancel гостьового входу чистить `WKWebsiteDataStore.default()` так само, як `signOut()`, але без Keychain.
2. **OQ2:** екран «Couldn't access the saved session» з кнопками «Try again» і «Continue without signing in». Друга діє лише на цей запуск і нічого не видаляє.
3. **OQ3:** лише заголовок `X-Goog-Visitor-Id`.
4. **OQ4:** ні. `visitorData` живе тільки в пам'яті й скидається при вході та виході.
5. **OQ5:** ні в 1.4, перенесено в 2.1.
6. **OQ6:** ні, `.signedOut` лишається, а його значення фіксується в docs/02.
7. **OQ7:** знято пробою A, перше значення приходить з першої відповіді.
