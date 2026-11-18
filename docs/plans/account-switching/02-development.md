# Реалізація: список акаунтів і перемикання (backlog 1.3)

Проєкт: XcodeGen, macOS 14, Swift 6, SwiftUI + Observation, локальні SPM-пакети, Swift Testing у пакетах.

## Створено
- `Packages/InnerTube/Sources/InnerTube/AccountListItem.swift` (model + парсер, `fallbackIndex`)
- `Packages/Auth/Sources/Auth/GoogleSupportedDomains.swift` (data, 187 доменів)
- `Packages/InnerTube/Tests/InnerTubeTests/AccountListTests.swift`

## Змінено
- `InnerTubeRequest.swift` (`signed`, `makeGet`), `JSONValue.swift` (`init(response:)`, XSSI), `InnerTubeClient.swift` (`send`, `accountSwitcher`)
- `SignInRules.swift` (`isRegionalSetSID` замість regex), тести `SignInRulesTests`, `JSONValueTests`, `InnerTubeRequestTests`
- `App/AccountModel.swift`, `App/AccountView.swift` (`AccountAvatar`, `AccountRow`, повідомлення «Couldn't load other accounts» з Retry)
- `docs/02-architecture.md` §5.1/5.2, `docs/05-risks-and-scope.md` §4 #2

## Відхилення
- Немає відхилень від плану з урахуванням «Затвердження»: запит списку завжди з `X-Goog-AuthUser: 0` (`AccountModel.load`), активний рядок за `session.authUserIndex`.
- Парсер бере `signinUrl` як перший **рядковий** значення за ключем (на випадок, якщо ключ зустрінеться з обʼєктом).

## Тести
`xcodegen generate && xcodebuild ... build && swift test у кожному пакеті`: збірка Tunewave без помилок і попереджень; Auth 12 тестів, InnerTube 43 тести, інші пакети по 1, усі пройшли. AC11: `wholeMatch` лишився лише в тестах хешу SAPISID, `isRegionalAccountsHost` немає. AC12: нового логування немає.

## Для QA / безпеки / вручну
- AC14 вручну (зокрема (5): застарілий індекс, FR15 тепер працює, бо список іде з індексом 0). Модель і UI автотестами не покриті (тестового таргета `App/` немає).
- Рекурсивний парсер без підтверджених шляхів у реальній відповіді: порядок «першого» `signinUrl` у словнику недетермінований, якщо в елементі їх кілька.
- Знімок доменів оновлюється вручну.

## Fix pass

- M1: `AccountModel.State.failed(accounts:)` зберігає завантажений список; `AccountView` має спільний `AccountRows`, який показується в `.loaded` і `.failed`, тож з «зламаного» акаунта можна повернутися.
- L1: `AccountListItem.item(_:)` збирає всі `signinUrl`; якщо `authuser` неоднозначний (різні індекси), елемент відкидається. `pageid` перевіряється в усіх URL. Тести: конфліктні індекси відкидаються, однакові повторні лишаються.
- L2 (рішення користувача): порожній результат перемикача (`[]`) у `AccountModel.load` стає `nil`, тобто збій списку: «Couldn't load other accounts» + Retry, без індексного fallback. Наявні тести не стверджували протилежного (`fallbackIndex` з `[]` лишився як захист).
- Info 4: додано рядок про знімок supported_domains (джерело, дата 2026-11-18, шлях `/accounts/SetSID`, ручне оновлення) у `docs/02-architecture.md` §6.
- Перевірка: `test_command` пройшов з першої спроби (xcodegen, збірка, `swift test` у всіх пакетах).

## Fix pass 2 (AC14 feedback)

- `AccountListItem.byline` перейменовано на `handle`; парсер читає лише `channelHandle`, `accountByline` не читається (там кількість підписників або «No channel»).
- `AccountView`: другий рядок — `item.handle`, без handle вторинного тексту немає. Превʼю оновлено.
- Тести: фікстура містить `accountByline` як «3 960 subscribers» / «No channel» і перевіряє, що він ігнорується; `handleComesFromChannelHandleOnly`.
- Рішення «byline = accountByline, інакше channelHandle» (01-business-analysis.md) доповнено поправкою.
- Перевірка: `test_command` (результат нижче в підсумку виконання).

## Fix pass 3 (AC14 feedback: avatars only)
- `AccountView.swift`: рядки акаунтів тепер горизонтальний `HStack` круглих аватарів (34 pt, той самий `AccountAvatar`), без імені й handle.
- Активний акаунт позначений кільцем (`Circle().stroke`, accentColor) плюс трейт `.isSelected`; кнопка вимкнена для активного та під час виходу.
- Кожна кнопка: `.help(name)`, `.accessibilityLabel(name)`; дія перемикання без змін.
- `AccountListItem.handle` залишено в моделі (покрито тестами парсера); превʼю "Row" оновлено.
- Перевірка: `test_command` — build і тести пакетів пройшли.
