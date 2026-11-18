# Огляд безпеки: Auth — вхід через Google у WKWebView, cookies у Keychain, вихід (backlog 1.1)

## Підсумок
- Critical: 0
- High: 1 (передається у fix pass: текст docs/05 §2 п.4 і повторне підтвердження рішення користувачем)
- Medium: 1 (рекомендація. Це кілька рядків в одній функції без побічних ризиків, тож оркестратор може включити їх у fix pass, як M1 у 0.2)
- Поза скоупом: Low 6, Info 8

Прямого шляху експлуатації в коді немає. Між сторінкою та нативним кодом немає містка (JS→native), main frame обмежено точним allowlist, popup-вікна і завантаження неможливі, cookies ніде не логуються. Головна проблема в іншому: задокументована модель загроз (docs/05 §2 п.4) применшує ризик, який користувач прийняв, і саме рішення спирається на хибне порівняння із Safari.

## Що перевірено і виявилося чистим

| Перевірка | Результат |
|---|---|
| Логування (A09) | `grep` за `print(`, `Logger`, `os_log`, `NSLog`, `dump(`, `debugPrint`, `.description`, `String(describing` у `Packages/*/Sources`, `Packages/*/Tests`, `App/` не знайшов нічого. `KeychainError` містить лише `OSStatus` і системний текст. UI показує фіксовані рядки, а не текст `signInError` |
| Тести (AC5) | значення синтетичне (`"test-value"`). `KeychainItem`, `AuthSession` і `WKWebsiteDataStore` у тестах не створюються |
| Десеріалізація (A08) | binary plist через `PropertyListSerialization` і `HTTPCookie(properties:)`. `NSKeyedUnarchiver` немає, тож довільні об'єкти не створюються. `Dictionary(uniqueKeysWithValues:)` не впаде: ключі plist-словника унікальні, а `HTTPCookiePropertyKey` ↔ `String` — бієкція |
| Що потрапляє в Keychain | лише `youtube.com` / `.youtube.com` / `music.youtube.com` (`SignInRules.musicCookies`, `SignInView.swift:116`). Cookies `google.com` у Keychain не пишуться |
| Атрибути Keychain (A02) | generic password у файловому login keychain (без `kSecUseDataProtectionKeychain`). Елементи файлового keychain не синхронізуються з iCloud, тож «not synchronized» у docs/05 правдиве за конструкцією, навіть без ручного кроку 3 плану. `kSecAttrAccessible` файловий keychain ігнорує, тож його відсутність не є знахідкою. ACL за замовчуванням довіряє застосунку-творцю (cdhash) |
| Навігація main frame (A01/A10) | `https` і точний збіг хоста в нижньому регістрі. `user@host`, хвостова крапка, `google.com.evil.example` та IDN дають `false` (fail-closed). Заблокована навігація скасовується (`.cancel`) і назовні не відкривається. За поведінкою WebKit серверні редиректи main frame теж проходять через `decidePolicyFor`, але тут це не перевірено |
| Нові вікна | для `target=_blank` / `window.open` `targetFrame == nil`, тож умова `nil == false` хибна, і дія проходить через allowlist. Далі `createWebViewWith` повертає `nil`, і вікно не створюється |
| Завантаження, файли, медіа | немає делегата завантажень (`WKDownloadDelegate`, `navigationAction(_:didBecome:)`), немає `runOpenPanel` і `requestMediaCapturePermission`. Без entitlements камери й мікрофона Hardened Runtime доступу не дасть |
| Поверхня JS→native | немає `WKScriptMessageHandler`, `WKUserScript` і `evaluateJavaScript`. Пароль вводиться у WebContent-процесі WebKit і в процес Tunewave не потрапляє. `isInspectable` за замовчуванням `false` |
| Спуфінг успіху входу | предикат вимагає main frame на `music.youtube.com` (main frame може бути лише на allowlist-хості) і `SAPISID` з доменом `youtube.com`. Таку cookie ставить лише відповідь або скрипт `youtube.com`, тож сторонній origin її не підробить |
| Конкурентність | `AuthSession` і `Coordinator` — `@MainActor`. `cookiesDidChange` має атрибут `nonisolated` і запускає `Task { @MainActor [weak self] }`, а `Task` у `checkSignIn` успадковує MainActor. Після `await allCookies()` повторно перевіряються `didComplete` і `isSignInActive`. `completeSignIn` синхронний, тож подвійного збереження немає. Спільного між потоками змінюваного стану немає. Виняток див. у M1 (c) |
| Hardened Runtime / entitlements | `.entitlements` немає, `project.yml` не змінено. JIT JavaScriptCore працює в XPC-процесі WebContent від Apple, тож `allow-jit` і `disable-library-validation` не потрібні. Release без `get-task-allow` (з 0.2) |
| User-Agent | `applicationNameForUserAgent` дописує `Version/<v> Safari/605.1.15` до стандартного префікса WebKit. Версія береться з `Info.plist` Safari, а змінити його може лише адміністратор, і наслідком буде лише інший UA. Ін'єкції в заголовок немає. Порушення ToS через підміну UA вже зафіксоване в docs/05 §2 п.1 |
| `X-Goog-AuthUser` | `authUserIndex` має тип `Int`, тож ін'єкції в заголовок бути не може. Значення не секретне. Див. L1 |
| ATS | ключів `NSAppTransportSecurity` немає. Main frame — лише `https`. Змішаний вміст у subframes блокує WebKit |

## Critical findings (для fix pass)

Немає.

## High findings (для fix pass)

### 1. Модель загроз у docs/05 §2 п.4 применшує прийнятий ризик — `docs/05-risks-and-scope.md:32-40`

**Статус: прийнято користувачем 2026-11-18 (повторно підтверджено після огляду), docs/05 оновлено.**

**Проблема.** 2026-11-18 користувач прийняв зберігання cookies у `WKWebsiteDataStore.default()` з обґрунтуванням «так само поводиться Safari» (`01-business-analysis.md:202`). Новий текст §2 п.4 повторює це обґрунтування. Проте два твердження в ньому хибні, і через них прийнято більший ризик, ніж описано.

1. **Обсяг доступу.** Текст каже: «Session cookies give full access to the Google account within YouTube». Це правда лише для елемента Keychain, бо `musicCookies` пропускає тільки `youtube.com`. У сховищі WebKit також лежать cookies, які ставить сам вхід на `accounts.google.com`: `SID`, `HSID`, `SSID`, `APISID`, `SAPISID`, `__Secure-1PSID`, `__Secure-3PSID`, `LSID` та інші на `.google.com` і `accounts.google.com`. BA це визнає («Вони лишаються у website data store», `01-business-analysis.md:68`). Ці cookies дають доступ до **всього** Google-акаунта: Gmail, Drive, Photos, налаштувань (крім дій, для яких Google просить пароль повторно). Keychain захищає лише підмножину того, що лежить на диску без захисту.
2. **«Like Safari's».** Це не так. З macOS 10.14 cookies та історія Safari (`~/Library/Cookies`, `~/Library/Safari`, контейнер `com.apple.Safari`) захищені TCC: інший застосунок читає їх лише з Full Disk Access ([Eclectic Light](https://eclecticlight.co/2018/09/06/working-with-mojaves-privacy-protection/)). На macOS 27 Apple додатково закрила від несендбоксних застосунків профілі Chrome і Firefox ([Apple Developer Forums](https://developer.apple.com/forums/thread/847030)). Файли Tunewave у `~/Library/HTTPStorages/dev.kruhlyk.tunewave*` і `~/Library/WebKit/dev.kruhlyk.tunewave/` (застосунок без sandbox) не підпадають під жоден із цих механізмів. Отже, вони захищені *гірше* за Safari, а не так само. Чи не поширила macOS 27 захист і на ці шляхи, звідси не перевірено, тому перевірка нижче обов'язкова.
3. Дрібніше: «Sign-out clears both» не уточнює, що вихід лише локальний. Сесія на сервері Google лишається дійсною. Копії файлу cookies у резервних копіях (Time Machine та інші файлові бекапи `~/Library`) теж лишаються придатними, доки Google їх не відкличе.

**Exploit.** Будь-який процес від імені користувача (шкідливий postinstall у npm/pip-пакеті, інфостілер, скомпрометоване розширення редактора) без жодного запиту читає `~/Library/HTTPStorages/dev.kruhlyk.tunewave*`. Він витягує `SID` / `__Secure-1PSID` для `.google.com` і перехоплює весь Google-акаунт, а не лише YouTube. Той самий процес, намагаючись прочитати cookies Safari, отримав би «Operation not permitted». Вихід у Tunewave вже вкрадене не відкликає. Це можна зробити лише в Google Account (вихід пристрою в «Your devices» або зміна пароля).

**Чому High, а не Info про вже прийнятий ризик.** Код відповідає рішенню користувача. Але саме рішення спирається на два хибні факти, а документ, на який далі спираються 1.2, 3.1 і реліз, їх закріплює. Виправлення — це текст і повторне підтвердження, а не переробка коду.

**Prescribed fix.**
1. **Архітектор (fix pass):** замінити в `docs/05-risks-and-scope.md` §2 п.4 (рядки 32-40) текст на наведений нижче (англійською, як і решту файлу). Код не змінювати.

   > 4. **Credentials.** Two stores hold the session.
   >    - The Keychain item (`dev.kruhlyk.tunewave.session`, generic password in the login keychain, not synchronized) holds only the `youtube.com` cookies. It is the source of the app's session state and of the cookies InnerTube sends; they give full access to the Google account within YouTube.
   >    - The WebKit website data store (`WKWebsiteDataStore.default()`; files named after `dev.kruhlyk.tunewave` under `~/Library/HTTPStorages`, `~/Library/WebKit` and `~/Library/Caches`) is the browser session that the sign-in window and the player share. It also holds the `google.com` / `accounts.google.com` session cookies, which give access to the **whole Google account** (Gmail, Drive, account settings), not only YouTube. Unlike Safari's cookies, which macOS protects behind Full Disk Access, these files are readable without any prompt by every process running as the same user, and the cookie files can be copied by file backups such as Time Machine.
   >    - **Status: pending user re-confirmation.** The 2026-11-18 acceptance assumed Safari-equivalent protection and YouTube-only scope.
   >    - Sign-out clears both stores on this Mac only. It does not end the session at Google: a copy that has already leaked, or sits in a backup, stays valid until Google expires it or the user signs the device out in the Google Account or changes the password.
   >    - Cookie values are never logged and never end up in fixtures, test output or crash reports.

2. **Оркестратор (не архітектор):** показати користувачу виправлений текст і попросити повторно підтвердити рішення №1. Якщо користувач підтверджує, рядок «Status: pending…» замінити на «Accepted for personal use (user decision, <дата підтвердження>)». Якщо не підтверджує, є такі варіанти (рішення за користувачем):
   - (a) після успішного `completeSignIn` видаляти з `WKHTTPCookieStore` cookies `.google.com` і `accounts.google.com`. Це дешево, але, ймовірно, зламає `addAccount()` (`AddSession` потребує google.com-сесії) і ротацію cookies (ризик #8). Перевіряти на go/no-go;
   - (b) `WKWebsiteDataStore.nonPersistent()` для входу й плеєра, а під час запуску переносити `youtube.com` cookies з Keychain у `httpCookieStore`. Диск закривається повністю, але цей варіант уже відхилено як складний (BA, відкрите питання 1), і він зачіпає 3.1;
   - (c) sandbox (контейнер під захистом App Data). Суперечить рішенню docs/02 §1.
3. **Перевірка (виконує користувач, агент команд не запускає).** Переконатися, що Terminal *немає* у System Settings → Privacy & Security → Full Disk Access. Після входу виконати `ls -l ~/Library/HTTPStorages/ | grep tunewave` і `ls ~/Library/Containers/com.apple.Safari/Data/Library/Cookies/`. Очікувано перша команда покаже файли без запиту, а друга поверне `Operation not permitted`. Якщо перша теж відмовить, macOS 27 уже захищає ці шляхи, і речення «Unlike Safari's…» треба переписати.

## Medium recommendations (у цьому прогоні не виправляються)

### 1. Вихід може «воскреснути» або лишити Google-сесію на диску — `Packages/Auth/Sources/Auth/AuthSession.swift:56-58, 68-84`, `App/SignedInPlaceholderView.swift:10`

**Статус: виправлено у fix pass.**

**Проблема.**
- **(a) Порядок кроків.** Keychain видаляється (рядок 74) до `await removeData` (рядок 82). Якщо застосунок завершиться під час цього `await` (Cmd-Q, збій, вимкнення), Keychain уже порожній, а сховище WebKit ще ні. На наступному запуску стан буде `.signedOut`, `ServiceLogin` автоматично перенаправить на `music.youtube.com`, і `completeSignIn` мовчки збереже сесію знову. Так порушується Story 3 («після виходу й перезапуску — не увійшов»), і жодного сигналу про це немає.
- **(b) Збій видалення з Keychain перериває очищення WebKit.** Якщо `keychain.delete()` кидає помилку (рядки 75-77), вихід зупиняється *до* `removeData`. Так буває, коли користувач відмовив у запиті Keychain після нової ad-hoc збірки (ризик #11) або keychain заблокований. Помилку видно, але cookies `.google.com` лишаються в `~/Library` (див. H1), хоча користувач хотів вийти.
- **(c) «Add account» доступна під час виходу.** Кнопку (`SignedInPlaceholderView.swift:10`) не вимкнено, а `addAccount()` не перевіряє `isSigningOut`. Під час `await removeData` стан ще `.signedIn`, тож sheet можна відкрити знову. Тоді `isAddingAccount` може лишитися `true` після `state = .signedOut`, і головне вікно відкриє `AddSession` замість `ServiceLogin` (`SignInView.swift:54`). Крім того, повторна перевірка після `await` у `checkSignIn` (`SignInView.swift:114`, `isSignInActive` на рядках 122-125) пропускає стан `.signedOut`. Тому `Task`, який зняв знімок cookies ще до очищення, а відновився після `state = .signedOut`, теоретично записав би стару сесію назад у Keychain. План (D7, §10 «Перегони») стверджує, що повторна перевірка закриває цей випадок, але вона закриває лише варіант «відновився, поки `.signedIn`».

**Рекомендоване виправлення.** Спочатку очищати WebKit, потім Keychain, а стан перемикати лише після обох кроків. Додавання акаунта під час виходу заблокувати:

```swift
public func addAccount() {
    guard !isSigningOut else { return }
    isAddingAccount = true
}

public func signOut() async {
    guard !isSigningOut else { return }
    isSigningOut = true
    defer { isSigningOut = false }
    signOutError = nil
    isAddingAccount = false
    await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    do {
        try keychain.delete()
    } catch {
        signOutError = error
        return
    }
    authUserIndex = 0
    state = .signedOut
}
```

У `SignedInPlaceholderView.swift:10` додати до «Add account» `.disabled(session.isSigningOut)`, як уже зроблено для «Sign out».

Наслідки нового порядку:
- збій Keychain тепер лишає видимий стан «увійшов» з повідомленням про помилку і порожнє сховище WebKit, тобто без Google-wide cookies на диску. Повторний «Sign out» працює;
- завершення процесу посеред виходу лишає «увійшов» після перезапуску, і це видно, а не мовчки «воскреслу» сесію.

Залишковий ризик (c) після цієї зміни практично закритий: під час виходу немає живого `SignInView`, крім sheet, який саме закривається. Повністю закрити його можна лише лічильником поколінь сесії, а це зайве для 1.1.

**Чому відкладено.** Випадок (a) потребує завершення процесу саме поки триває `removeData` (зазвичай частки секунди). Збій (b) видимий, і вихід можна повторити. Випадок (c) потребує дій у вузькому вікні. За класифікацією це Medium, хоча зміна — перестановка рядків в одній функції й одна умова.

## Поза скоупом

### Low

1. **`authUserIndex` не скидається, коли сесію відкинуто без виходу** (`AuthSession.swift:50-52`, `87-98`). `restore()` видаляє прострочений або пошкоджений елемент, але індекс не чіпає. Звичайний вхід (не add-account) у `completeSignIn` теж його не скидає. Після нового входу з іншим набором акаунтів 1.2 надішле `X-Goog-AuthUser` зі старим індексом: дії підуть від іншого акаунта сесії, або запити впадуть. Зараз індекс завжди 0, бо UI вибору з'явиться в 1.2. Виправлення: `authUserIndex = 0` поруч із `try? keychain.delete()` у `restore()` і в `completeSignIn`, коли `!isAddingAccount`. Зробити до 1.2.
2. **Помилка проковтнута в `restore()`** (`AuthSession.swift:51`, `try? keychain.delete()`). Якщо видалення не вдалося, пошкоджений чи прострочений елемент лишається, і на кожному запуску повторюється той самий шлях. Наступний вхід перезапише елемент через `SecItemUpdate`. Шкоди немає. Якщо з'явиться логування, записувати `status`.
3. **Опис `HTTPCookie` містить значення** (`AuthSession.swift:9`, `.signedIn(cookies:)`). `NSHTTPCookie.description` друкує `value`, тож будь-яке майбутнє `print(session.state)`, `Logger` з `"\(state)"` чи `dump` у 1.2/3.1 виведе сесійні cookies. `grep`-перевірку з §8 плану варто поширити на `App/` і `Packages/InnerTube`, а в `Logger` писати лише назви cookies з `privacy: .private`.
4. **Підміна елемента Keychain (клас XARA)** (`KeychainItem.swift:18-36`). Запит без `kSecUseDataProtectionKeychain` знаходить будь-який generic password з такими service/account у списку пошуку keychain. Процес того самого користувача може заздалегідь створити елемент із власним ACL. Тоді `write()` через `SecItemUpdate` запише cookies туди, де той процес читає їх без запиту, а `read()` прийме підкладений набір, тобто застосунок увійде в чужий акаунт. Сьогодні це нічого не додає до H1, бо той самий атакувальник і так читає сховище WebKit. Якщо диск колись закриють (варіант H1-b), переглянути: робити `write()` як `SecItemDelete` + `SecItemAdd`, щоб ACL завжди створював Tunewave.
5. **Allowlist перевірено лише як чисту функцію** (`SignInView.swift:76-80`). Жоден тест не доводить, що WebKit справді викликає async-варіант `decidePolicyFor`. Якби сигнатура розійшлася з вимогою протоколу, WebKit пропускав би всі навігації, а тести лишалися б зеленими. Збірка без warnings (`02-development.md:16`) свідчить про збіг лише непрямо. Додати в ручний AC8: на `accounts.google.com` натиснути «Help», «Privacy» і «Terms» (`support.google.com`, `policies.google.com` — поза allowlist). Нічого не має відкритися.
6. **Тихі відкидання в кодеку** (`SessionCookies.swift:13-15`, `24-26`). `compactMap` мовчки пропускає cookie без `properties` або таку, яку `HTTPCookie(properties:)` не відновив. Якщо це обов'язкова cookie, вийде видимий `.signedOut`. Решта зникне непомітно, і в 1.2 заголовок `Cookie` буде неповним. На go/no-go порівняти кількість cookies до `encode` і після `restore`.

### Info

1. **Subframes без обмежень і без адресного рядка** (D6). Це свідомий компроміс. Main frame обмежено, тож фішингова сторінка не може стати головною. Повернутися до цього, коли go/no-go покаже, які хости subframes реально потрібні.
2. **Go/no-go на Debug-збірці** (`get-task-allow`, без Hardened Runtime) зі справжніми cookies. Після перевірки натиснути «Sign out» або далі користуватися Release-збіркою.
3. **Звичка до запитів Keychain** (ризик #11). Після кожної збірки користувач погоджується на «Tunewave wants to use … dev.kruhlyk.tunewave.session». Будь-який ad-hoc застосунок з тією самою назвою покаже такий самий діалог. Це вже враховано в оцінці H1.
4. **Passkeys** потребують restricted entitlement `com.apple.developer.web-browser.public-key-credential`, а для нього потрібна команда розробника. З ad-hoc підписом він недоступний. Обхід паролем уже є в Story 5.
5. **`SecItemCopyMatching` на main thread** у `AuthSession.init`. Поки користувач відповідає на запит Keychain, UI заблоковано. Це UX, не безпека.
6. **Широта allowlist** (`SignInRules.swift:7-12`). Хости `www.google.com` і `myaccount.google.com` переглянути після go/no-go й лишити лише ті, що справді трапилися в потоці входу.
7. **Для 1.2/3.1.**
   - Якщо InnerTube покладе cookies у `HTTPCookieStorage.shared` або `URLSessionConfiguration`, `signOut()` має очищати і їх.
   - Web view плеєра (3.1) треба зупинити до `removeData`, щоб сторінка не встигла записати нові cookies після очищення.
   - `SignInWebView` неявно покладається на те, що `WKWebViewConfiguration()` використовує `.default()`. Якщо сховище колись задаватимуть явно, `signOut()` має очищати саме його.
8. **Зайвий рядок у `signOut()`** (`AuthSession.swift:79-80`). Спершу викликається `removeObject(forKey:)`, а потім `authUserIndex = 0`, і `didSet` знову записує ключ. Шкоди немає, рядок 79 можна прибрати (у M1 це вже враховано).

## Зведення за severity

| Severity | Кількість | Що далі |
|---|---|---|
| Critical | 0 | — |
| High | 1 | fix pass: текст docs/05 §2 п.4; оркестратор просить користувача повторно підтвердити рішення №1 |
| Medium | 1 | рекомендація: перестановка в `signOut()` і блокування `addAccount()` під час виходу (можна включити у fix pass) |
| Low | 6 | поза скоупом; L1 зробити до 1.2 |
| Info | 8 | поза скоупом |

Джерела:
- [Eclectic Light — Working with Mojave's Privacy Protection](https://eclecticlight.co/2018/09/06/working-with-mojaves-privacy-protection/)
- [Apple Developer Forums — thread 847030 (macOS 27, доступ до каталогів браузерів)](https://developer.apple.com/forums/thread/847030)
