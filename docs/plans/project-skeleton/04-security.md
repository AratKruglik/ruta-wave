# Огляд безпеки: каркас проєкту Tunewave (backlog 0.2)

## Підсумок
- Critical: 0 (до fix pass нічого не передається)
- High: 0
- Medium: 1 (рекомендація. Виправлення займає один рядок і нічим не ризикує, тому оркестратор може сам включити його в fix pass)
- Поза скоупом (Low/Info): 5

Зміна є каркасом без жодної runtime-логіки. Немає ні мережі, ні сховищ, ні вводу користувача, ні обробки помилок. Тому OWASP A01–A10 і чекліст тихих збоїв не мають тут точок прикладання. Огляд зосереджено на конфігурації збирання й підпису.

## Що перевірено і виявилося чистим

| Перевірка | Результат |
|---|---|
| Секрети в бандлі | у `project.yml`, згенерованому Info.plist і пакетах немає ключів, токенів чи URL з обліковими даними. `DEVELOPMENT_TEAM: ""` не є секретом |
| App Transport Security | Info.plist генерується (`GENERATE_INFOPLIST_FILE: YES`), ключів `NSAppTransportSecurity` / `NSAllowsArbitraryLoads` немає |
| Entitlements | `.entitlements` немає. Немає `com.apple.security.cs.*`, немає `disable-library-validation`. Sandbox вимкнено свідомо, за рішенням користувача (docs/02 §1), і це не знахідка. Єдиний ключ `get-task-allow` розібрано в M1 |
| Hardened Runtime | у Release `flags=0x10002(adhoc,runtime)` (за звітом розробки) |
| Залежності | лише локальні `.package(path:)`. Remote-пакетів і `Package.resolved` немає, тож немає й поверхні supply chain |
| `.gitignore` | `*.xcodeproj/`, `.build/`, `.swiftpm/`, `xcuserdata/` і локальний стан SDLC ігноруються. `.env`-файлів немає |
| Логування / приватність | немає ні `print`, ні `os.Logger`. Захищені ресурси не використовуються, тож `NS…UsageDescription` не потрібні |
| Тихі збої | немає жодного `catch`, `try?` чи return-коду |

## Critical findings (для fix pass)

Немає.

## High findings (для fix pass)

Немає.

## Medium recommendations (у цьому прогоні не виправляються)

### 1. `com.apple.security.get-task-allow` у Release-збірці — `project.yml:24-34` (`targets.Tunewave.settings`)

> **Статус:** виправлено в цьому PR за рішенням користувача (security fix pass): `configs: Release: CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO`. Перевірено: у Release `get-task-allow` немає, `flags=0x10002(adhoc,runtime)`; у Debug ключ лишився. QA verify rerun: 6/6.

**Проблема.** Ad-hoc підпис (`CODE_SIGN_IDENTITY: "-"`) використовується з `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` за замовчуванням (`YES`). Тому Xcode додає `get-task-allow` у підпис обох конфігурацій, зокрема Release, і звіт розробки це підтверджує (02-development.md:17). Цей entitlement є саме тим винятком Hardened Runtime, який дозволяє іншим процесам отримати task port застосунку. З ним Hardened Runtime і далі блокує `DYLD_*`-ін'єкцію, але вже не захищає від під'єднання налагоджувача. Також не справджується очікування «Hardened Runtime увімкнено» з docs/02 §1: Release-збірка фактично налагоджувана.

**Сценарій експлуатації (з'явиться з backlog 1.1).** Шкідливий процес працює від імені того самого користувача і підписаний ad-hoc з `com.apple.security.cs.debugger`, а це не restricted entitlement. На Mac з увімкненим Developer Mode, що типово для машини з Xcode, він отримує task port Tunewave. Далі він читає пам'ять процесу або виконує код усередині нього. Від імені Tunewave можна прочитати Keychain-елементи з сесійними cookies Google, і ACL Keychain не покаже запиту. Ці cookies дають повний доступ до Google-акаунта в межах YouTube (docs/05 §2.4).

**Чому Medium, а не High:**
- зараз застосунок не має жодних даних, тож красти нічого;
- атаці потрібні виконання коду від імені того самого користувача та авторизація налагоджувача;
- атакувальник такого рівня і без `get-task-allow` прочитає дискове сховище cookies WebKit, бо застосунок працює без sandbox (див. «Поза скоупом», п. 2). Отже, `get-task-allow` не є найслабшою ланкою;
- фінальний підпис DMG формує скрипт етапу 8, який перепідписує застосунок (див. «Поза скоупом», п. 1).

**Рекомендоване виправлення.** Один рядок, ризику немає. У `project.yml` в `targets.Tunewave.settings` додати блок `configs:` на тому самому рівні, що й `base:` (після рядка 34, з відступом 6 пробілів):

```yaml
      configs:
        Release:
          CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO
```

- Ключ має бути саме `Release`. XcodeGen зіставляє ключі `configs` без урахування регістру й за входженням підрядка, але точний збіг має пріоритет. Тому з точним ключем налаштування не пошириться на майбутні конфігурації на кшталт `Staging Release`.
- Debug не чіпати: там `get-task-allow` потрібен для lldb.

Перевірка після `xcodegen generate` і Release-збірки (шлях `.app` взяти з `BUILT_PRODUCTS_DIR`):
- `codesign -d --entitlements - Tunewave.app` не показує `get-task-allow`;
- `codesign -dv --verbose=2 Tunewave.app` і далі показує `flags=0x10002(adhoc,runtime)`;
- Debug-збірка і далі містить `get-task-allow`;
- твердження «`get-task-allow` присутній і в Release … Не дефект» у 02-development.md:17 та відповідний критерій QA застаріють, тож їх треба оновити.

**Чому відкладено.** Лише через класифікацію: за чесною оцінкою це Medium, і ризику сьогодні немає. Якщо оркестратор вирішить, виправлення вкладається в поточний fix pass без побічних ефектів. Застосувати його треба не пізніше злиття backlog 1.1 (Auth: cookies → Keychain).

## Поза скоупом (Low/Info)

1. **Перепідпис на етапі 8, імовірно, знімає Hardened Runtime (`docs/03-roadmap.md:190`, нотатка для backlog 8.1).** Запланована команда `codesign --force --deep --sign -` не містить `--options runtime`. Під час перепідпису codesign не переносить прапорець runtime і entitlements, якщо їх не вказати явно (`-o runtime` / `--preserve-metadata`). Звідси це не перевірено, перевірте на реальному артефакті. Наслідок: Release-збірка в Xcode виглядатиме правильно, а в DMG Hardened Runtime тихо зникне, і FR3 зламається. Для 8.1:
   - підписувати командою `codesign --force --options runtime --sign - Tunewave.app`;
   - не використовувати `--deep`, бо Apple не радить його для підпису: вкладений код підписують зсередини назовні;
   - у самому скрипті перевіряти фінальний артефакт: `codesign -dv` містить `runtime`, а `codesign -d --entitlements -` не містить `get-task-allow`.

   Наслідки цього пункту більші, ніж у M1, але файл не входить у цю зміну.
2. **Cookies WebKit на диску (нотатка для backlog 1.1).** docs/02 §4.1 передбачає `websiteDataStore = .default()`. Застосунок без sandbox, тому WebKit зберігає cookies у `~/Library` (наприклад, `HTTPStorages/dev.kruhlyk.tunewave`) поза захищеним контейнером. Будь-який процес того самого користувача прочитає їх без запиту Keychain, тож вимога «cookies лише в Keychain» (docs/05 §2.4) буквально не виконається. Це треба врахувати в моделі загроз 1.1 або свідомо прийняти для персонального використання.
3. **Debug без Hardened Runtime** (`flags=0x2(adhoc)`). Для локальної Debug-збірки це очікувано, бо вона не поширюється.
4. **Ad-hoc підпис змінюється з кожним збиранням.** Designated requirement прив'язаний до cdhash, тож Keychain повторно запитує доступ. Це відомий ризик №11 (docs/05) без нового впливу на безпеку.
5. **`PrivacyInfo.xcprivacy` відсутній.** Для DMG поза App Store і без required-reason API зараз він не потрібен. Повернутися до нього, якщо з'явиться дистрибуція через App Store.
