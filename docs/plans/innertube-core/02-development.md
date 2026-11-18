# Звіт розробки: InnerTube core (backlog 1.2)

## Файли

Створено (`Packages/InnerTube/Sources/InnerTube/`): `JSONValue.swift`, `SAPISIDHash.swift`, `InnerTubeRequest.swift`, `InnerTubeClient.swift` (також `InnerTubeError`), `AccountInfo.swift`, `AccountListItem.swift`.
Тести (`Packages/InnerTube/Tests/InnerTubeTests/`): `JSONValueTests`, `SAPISIDHashTests`, `InnerTubeRequestTests`, `AccountParsingTests`.
Застосунок: `App/AccountModel.swift`.

Змінено: `App/SignedInPlaceholderView.swift` перейменовано через `git mv` на `App/AccountView.swift` (новий вміст), `App/TunewaveApp.swift`, `Packages/Auth/Sources/Auth/AuthSession.swift` (FR14 а, б), `docs/05-risks-and-scope.md`, `docs/02-architecture.md`.

Залежності: нових немає (системні CryptoKit, Foundation).

## Відхилення від плану

- `AccountInfo` отримав публічний `init(name:handle:avatarURL:)`, бо `#Preview` у застосунку будує його на синтетичних даних.
- `InnerTubeError` має `Equatable`, щоб тести могли перевіряти `throws:`.
- Коментар біля `clientVersion` записано як `// shortcut: ...` (формат ponytail). Значення `1.20261115.14.00` взято з плану, повторно з мережі не перечитувалося (див. «Для QA»).
- `AccountModel.load`: якщо `accountMenu` впав, а `accountsList` ще виконується, дочікуємось його перед виходом, щоб `async let` не залишився висіти.

## Результати перевірки

Команда з `test_command`: `xcodegen generate` + `xcodebuild ... build` без помилок і warnings; `swift test` у пакетах: Auth 12, InnerTube 17 (4 suites), інші по 1. Усе пройшло, помилок 0.
grep на логування та спільні сховища (AC11): порожньо.

## Для QA / безпеки / ручної перевірки

- AC13 (користувач): пункти 1–6 з плану §6. Особливо: чи приймається `SAPISIDHASH` без `SAPISID1PHASH`, чи працює `clientVersion`, і чи `accounts_list` повертає Google-акаунти сесії з `authuser` у `signinUrl`. Якщо ні: прибрати виклик `accountsList` у `AccountModel` (запасний варіант (в)).
- Тіло запиту `accounts_list` і шляхи `accountItem` мають статус [known, verify at AC13]; парсер шукає `accountItem` рекурсивно.
- Транспорт (не-2xx, відхилення редіректів) unit-тестами не покритий, за планом.
- `AccountView` не має UI-тестів (тестового таргета немає). Рядки англійською, String Catalog немає.

## Fix pass

- M1: `App/AccountModel.swift:34` — до умови додано `index != 0,`; при індексі 0 екран переходить у `.loaded`, а не зависає в завантаженні.
- L1: `Packages/InnerTube/Sources/InnerTube/AccountInfo.swift` (`lastThumbnailURL`, спільна для меню й списку акаунтів) — лише `https` і хости `ggpht.com`/`googleusercontent.com`/`ytimg.com` (точний збіг або піддомен), інакше `nil`. Фікстури в `AccountParsingTests.swift` переведено на `yt3.ggpht.com/test-*`, додано `rejectsDisallowedAvatarURLs` (example.com, file:, http, `evilggpht.com`).
- L2: `Packages/Auth/Sources/Auth/AuthSession.swift:80` — `URLCache.shared.removeAllCachedResponses()` одразу після `removeData` WebKit.
- L6: `docs/05-risks-and-scope.md` §4 #2 — дописано «pending manual check AC13; fallback: ...» за формулюванням звіту.
- 04-security.md: під M1, L1, L2, L6 додано «Fixed in fix pass».
- Тест: `xcodegen generate`, `xcodebuild` build і `swift test` у всіх пакетах — успішно з першої спроби.

## Fix pass 2 (AC13)
- Проблема: після пароля Google веде main frame на `gds.google.com/web/landing`; `decidePolicyFor` скасовував навігацію (WebKit 102, `report` її ігнорує), вікно входу зависало.
- Зміна: `Packages/Auth/Sources/Auth/SignInRules.swift:12` — `"gds.google.com"` у `allowedHosts`; `Packages/Auth/Tests/AuthTests/SignInRulesTests.swift:43` — випадок `https://gds.google.com/web/landing` у параметризованому `allowlist`.
- Тест: `xcodegen generate`, `xcodebuild` build і `swift test` у всіх пакетах — успішно з першої спроби.

## Fix pass 3 (AC13)
- Проблема: після `accounts.youtube.com/accounts/SetSID` Google редіректить main frame на регіональний `https://accounts.google.com.ua/accounts/SetSID`; хост не дозволений, навігацію скасовувало (WebKit 102), вікно лишалося порожнім.
- Зміна: `Packages/Auth/Sources/Auth/SignInRules.swift` — до точного allowlist додано `isRegionalAccountsHost` (повний збіг `accounts.google.(com.|co.)?<cc>`, `<cc>` — рівно дві латинські літери, лише https); `SignInRulesTests.swift` — дозволені `.com.ua`, `.de`, `.co.uk`; відхилені `.xyz`, `.com.evil.ua`, `evil.accounts.google.com.ua`, `.com.ua.evil.com`, `http://...com.ua`.
- Тест: `xcodegen generate`, `xcodebuild` build і `swift test` у всіх пакетах — успішно (друга спроба: перша впала через non-Sendable статичний `Regex`, замінено на локальний літерал у функції).

## Fix pass 4 (AC13: accounts_list fallback)
- Проблема: `account/accounts_list` на живому акаунті повертає лише `responseContext` і `selectText`, тож парсер дає 0 акаунтів; «Add account» працює.
- Рішення користувача (BA, питання 1): у 1.2 лише активний акаунт, список і перемикання — у backlog 1.3.
- Зміна: `App/AccountModel.swift` (стан `.loaded(AccountInfo)`, без виклику списку й fallback за індексом), `App/AccountView.swift` (без списку; Add account і Sign out лишилися); видалено `InnerTubeClient.accountsList`, `AccountListItem.swift` і його тести; `text`/`lastThumbnailURL` та тест allowlist аватарів лишилися в `AccountInfo`.
- Docs: `docs/06-backlog.md` (рядок 1.3), `docs/05-risks-and-scope.md` §4 №2, `03-qa.md` (знахідка AC13).
