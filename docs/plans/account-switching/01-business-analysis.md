# Бізнес-аналіз: список акаунтів і перемикання між Google-акаунтами сесії (backlog 1.3)

## Executive summary

Екран акаунта, зроблений у 1.2, показує лише активний акаунт: `account/accounts_list` з тілом `CHANNEL_SWITCHER` і контекстом `WEB_REMIX` повернув тільки `responseContext` і `selectText`. У 1.3 треба знайти запит, який надійно перелічує Google-акаунти cookie-сесії разом з їхніми індексами `authuser`, додати список і перемикання через `AuthSession.authUserIndex` (з fallback FR15 на 0), після «Add account» лишатися на поточному акаунті й оновлювати список. Окремо замінюємо regex `isRegionalAccountsHost` на опублікований Google список доменів і дозволяємо на цих хостах лише шлях `/accounts/SetSID`.

Найбільша невизначеність: ще не перевірено, чи `X-Goog-AuthUser: 1` справді повертає **інший** акаунт (див. P1, AC2 і відкрите питання 1). Від цього залежить, чи вистачає моделі «перемикання = індекс у заголовку».

## Джерела

| Позначка | Джерело |
|---|---|
| [B] | `docs/plans/account-switching/_brief.md` |
| [BL] | `docs/06-backlog.md`, рядок 1.3 і security note для 1.3 |
| [BA2] | `docs/plans/innertube-core/01-business-analysis.md` (FR8, FR9, FR13, FR15, відповіді користувача) |
| [P2] | `docs/plans/innertube-core/02-development-plan.md`, D5 (дизайн `AccountListItem`, вилучений у fix pass 4) |
| [D2] | `docs/plans/innertube-core/02-development.md`, fix pass 3 і 4 |
| [Q2] | `docs/plans/innertube-core/03-qa.md`, розділ AC13 |
| [S2] | `docs/plans/innertube-core/04-security.md`: Medium 1 (M1), Low 3 (від'ємний `authuser`), Low 5 (проковтнутий збій списку), Info 5 (дублікати `id`), Info 6 (перемикання під час виходу) |
| [K] | `docs/05-risks-and-scope.md` §2 п.4 (два сховища), §4 #2 |
| [A] | `docs/02-architecture.md` §5.1 (транспорт, `X-Goog-AuthUser: 0`), §5.2 (таблиця ендпоінтів) |
| [YJ-AM] | youtubei.js, `AccountManager.getInfo(true)`: https://github.com/LuanRT/YouTube.js/blob/main/src/core/managers/AccountManager.ts |
| [YJ-AI] | youtubei.js, `AccountItem`: https://github.com/LuanRT/YouTube.js/blob/main/src/parser/classes/AccountItem.ts ; `AccountSectionList`: https://github.com/LuanRT/YouTube.js/blob/main/src/parser/classes/AccountSectionList.ts |
| [YJ-REQ] | youtubei.js, тип `GetAccountsListInnertubeRequest` (`callCircumstance`: `SUPPLEMENTAL_USER` або `SWITCHING_USERS_FULL`, `channelSwitcherQuery?`): https://www.ytjs.dev/api/type-aliases/GetAccountsListInnertubeRequest |
| [YJ-735] | YouTube.js issue #735 («account_index does not work», `/getAccountSwitcherEndpoint`): https://github.com/LuanRT/YouTube.js/issues/735 |
| [YTDLP] | yt-dlp, `yt_dlp/extractor/youtube/_base.py` (`SESSION_INDEX`, `DATASYNC_ID`, `responseContext.mainAppWebResponseContext.datasyncId`, розбиття за `\|\|`): https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/youtube/_base.py |
| [YM] | ytmusicapi, `ytmusic.py`: бренд-акаунт через `context.user.onBehalfOfUser`, без списку акаунтів: https://github.com/sigma67/ytmusicapi/blob/main/ytmusicapi/ytmusic.py |
| [NP] | NewPipe FAQ: вхід у Google-акаунт не підтримується: https://newpipe.net/FAQ/ |
| [CR] | Chromium `google_apis/gaia/gaia_auth_util.cc`, `ParseListAccountsData` (protobuf `ListAccountsResponse`): https://chromium.googlesource.com/chromium/src/+/main/google_apis/gaia/gaia_auth_util.cc |
| [GSD] | Список доменів Google: https://www.google.com/supported_domains (близько 250 записів через пробіл, з крапкою на початку: `.google.com .google.ad … .google.com.ua`; є `.google.co.uk`, `.google.de`, `.google.cat`; перевірено 2026-11-18) |

Позначки достовірності: **[verified-code]** означає, що це прочитано в коді зовнішнього проєкту; **[unverified]** означає, що поведінку на живому акаунті не перевіряли. Жоден агент не викликав живих ендпоінтів.

## Стан кодової бази (що є зараз)

- `Packages/InnerTube/Sources/InnerTube/InnerTubeClient.swift`: є лише `accountMenu(cookies:authUserIndex:)`. Метод `accountsList` і `AccountListItem.swift` прибрано у fix pass 4 [D2]. Дизайн парсера (рекурсивний пошук `accountItem`, індекс з `signinUrl`, відкидання `pageIdToken`) описано в [P2] D5, і його можна відновити.
- `InnerTubeRequest.make`: фіксований `origin = https://music.youtube.com`, `clientName: WEB_REMIX`, тіло `[String: String]`, лише метод `POST /youtubei/v1/<endpoint>`. Будь-який кандидат з іншим хостом, клієнтом чи методом (`GET`) змінює цей контракт (FR2 і FR3 з 1.2).
- `AccountInfo(accountMenu:)` читає лише `activeAccountHeaderRenderer`. `responseContext` не розбирається. Хелпери `text` і `lastThumbnailURL` (allowlist хостів аватарів) можна використати повторно.
- `App/AccountModel.swift`: стан `loading | loaded(AccountInfo) | failed`, без списку і без FR15. `App/AccountView.swift` перезавантажує екран через `.task(id: ReloadKey(index, attempt))`, а після закриття sheet «Add account» збільшує `attempt`.
- `AuthSession`: `authUserIndex` зберігається в `UserDefaults`. `completeSignIn` не скидає індекс під час add-account, `signOut()` і пошкоджений Keychain скидають його в 0. Сесія Keychain містить лише cookies `youtube.com`, а `google.com` є тільки у WebKit-сховищі [K].
- `SignInRules.isAllowedMainFrameNavigation`: точний allowlist плюс regex `accounts\.google\.(?:com\.|co\.)?[a-z]{2}` без перевірки шляху. Тести є в `Packages/Auth/Tests/AuthTests/SignInRulesTests.swift`: позитивні `.com.ua`, `.de`, `.co.uk` і негативні lookalike.
- Тестового таргета для `App/` немає: логіка FR15 і перегони в 1.2 автоматично не покриті [Q2].

## Як інші клієнти отримують список акаунтів (огляд)

| Клієнт | Що робить | Достовірність |
|---|---|---|
| youtubei.js | `getInfo(true)`: `getAccountsListInnertubeEndpoint` з `requestType: ACCOUNTS_LIST_REQUEST_TYPE_CHANNEL_SWITCHER` і `callCircumstance: SWITCHING_USERS_FULL`, **клієнт `WEB`** (не `WEB_REMIX`). Елементи `AccountItem` збираються з усієї відповіді: `accountName`, `accountPhoto`, `isSelected`, `isDisabled`, `hasChannel`, `serviceEndpoint`, `accountByline`, `channelHandle` [YJ-AM][YJ-AI]. Контейнер — `AccountSectionList.contents[] → AccountItemSection` | [verified-code]. Що цей запит повертає в 2026 році, не перевірено |
| YouTube.js #735 | `GET https://www.youtube.com/getAccountSwitcherEndpoint`, відповідь з 5-символьним XSSI-префіксом. Шлях: `actions[0].getMultiPageMenuAction.menu.multiPageMenuRenderer.sections[0].accountSectionListRenderer.contents[0].accountItemSectionRenderer.contents[].accountItem`. Індекс береться з **позиції в масиві**. У тому ж issue повідомлено, що `X-Goog-AuthUser` у їхньому випадку **не перемикав** акаунт, а `SESSION_INDEX` завжди 0 [YJ-735] | коментар в issue, [unverified]. Висновок «індекс = позиція» сумнівний |
| yt-dlp | Списку не будує. `X-Goog-AuthUser` бере з `SESSION_INDEX` у ytcfg (інакше 0), `X-Goog-PageId` — з `DELEGATED_SESSION_ID` або першої частини `datasyncId`. `datasyncId` читається з `responseContext.mainAppWebResponseContext.datasyncId` і має формат `<delegated>\|\|<user>` [YTDLP] | [verified-code] для клієнта `WEB`. Чи є це поле у відповідях `WEB_REMIX`, [unverified] |
| ytmusicapi | Списку не будує. Бренд-акаунт обирається через `context.user.onBehalfOfUser`, а активний акаунт читає `account_menu` [YM] | [verified-code] |
| NewPipe | Вхід у Google-акаунт не підтримує [NP] | FAQ |
| Chromium | `accounts.google.com/ListAccounts` у поточному коді розбирається як base64 protobuf `ListAccountsResponse`: `display_email`, `obfuscated_id`, `valid_session`, `signed_out` [CR]. Імені й аватара немає | [verified-code] |

**Висновок.** Жоден відкритий клієнт не перелічує акаунти через контекст `WEB_REMIX`. Найближчий робочий прецедент — те саме тіло `accounts_list`, яке ми вже пробували в 1.2, але з клієнтом `WEB`. Порожня відповідь із `selectText` у 1.2 узгоджується з гіпотезою, що сервер зрозумів запит, але для `WEB_REMIX` елементів не віддає **[unverified]**.

## Кандидати для discovery (ранжовано)

Спільні правила для всіх кандидатів: авторизаційні заголовки як у 1.2 (`Cookie` з Keychain, `SAPISIDHASH`, `X-Goog-AuthUser` = поточний індекс). `Origin` і `X-Origin` дорівнюють origin хоста запиту, і саме від нього рахується `SAPISIDHASH`.

| Ранг | Кандидат | Запит | Де шукати поля | Плюси / мінуси |
|---|---|---|---|---|
| **Pre-step P0** (може перекрити ранжування) | Що надсилає сам `music.youtube.com` | (1) запит, який сайт шле після кліку «Switch account» в аватар-меню; (2) ендпоінт, який рекламує пункт «Switch account» у відповіді `account_menu` (`…multiPageMenuRenderer.sections[].…items[].…navigationEndpoint` або `serviceEndpoint`, назва ключа `*Endpoint`) | залежить від результату | Це те, що робить офіційний клієнт. Якщо P0 покаже робочий запит зі списком, він стає primary замість C1 |
| **C1 — PRIMARY** | `accounts_list`, клієнт `WEB` | `POST /youtubei/v1/account/accounts_list?prettyPrint=false`, тіло `context.client{clientName: "WEB", clientVersion: <поточна WEB>, hl, gl}`, `requestType: "ACCOUNTS_LIST_REQUEST_TYPE_CHANNEL_SWITCHER"`, `callCircumstance: "SWITCHING_USERS_FULL"`. Спершу хост `music.youtube.com`, потім `www.youtube.com` | Усі `accountItem` у відповіді, очікуваний контейнер `actions[].getMultiPageMenuAction.menu.multiPageMenuRenderer.sections[].accountSectionListRenderer.contents[].accountItemSectionRenderer.contents[]`. Поля: **ім'я** — `accountName`; **byline** — `accountByline` (ймовірно email) або `channelHandle`; **аватар** — `accountPhoto.thumbnails[]`; **індекс** — параметр `authuser` у `serviceEndpoint.selectActiveIdentityEndpoint.supportedTokens[].accountSigninToken.signinUrl`; **вибраний** — `isSelected`; **brand-маркер** — `supportedTokens[].pageIdToken` | Прецедент [YJ-AM]; той самий транспорт `POST /youtubei`, а від провалу 1.2 відрізняється лише клієнтом. Мінуси: потрібна константа `clientVersion` для `WEB` (джерело див. P2), а для `www.youtube.com` — новий хост і origin (зміна FR3 з 1.2). Шлях до індексу [unverified] |
| **C2** (альтернатива primary) | `getAccountSwitcherEndpoint` | `GET /getAccountSwitcherEndpoint` (не `youtubei`), спершу на `music.youtube.com`, потім на `www.youtube.com`. Відповідь з XSSI-префіксом `)]}'` | `actions[0].getMultiPageMenuAction.menu.multiPageMenuRenderer.sections[0].accountSectionListRenderer.contents[*].accountItemSectionRenderer.contents[].accountItem`, ті самі поля, що в C1 | Відомий шлях [YJ-735], `clientVersion` не потрібен. Мінуси: інший метод і формат, легасі-ендпоінт, який можуть вимкнути. Індекс за позицією не приймаємо, лише з `signinUrl` |
| **C3 — FALLBACK** | Зондування `account_menu` | `POST …/account/account_menu` з `X-Goog-AuthUser` = 0, 1, 2… Зупинка: не-2xx, немає `activeAccountHeaderRenderer`, повтор уже баченого акаунта (див. «ключ ідентичності») або ліміт (10 [unverified], стільки Google-акаунтів дозволяє одна сесія) | Ім'я, handle й аватар як в `AccountInfo`. Індекс — номер зонда. **Ключ ідентичності**: `responseContext.mainAppWebResponseContext.datasyncId` [YTDLP], якщо P1 покаже, що він є; інакше трійка (ім'я, handle, URL аватара). `isSelected` = збіг з поточним `authUserIndex` | Будується лише на перевіреній поведінці 1.2, без нового ендпоінта й хоста. Мінуси: до 10 запитів на кожне відкриття; поведінка для індексу поза межами невідома (помилка чи тихий повтор акаунта 0); email немає; збіг трійки для двох різних акаунтів малоймовірний, але можливий |
| C4 (відхилено) | `accounts.google.com/ListAccounts` | — | — | Потребує cookies `google.com`, яких у Keychain немає [K]; розширює зону облікових даних до всього Google-акаунта; формат protobuf, без імені й аватара [CR]. **Не для 1.3** |
| C5 (відхилено) | ytcfg сторінки (`SESSION_INDEX`, `DATASYNC_ID`) | — | — | Дає лише поточний індекс, а не список [YTDLP]; [YJ-735] повідомляє, що `SESSION_INDEX` завжди 0 |

**Рекомендація.** **Primary — C1** (`accounts_list` з клієнтом `WEB`). **Fallback — C3** (зондування `account_menu`). P0 виконується першим і може замінити primary на запит, який реально шле `music.youtube.com`. C2 пробуємо, лише якщо C1 не дасть елементів на жодному хості. Усе це має сенс тільки тоді, коли P1 (AC2) підтвердить, що `X-Goog-AuthUser` перемикає акаунт: у кожному варіанті перемикання робиться саме через заголовок.

## Процедура верифікації (для оркестратора, debug-збірка з редагованою структурою)

**Правила редагування виводу (обов'язкові для всіх зондів):**

- Друкується дерево ключів з типами і довжинами масивів. Рядок виводиться як `<str len=N>`, число як `<num>`, bool — як є.
- Дослівно друкуються лише значення з allowlist: `requestType`, `callCircumstance`, `clientName`, `clientVersion`, `webPageType`, назви ключів `*Endpoint`, а також `apiUrl` або шлях URL, якщо він відповідає `^/[A-Za-z0-9_/]+$` (без query).
- Для кожного `accountItem` друкується: номер секції й позиція; `authuser` як `Int`, розібраний з `signinUrl` (або `absent`); хост `signinUrl`; `pageIdToken: present/absent`; `isSelected`, `isDisabled`, `hasChannel`; наявність (`true/false`) `accountName`, `accountByline`, `channelHandle`, `accountPhoto`.
- Порівняння ідентичності робляться в процесі, а друкуються лише як bool: спершу `datasyncIdPresent`, потім `datasyncIdEqualsIndex0` / `datasyncIdEqualsPrevious`, а також `nameEqualsIndex0`, `handleEqualsIndex0`, `avatarEqualsIndex0`. Самі значення ніколи не друкуються.
- Імена, handle, email, URL аватарів, `datasyncId`, cookies, `Authorization` і сирі тіла ніколи не друкуються. Вивід іде у scratch-файл поза репозиторієм. Debug-код у PR не потрапляє (відкрите питання 5).
- Перед запуском зондів у сесії мають бути рівно дві Google-сесії (поточний стан користувача).

| Зонд | Що робить | Що записати | Критерій |
|---|---|---|---|
| **P0a** (pre-step, вручну користувачем) | Користувач у **своєму** Safari з Web Inspector відкриває `music.youtube.com`, натискає аватар і «Switch account», дивиться вкладку Network | метод, шлях, назви ключів тіла, значення `requestType` / `callCircumstance` / `clientName` / `clientVersion`. Без cookies, заголовків авторизації, тіл відповіді | є запит, що повертає список → він стає primary |
| **P0b** (pre-step, debug-збірка) | Один `account_menu` (індекс 0), редагована структура `sections[]` | назви ключів `*Endpoint` пункту «Switch account» і їхні allowlist-поля | ендпоінт і тіло, які рекламує сам WEB_REMIX |
| **P1** (блокер, AC2) | `account_menu` з `X-Goog-AuthUser` = 0, 1, 2, 3 | для кожного: HTTP-статус, `activeAccountHeaderRenderer` є/немає, `datasyncIdPresent`, потім усі bool-порівняння з правил вище | **Індекс 1 відрізняється від 0** (за `datasyncId`, якщо він є, інакше за ім'ям або аватаром), тоді модель перемикання працює. Якщо 1 дорівнює 0 за всіма сигналами, зупиняємось (відкрите питання 1). Статус індексів 2 і 3 визначає умову зупинки C3, а `datasyncIdPresent` — ключ ідентичності C3 |
| **P2** (C1) | Передумова: поточна `clientVersion` для `WEB`. Береться з P0a або в debug-збірці з `INNERTUBE_CLIENT_VERSION` у ytcfg сторінки `www.youtube.com` (не персональні дані, друкується дослівно). Потім `accounts_list` з `WEB`, тіло вище, спершу на `music.youtube.com`, потім на `www.youtube.com` | статус, чи є `actions`, кількість `accountItem`, поля за правилами вище | ≥2 Google-елементи з різними `authuser`, рівно один `isSelected` |
| **P3** (C2, лише якщо P2 не пройшов) | `GET /getAccountSwitcherEndpoint` на обох хостах | статус, чи є XSSI-префікс, структура за правилами | те саме, що в P2 |
| **P4** | Найкращий кандидат з P0/P2/P3 з `X-Goog-AuthUser: 1`, а потім з індексом поза межами (наприклад, 7) | на якому елементі `isSelected`, чи має вибраний елемент токен з `authuser`, чи змінився порядок | `isSelected` переходить на елемент з `authuser=1`, набір індексів стабільний. Для індексу 7 записати, що позначено вибраним і чи має він токен: від цього залежить FR4 |

Результат записується в `docs/plans/account-switching/` (наприклад, у розділ QA): обраний запит, підтверджені шляхи JSON, поведінка поза межами, наявність `datasyncId`. Вивід лише редагований, без жодних значень. Синтетичну фікстуру будують вручну за цією структурою.

## Функціональні вимоги

1. **FR1. Discovery і рішення.** До початку реалізації UI запускаються зонди P0–P4, а результат (обраний кандидат, підтверджені шляхи й поведінка поза межами) документується. Primary і fallback обираються за правилом з розділу «Рекомендація».
2. **FR2. Запит списку.** Клієнт `InnerTube` отримує метод, що повертає список Google-акаунтів сесії за обраним кандидатом. На вхід він бере знімок cookies і поточний `authUserIndex`, як `accountMenu` (FR6 з 1.2). Якщо кандидату потрібен хост, клієнт чи метод, відмінні від `music.youtube.com` / `WEB_REMIX` / `POST`, це **явне розширення** контракту FR3 з 1.2. Дозволено лише конкретний додатковий хост (`www.youtube.com`), лише для цього запиту, з origin цього хоста в `SAPISIDHASH`, `Origin` і `X-Origin`. Редіректи, як і раніше, відхиляються. `clientVersion` для `WEB` (якщо потрібен) — одна константа до 2.1, як і для `WEB_REMIX`.
3. **FR3. Парсер списку.** Розбір толерантний до зсуву структури (як [P2] D5). Він повертає лише Google-акаунти, у кожного є `name`, `byline?`, `avatarURL?` (через наявний allowlist хостів), `authUserIndex`, `isSelected`. Елемент відкидається, коли:
   - є `pageIdToken` (brand);
   - немає імені;
   - немає індексу або індекс від'ємний (Low 3 з [S2]). Виняток описує FR4.

   Якщо кілька елементів мають однаковий індекс (канали одного акаунта), лишається один, перевага за елементом без `pageIdToken` (Info 5 з [S2]). Порядок — за зростанням індексу. Для C3 ті самі поля беруться з `account_menu` кожного індексу, а повтори відкидаються за ключем ідентичності.
4. **FR4. Вибраний елемент без індексу.** Активним вважається акаунт, чий індекс дорівнює `authUserIndex`. Як трактувати вибраний елемент без токена з `authuser` (M1 з [S2]), вирішує результат P4. Обов'язкові інваріанти незалежно від рішення:
   - (а) коли збережений індекс належить акаунту в сесії, вибір **не** скидається на 0;
   - (б) коли збережений індекс не належить жодному акаунту в сесії (наприклад, 7 при двох акаунтах), він **завжди** скидається на 0, навіть якщо Google мовчки показав акаунт 0 як вибраний без токена.

   Сліпо приписувати такому елементу поточний індекс заборонено, бо це порушує (б).
5. **FR5. UI списку на екрані акаунта.** Під заголовком активного акаунта йде список: аватар (заглушка, якщо немає), ім'я, byline (якщо є) і позначка активного. Неактивний рядок можна вибрати мишею й клавіатурою, а VoiceOver озвучує ім'я і стан «вибрано». Якщо в сесії один акаунт, список не показується або показується без можливості вибору. Кнопки «Add account» і «Sign out» лишаються.
6. **FR6. Перемикання.** Вибір рядка записує його індекс в `session.authUserIndex` (зберігається між запусками) і перезавантажує `account_menu` та список. Keychain і WebKit-сховище не змінюються. Під час `isSigningOut` вибір вимкнено (Info 6 з [S2]). Виграє останній вибір: відповідь для попереднього індексу не перезаписує екран.
7. **FR7. Fallback FR15.** Якщо **непорожній і успішно отриманий** список не містить `authUserIndex` (з урахуванням FR4 (б)), індекс стає 0, це зберігається, екран перезавантажується. Порожній список, збій запиту списку чи збій `account_menu` скидання **не** викликають. Скидання відбувається не більше одного разу на завантаження, щоб уникнути циклу.
8. **FR8. Збій списку.** Збій запиту списку не ламає екран: активний акаунт показується, як у 1.2, а замість списку видно коротке повідомлення з «Retry» (відкрите питання 4, закриває Low 5 з [S2]). Модель помилок 2.1 не будується.
9. **FR9. Після «Add account».** Після успішного додавання індекс не змінюється (поведінка `completeSignIn` з 1.2), а список перечитується й містить новий акаунт. Скасування sheet нічого не змінює.
10. **FR10. Allowlist регіональних хостів.** `isRegionalAccountsHost` замінюється перевіркою за знімком [GSD]:
    - головний фрейм дозволено, якщо схема `https`, хост дорівнює `accounts` + запис зі списку (наприклад, `accounts.google.com.ua`) **і** шлях дорівнює `/accounts/SetSID` (query довільний);
    - точний `allowedHosts` (включно з `accounts.google.com`) лишається без змін і обмеження шляху не отримує;
    - список вбудовується у код як дані з датою знімка й URL джерела. Застосунок не завантажує його під час роботи.
11. **FR11. Документація.** `docs/05-risks-and-scope.md` §4 #2 і `docs/02-architecture.md` §5.1 (`X-Goog-AuthUser` = вибраний індекс) та §5.2 (рядок для ендпоінта списку, а якщо додано `www.youtube.com`, то й хост) оновлюються за фактичним рішенням. У `docs/06-backlog.md` 1.3 позначається як виконаний.

## Нефункціональні вимоги

- **Безпека:**
  - cookies, `Authorization`, `SAPISID`, `datasyncId`, тіла відповідей, імена, email і URL аватарів не логуються (AC11 з 1.2 лишається в силі);
  - cookies `google.com` з WebKit-сховища не читаються й не копіюються в Keychain (через це C4 і відхилено);
  - новий хост, якщо він потрібен, додається точним збігом, не шаблоном;
  - `authuser` з відповіді — лише `Int ≥ 0`, тож у заголовок він потрапляє без ін'єкцій.
- **Приватність:** фікстури синтетичні й зібрані вручну (`Test User`, `test@example.com`, `https://yt3.ggpht.com/test-*`, `datasyncId` вигляду `test-a||`). Debug-зонди друкують лише редаговану структуру й не потрапляють у PR.
- **Продуктивність:** для C1 і C2 це один запит списку на відкриття, перемикання або Retry, паралельно з `account_menu`. Для C3 — не більше 10 послідовних запитів, і лише в тих самих подіях. Немає опитування за таймером і немає мережевої роботи на головному потоці.
- **Тестованість:** парсер, побудова запиту та логіка вибору/FR15 перевіряються `swift test` без мережі й Keychain. Де розмістити логіку вибору, вирішує розробник, але її треба покрити тестом (у 1.2 вона лишилась без тестів [Q2]).
- **Сумісність:** macOS 14+, Swift 6 strict concurrency без warnings, без нових залежностей і entitlements.
- **Комплаєнс:** використання приватного API прийняте раніше ([K] §2 п.1). Новий хост `www.youtube.com` нового ризику не додає.

## User stories (Gherkin)

### Story 1: Бачу всі акаунти сесії
**As a** користувач з двома Google-акаунтами в сесії
**I want** бачити список обох на екрані акаунта
**So that** я знаю, між чим можу перемикатися

**Acceptance criteria:**
- Given у сесії два Google-акаунти, When екран завантажено, Then видно два рядки з іменем і аватаром, а активний позначено.
- Given у відповіді є brand-канал або дублікат індексу, When список показано, Then brand-рядка немає і кожен індекс трапляється один раз.
- Given запит списку не вдався, When екран завантажено, Then активний акаунт видно, а замість списку є повідомлення з «Retry».

### Story 2: Перемикаюся на інший акаунт
**As a** користувач
**I want** вибрати інший акаунт одним кліком
**So that** застосунок працює від його імені

**Acceptance criteria:**
- Given активний акаунт 0, When я вибираю рядок з індексом 1, Then заголовок показує ім'я й аватар акаунта 1, а `authUserIndex == 1`.
- Given я перемкнувся на 1 і перезапустив застосунок, When екран завантажено, Then активним лишається 1.
- Given я швидко вибрав 1, а потім 0, When відповідь для 1 приходить пізніше, Then екран показує 0.

### Story 3: Збережений індекс зник із сесії
**As a** користувач, що вийшов з другого акаунта в браузері
**I want** щоб застосунок повернувся на основний акаунт
**So that** я не застрягаю в помилці

**Acceptance criteria:**
- Given збережено `authUserIndex == 5`, а список містить 0 і 1, When екран завантажено, Then індекс стає 0, зберігається, і показано акаунт 0.
- Given збережено 5, а Google позначив вибраним елемент без токена індексу, When екран завантажено, Then індекс однаково стає 0.
- Given список порожній або його запит упав, When екран завантажено, Then індекс не змінюється.

### Story 4: Додаю акаунт, лишаючись на поточному
**As a** користувач
**I want** додати акаунт і лишитися на поточному
**So that** додавання не змінює, від чийого імені я слухаю

**Acceptance criteria:**
- Given активний акаунт 1, When «Add account» успішно завершено, Then активним лишається 1, а список містить новий акаунт.
- Given я скасував sheet, When екран повертається, Then ні індекс, ні список не змінились.

### Story 5: Вхід лише через справжні домени Google
**As a** користувач
**I want** щоб вікно входу відкривало лише сторінки Google
**So that** сторонній домен не отримав моїх облікових даних

**Acceptance criteria:**
- Given редірект на `https://accounts.google.com.ua/accounts/SetSID?...`, When вікно входу його обробляє, Then навігацію дозволено.
- Given `https://accounts.google.de/ServiceLogin` або хост, якого немає в списку Google, When навігація, Then її скасовано.

## Перевірювані критерії приймання

| # | Критерій | Вимога | Як перевіряється |
|---|---|---|---|
| AC1 | Звіт discovery (P0–P4) записано у `docs/plans/account-switching/`, у ньому лише редагована структура, обраний primary і fallback, підтверджені шляхи до name / byline / avatar / authuser / selected, наявність `datasyncId`, поведінка індексу поза межами | FR1 | оркестратор + рев'ю |
| AC2 | **Gate.** P1: `account_menu` з `X-Goog-AuthUser: 1` повертає інший акаунт, ніж з 0: `datasyncId` відрізняється, якщо він є, інакше відрізняється ім'я або аватар. Інакше 1.3 зупиняється за відкритим питанням 1 | FR6 | debug-збірка |
| AC3 | Парсер на синтетичній фікстурі (структура з AC1): два Google-акаунти (0 вибраний, 1), brand з `pageIdToken`, дублікат індексу 1, елемент з `authuser=-1`, елемент без імені. Результат — рівно 2 елементи [0, 1] з правильними `isSelected`, byline й аватаром, а аватар з недозволеного хоста дає `nil` | FR3 | `swift test` |
| AC4 | Вибраний елемент без токена індексу трактується за рішенням з P4 і задовольняє інваріанти FR4 (а) і (б) | FR4 | `swift test` |
| AC5 | Відповідь без контейнера списку дає `[]` без збою. Нерозбірний JSON або не-2xx дають помилку списку | FR3, FR8 | `swift test` |
| AC6 | Побудова запиту списку: метод, URL (хост з allowlist), тіло (клієнт, `requestType`, `callCircumstance` або поля за P0), заголовки з FR4 1.2; `SAPISIDHASH`, `Origin` і `X-Origin` рахуються від origin хоста запиту. Для C3 кожен зонд має правильний `X-Goog-AuthUser`, а зупинка відбувається на повторі ключа ідентичності, не-2xx або ліміті | FR2 | `swift test` |
| AC7 | Логіка вибору (таблиця): індекс у списку — без змін; індекс поза непорожнім списком — 0; **індекс поза списком при вибраному елементі без токена — 0**; порожній список — без змін; збій — без змін; повторного скидання в одному завантаженні немає | FR4, FR7 | `swift test` |
| AC8 | Перемикання змінює заголовок і `authUserIndex`. Відповідь для попереднього індексу або після «Sign out» не перезаписує екран | FR6 | рев'ю + вручну |
| AC9 | Після успішного «Add account» індекс той самий, а список містить новий акаунт. Cancel нічого не змінює | FR9 | вручну |
| AC10 | `SignInRules`: дозволено `accounts.google.com.ua/accounts/SetSID`, `accounts.google.de/accounts/SetSID`, `accounts.google.co.uk/accounts/SetSID`, `accounts.google.cat/accounts/SetSID`. Відхилено: `accounts.google.de/ServiceLogin`, `accounts.google.com.ua/` (корінь), `accounts.google.xyz/accounts/SetSID`, наявні lookalike (`.com.evil.ua`, `evil.accounts.google.com.ua`, `.com.ua.evil.com`), `http://…`. Точні хости (наприклад, `accounts.google.com/AddSession`, `gds.google.com/web/landing`) дозволені як раніше | FR10 | `swift test` |
| AC11 | Знімок [GSD] вбудовано з датою й URL, мережевого завантаження списку немає, regex `isRegionalAccountsHost` видалено | FR10 | рев'ю + `grep` |
| AC12 | `grep` по `Packages/*/Sources`, `Packages/*/Tests`, `App/` не знаходить логування cookies, заголовків, тіл, `datasyncId`. Debug-коду зондів немає. Фікстури синтетичні | NFR | рев'ю + `grep` |
| AC13 | `xcodegen generate`, Debug-збірка, `swift test` в усіх пакетах проходять, Swift 6 без warnings | NFR | CI-команда |
| AC14 | **Вручну, користувач на живому акаунті:** (1) видно обидва акаунти, активний позначено; (2) перемикання на другий і назад змінює ім'я й аватар; (3) після ⌘Q вибір зберігається; (4) «Add account» лишає поточний акаунт і оновлює список; (5) `defaults write dev.kruhlyk.tunewave authUserIndex 7` і запуск дають акаунт 0, а `authUserIndex` після цього дорівнює 0; (6) Sign out працює; (7) вхід через регіональний `SetSID` (як у fix pass 3) проходить | FR4–FR10 | вручну, результат записується в `03-qa.md` |
| AC15 | Документи з FR11 оновлено | FR11 | рев'ю |

## Модель даних (ескіз)

| Сутність | Поля | Примітки |
|---|---|---|
| `AccountListItem` (відновлюється за [P2] D5) | `name`, `byline?`, `avatarURL?`, `authUserIndex: Int (≥0)`, `isSelected` | ідентичність — `authUserIndex` (унікальний після FR3) |
| `AccountInfo` | без змін | активний акаунт з `account_menu` |
| Стан екрана | завантаження, дані (активний + список або «список недоступний»), помилка | живе в `App/`, як у 1.2 |
| `authUserIndex` | `Int` у `UserDefaults` | модель з 1.1 без змін |
| Знімок доменів Google | набір суфіксів + дата + URL джерела | лише в `Auth`, без мережі |
| (C3) ключ ідентичності | `datasyncId` з `responseContext.mainAppWebResponseContext` або трійка (ім'я, handle, аватар) | використовується лише для порівняння й не зберігається |

Рефактору сховища не потрібно: модель `authUserIndex: Int` покриває Google-акаунти. Brand-акаунтам потрібен був би `pageId`, але вони поза скоупом.

## Контракт API (ескіз)

Остаточний контракт фіксує AC1. Ескізи кандидатів наведено в таблиці «Кандидати для discovery». Незмінне для всіх:
- поля відповіді: `accountItem.accountName` → name, `accountItem.accountByline` / `channelHandle` → byline, `accountItem.accountPhoto.thumbnails[]` → avatar, `authuser` з `serviceEndpoint.selectActiveIdentityEndpoint.supportedTokens[].accountSigninToken.signinUrl` → індекс, `accountItem.isSelected` → selected, `supportedTokens[].pageIdToken` → brand-маркер **[поля з [YJ-AI], шлях індексу unverified]**;
- перемикання: окремого запиту немає, змінюється лише `X-Goog-AuthUser` у наступних запитах (за умови AC2).

## Граничні випадки та помилки

- **`X-Goog-AuthUser` не перемикає акаунт** (повідомлено в [YJ-735]). Тоді вся модель перемикання не працює. AC2 це ловить до реалізації UI (відкрите питання 1).
- **`datasyncId` відсутній у відповідях `WEB_REMIX`.** P1 і C3 переходять на порівняння імені, handle й аватара. Два акаунти з однаковими іменем і аватаром-заглушкою можуть злитися в один. Це ризик, і P1 показує, чи він актуальний.
- **Індекс поза межами** для `account_menu`: можлива помилка, а можливий тихий повтор акаунта 0. P1 і P4 фіксують, як саме. FR4 (б) гарантує скидання в обох випадках.
- **Перенумерація індексів.** Якщо акаунт вийшов у браузері, Google може зсунути індекси. Тоді збережений індекс може вказувати на **інший** існуючий акаунт, і FR15 цього не помітить, бо індекс є в списку. Приймаємо: користувач бачить ім'я й може перемкнути (відкрите питання 6).
- **Акаунт у сесії з потрібним повторним входом** (`isDisabled` або «signed out» у switcher). Рядок показується неактивним або не показується (за AC1). Його вибір не повинен залишити екран у вічному завантаженні.
- **Канали одного акаунта** (особистий + brand) з тим самим `authuser`. Brand відкидається, дублікати зводяться в один рядок (FR3).
- **Один акаунт.** Список не показується, перемикання немає.
- **Перегони.** Швидке A→B, вихід під час запиту, «Add account» під час завантаження списку: виграє останній запит, після виходу нічого не записується.
- **Ротація cookies після AddSession.** Keychain отримує новий знімок cookies `youtube.com` на `completeSignIn`. Якщо нового акаунта в списку немає, це баг, і AC14 (4) його ловить.
- **Застарілий `clientVersion` для `WEB`** (C1). Як і для `WEB_REMIX`, це константа до 2.1.
- **XSSI-префікс** (C2): відповідь без нього або з іншим префіксом вважається нерозбірною.
- **Регіональний домен, якого немає в знімку** (новий ccTLD). Навігацію буде скасовано, і вхід зависне, як у fix pass 3. Знімок потрібно оновлювати. Помилку видно під час ручної перевірки, а не мовчки.
- **Шлях `SetSID` з іншим регістром або кінцевою `/`.** Порівнюємо точно, тож це дасть відмову. Якщо AC14 (7) покаже інший шлях, правило уточнюється.
- **GDPR / видалення.** Нових даних застосунок не зберігає. Sign out, як і раніше, очищає обидва сховища й скидає індекс.

## Ризики та залежності

- **Залежить від 1.2 (злито):** `InnerTubeClient`, `InnerTubeRequest`, `AccountInfo`, `AccountModel` і `AccountView`, а також `AuthSession.authUserIndex` і `addAccount()`.
- **Головний ризик:** AC2. Якщо заголовок не перемикає ідентичність, 1.3 стає великим завданням: перемикання через навігацію WebKit на `signinUrl` і повторне захоплення cookies.
- **Ризик #2 [K]:** формат switcher змінюється. Парсер толерантний, а fallback C3 спирається на `account_menu`, який уже перевірено.
- **Новий хост `www.youtube.com`** (якщо C1 або C2 працюють лише там): розширення поверхні, але cookies ті самі (`youtube.com`).
- **Знімок доменів застаріває:** періодичне оновлення вручну.
- **Зачеплені файли:** `Packages/InnerTube/Sources/InnerTube/*` (клієнт, запит, новий парсер), `Packages/InnerTube/Tests/*`, `Packages/Auth/Sources/Auth/SignInRules.swift` і тести, `App/AccountModel.swift`, `App/AccountView.swift`, документи з FR11.

## Відкладене (з ID backlog)

| Що | Куди |
|---|---|
| Brand-акаунти й канали (`X-Goog-PageId`, `onBehalfOfUser`) | **ID немає**, запропонувати новий рядок (наприклад, після 2.1) |
| Guest mode | 1.4 |
| Модель помилок, 401 → вхід, оновлення cookies, `clientVersion` зі сторінки | 2.1 |
| Узгодження вибраного `authuser` з плеєром у web view | 3.1 |
| Місце перемикача в оболонці (sidebar, toolbar, меню) | 4.1 |
| Полірування станів і VoiceOver | 4.7 |
| Вкладка «Account» у Settings | 5.3 |
| Вихід з одного акаунта (а не з усіх) | **ID немає**, у брифі не просили |
| Детект перенумерації за `datasyncId` | **ID немає**, див. відкрите питання 6 |

## Відкриті питання до стейкхолдерів

1. **Що робити, якщо P1 покаже, що `X-Goog-AuthUser: 1` повертає той самий акаунт, що й 0?** **Рекомендація:** зупинити 1.3 після discovery, записати результат і перепланувати перемикання через web view (оцінка large) окремим рядком backlog. Список без перемикання не випускати.
2. **Чи дозволяти запити на `www.youtube.com`, якщо список віддає лише він?** **Рекомендація:** так, лише для запиту списку, точним хостом, з origin `www.youtube.com` у підписі.
3. **Чи прийнятний fallback C3 (до 10 запитів `account_menu` на кожне відкриття екрана)?** **Рекомендація:** так, з лімітом 10, лише на відкриття, перемикання, Retry й після «Add account».
4. **Як показувати збій запиту списку?** **Рекомендація:** активний акаунт лишається, під ним короткий текст «Couldn't load other accounts» і «Retry». Без автоматичних повторів (модель помилок буде в 2.1).
5. **Debug-код зондів: тимчасовий чи в репозиторії під `#if DEBUG`?** **Рекомендація:** тимчасовий, у PR не потрапляє. Результати фіксуються лише редагованим звітом.
6. **Чи детектити перенумерацію індексів (збережений індекс тепер вказує на інший акаунт)?** **Рекомендація:** ні в 1.3. Ім'я на екрані робить це очевидним, і користувач перемикається вручну.
7. **Що показувати в byline: email чи handle?** **Рекомендація:** `accountByline`, якщо він є (у switcher це зазвичай email), інакше `channelHandle`. Для C3 — лише handle.

## Оцінка складності

**medium.** Код невеликий: один запит, один парсер (дизайн уже є в [P2] D5), список у наявному екрані, заміна regex на знімок доменів. Основна робота — discovery на живому акаунті через оркестратора. Складність стає **large**, якщо AC2 провалиться (перемикання через web view), або якщо працює лише C3 без `datasyncId` і з тихим поверненням акаунта 0 для індексу поза межами.

## Результати discovery і відповіді на відкриті питання (2026-11-18)

Discovery описано в `00-discovery.md`. Gate AC2 пройдено. Список акаунтів повертає `GET https://music.youtube.com/getAccountSwitcherEndpoint`, а не `accounts_list`. Індекс поза межами дає HTTP 200 без `activeAccountHeaderRenderer`. `datasyncId` у відповіді немає.

1. **Питання 1** знято: gate пройдено.
2. **Питання 2** знято: список віддає той самий хост `music.youtube.com`, тож `www.youtube.com` не потрібен.
3. **Питання 3 (fallback C3).** Рішення користувача: **ні**. Лишається тільки switcher. Якщо запит не вдався, активний акаунт лишається на екрані, а під ним з'являється «Couldn't load other accounts» і Retry.
4. **Питання 4–7** прийнято за рекомендаціями:
   - збій списку показуємо, як у п. 3;
   - debug-код зондів тимчасовий і в PR не потрапляє;
   - перенумерацію індексів не відстежуємо;
   - byline = `accountByline`, а якщо його немає, то `channelHandle`.

> Виправлення після AC14: `accountByline` у живій відповіді — це локалізована кількість підписників або «No channel», а не email. Secondary-текст рядка — лише `channelHandle`; `accountByline` не читається.
