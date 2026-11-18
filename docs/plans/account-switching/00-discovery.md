# Discovery: список акаунтів і перемикання (backlog 1.3, AC1)

Дата: 2026-11-18. Перевірено на живій сесії з двома Google-акаунтами і одним brand-акаунтом. Використовувалась тимчасова debug-збірка, у PR вона не потрапляє. Збірка друкувала лише структуру відповідей, булеві порівняння та 8-символьні SHA-1-дайджести імен. Самі імена, email і cookies не друкувались.

## P1. Gate AC2: чи перемикає `X-Goog-AuthUser`

Запит: `POST music.youtube.com/youtubei/v1/account/account_menu`, клієнт `WEB_REMIX`.

| `X-Goog-AuthUser` | HTTP | `activeAccountHeaderRenderer` | Ім'я відрізняється від індексу 0 |
|---|---|---|---|
| 0 | 200 | є | — |
| 1 | 200 | є | **так** (інший акаунт) |
| 2 | 200 | **немає** | — |
| 3 | 200 | **немає** | — |

- **Gate пройдено:** індекс 1 повертає інший акаунт, тож модель «перемикання = індекс у заголовку» працює.
- Індекс поза межами дає HTTP 200 **без** `activeAccountHeaderRenderer`, тобто без помилки і без тихого повтору акаунта 0.
- `datasyncId` у відповідях `WEB_REMIX` **відсутній**.

## P2. `account/accounts_list` (кандидат C1): не працює

Перевірено на `music.youtube.com` і `www.youtube.com`, з клієнтами `WEB` (версія `2.20261115.01.00` зі сторінки) і `WEB_REMIX`. Тіло: `ACCOUNTS_LIST_REQUEST_TYPE_CHANNEL_SWITCHER` / `SWITCHING_USERS_FULL`.

Усі чотири варіанти повернули HTTP 200 і **0 `accountItem`**. З клієнтом `WEB` у відповіді є `actions`, але без елементів акаунтів. З `authuser` 1 і 7 результат той самий.

## P3. `GET /getAccountSwitcherEndpoint` (кандидат C2): **працює**

Обидва хости, `music.youtube.com` і `www.youtube.com`, повернули HTTP 200 з однаковим вмістом: 3 `accountItem`.

| # | `isSelected` | brand (`pageIdToken` / `pageid`) | `authuser` з `signinUrl` | `accountByline` | `channelHandle` | Збіг з P1 |
|---|---|---|---|---|---|---|
| 0 | true | ні | 0 | є | є | ім'я = P1 індекс 0 |
| 1 | false | **так** | 0 | є | є | brand-акаунт, відкидається |
| 2 | false | ні | 1 | є | немає | ім'я = P1 індекс 1 |

- `signinUrl` має вигляд відносного шляху `/signin?action_handle_signin&authuser=<n>&next&feature&skip_identity_prompt` (тут показано лише назви параметрів). У brand-елемента є ще параметр `pageid`.
- Запит: `GET` з тими самими заголовками, що й `account_menu` (`Cookie` для youtube.com, `Authorization: SAPISIDHASH` з origin `https://music.youtube.com`, `X-Goog-AuthUser`, `Origin`). Тіла немає.
- Відповідь може починатися з XSSI-префікса `)]}'`. Debug-збірка знімала його перед розбором, тому парсер теж має знімати цей префікс, якщо він є.
- Точні шляхи до `accountItem` не фіксувались. Парсер шукає `accountItem` рекурсивно, як у дизайні D5 з 1.2.

## Рішення

- **Primary:** `GET https://music.youtube.com/getAccountSwitcherEndpoint`, тобто той самий хост, що й решта клієнта. Новий хост не потрібен, тому відкрите питання 2 знімається.
- **Fallback:** C3, перебір `account_menu` з індексами 0..N. Зупинка на першій відповіді без `activeAccountHeaderRenderer`, ліміт 10. `datasyncId` відсутній, тому ідентичність визначається за індексом.
- **Відкидаємо:** C1 (`accounts_list`) у всіх варіантах.
- Brand-акаунти відкидаються за `pageIdToken` / параметром `pageid`, як і планувалось.
