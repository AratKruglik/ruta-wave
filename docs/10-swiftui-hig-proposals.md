# 10. Пропозиції з покращення UI за рекомендаціями Apple (SwiftUI та HIG)

Дата: 2026-11-27 · Код: `develop` @ `4169331` · Ціль розгортання: macOS 14.0 (`project.yml`) · Перевірено на macOS 27.2.

Це продовження [аудиту 09](09-ui-ux-audit.md). Аудит відповідав на питання «що не так для користувача». Цей звіт відповідає на інше: **які з цих проблем зникають, якщо те саме зробити засобами платформи** — так, як радять документація SwiftUI та Human Interface Guidelines.

## Джерела і рівень певності

Перед написанням я звірив із документацією Apple ті API й настанови, на які спираються пропозиції:

- SwiftUI: [`safeAreaBar`](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)), [`scrollEdgeEffectStyle`](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:)), [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views), [`backgroundExtensionEffect`](https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect()), [`Window`](https://developer.apple.com/documentation/swiftui/window), [`windowLevel`](https://developer.apple.com/documentation/swiftui/scene/windowlevel(_:)), [`restorationBehavior`](https://developer.apple.com/documentation/swiftui/scene/restorationbehavior(_:)), [`searchScopes`](https://developer.apple.com/documentation/swiftui/view/searchscopes(_:scopes:)), [`searchFocused`](https://developer.apple.com/documentation/swiftui/view/searchfocused(_:equals:)), [`Table`](https://developer.apple.com/documentation/swiftui/table/init(_:selection:sortorder:columns:)), [`contextMenu(forSelectionType:menu:primaryAction:)`](https://developer.apple.com/documentation/swiftui/view/contextmenu(forselectiontype:menu:primaryaction:)), [`ContentUnavailableView`](https://developer.apple.com/documentation/swiftui/contentunavailableview), [`RedactionReasons.placeholder`](https://developer.apple.com/documentation/swiftui/redactionreasons).
- HIG: [Materials → Liquid Glass](https://developer.apple.com/design/human-interface-guidelines/materials), [Color](https://developer.apple.com/design/human-interface-guidelines/color), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), [Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields), [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars), [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables), [Typography](https://developer.apple.com/design/human-interface-guidelines/typography).

Решту згаданих API наведено з памʼяті; у таблиці доступності наприкінці вони позначені «звірити». Жодну пропозицію не перевірено збіркою — це напрямки, а не готові патчі.

## Як читати

Кожна пропозиція має: **що зараз** (з кодом), **що радить Apple**, **що пропоную**, мінімальну версію macOS, обсяг (S — до дня, M — кілька днів, L — тиждень і більше), ризик і перелік пунктів аудиту, які вона закриває (у дужках — номери issues).

## Підсумок

| № | Пропозиція | Обсяг | Ризик | Закриває |
|---|---|---|---|---|
| A1 | Плеєр-бар і верхня панель як safe-area-панелі замість оверлеїв із ручними відступами | M | середній | UX-01 (#110), UX-04 (#113), UX-05 (#114), UX-22 (#131) |
| A2 | Справжній toolbar вікна і `.searchable` | L | середній | UX-19 (#128), UX-09 (#118), UX-10 (#119), UX-04 |
| A3 | Бічна панель як `List(selection:)` | M | низький | UX-20 (#129), UX-35 (#144) |
| A4 | Життєвий цикл вікон: reopen, пункт меню, міні-плеєр | S | низький | UX-03 (#112), UX-26 (#135) |
| B1 | Списки треків як `Table` | L | високий, потрібне рішення | UX-16 (#125), UX-11 (#120), UX-30 (#139) |
| B2 | Полиці: розмір карток від контейнера і прилипання | S | низький | UX-18 (#127), UX-27 (#136) |
| B3 | Скелети через `.redacted` на справжній розкладці | M | низький | UX-14 (#123) |
| B4 | Порожні стани й помилки через `ContentUnavailableView` | S | низький | UX-23 (#132) |
| C1 | Сімейство `ButtonStyle` замість 63 `.buttonStyle(.plain)` | M | низький | UX-17 (#126), UX-32 (#141) |
| C2 | Liquid Glass за настановами HIG | S–M | низький | UX-05 (#114) |
| C3 | Семантичні кольори й каталог ресурсів | M | середній | UX-24 (#133), UX-25 (#134) |
| C4 | Типографіка: стилі тексту, виділення тексту | S | низький | UX-22 (#131), UX-37 (#146) |
| C5 | SF Symbols: `Label`, переходи символів | S | низький | UX-11 (#120) |
| C6 | Вкладки й розділи як сегментований `Picker` | S | низький | UX-21 (#130), клас помилки UX-01 |
| C7 | Черга й лірика в `.inspector` | L | потрібне рішення | UX-21 (#130), UX-22 (#131) |
| D1 | Пружинні анімації й проявлення обкладинок | S | низький | UX-37 (#146) |
| E1 | Вказівник, фокус, автоматичний аудит доступності | S | низький | UX-24 (#133) |
| F1 | Системні налаштування доступності | S–M | низький | UX-24 (#133), UX-11 (#120) |
| G1 | Форматування часу й чисел через format styles | S | низький | UX-21 (#130), UX-38 (#147) |

---

## A. Каркас вікна

### A1. Плеєр-бар і верхня панель як safe-area-панелі

**Що зараз.** Обидві панелі — це `.overlay` над `NavigationSplitView` ([ShellView.swift](../App/Shell/ShellView.swift)). Місце під них вміст резервує вручну: `contentMargins(.bottom, barInset, for: .scrollContent)` у двох місцях, `safeAreaPadding(.top, topBarHeight)` у чотирьох, плюс `ignoresSafeArea(.container, edges: .top)`. Сторінка плеєра додає власний `padding(.bottom, playerBarHeight + 16)`.

Саме цей механізм породив UX-01: `contentMargins` дістається кожному вкладеному `ScrollView`, зокрема горизонтальному рядку чипів.

**Що радить Apple.** `safeAreaInset(edge:)` розміщує вміст біля краю і сам зменшує безпечну зону; прокручуваний вміст отримує правильні відступи без ручних розрахунків. У macOS 26 зʼявився `safeAreaBar(edge:)`: те саме, але, за документацією, він ще й «extends the edge effect of any scroll views affected by the inset safe area». HIG (Materials) пояснює навіщо: scroll edge effect розмиває й приглушує вміст під панеллю заради читабельності, а Color додає, що вміст у стані спокою під елементами керування має лишатися розбірливим.

**Що пропоную.**

```swift
splitView
    .safeAreaInset(edge: .bottom, spacing: 0) {
        if isBarVisible { PlayerBar(isPlayerPagePresented: $isPlayerPagePresented) }
    }
```

На macOS 26 — `safeAreaBar(edge: .bottom)` за перевіркою доступності, а стиль краю задати через `scrollEdgeEffectStyle(_:for:)`. Після цього прибрати обидва `contentMargins(.bottom, barInset…)` і ручний відступ на сторінці плеєра. Верхню панель перевести так само або одразу на toolbar (A2).

**Мінімальна версія:** `safeAreaInset` — macOS 12; `safeAreaBar` і `scrollEdgeEffectStyle` — macOS 26.

**Ризик.** У коді є коментар, що сторінки, відкриті через `navigationDestination`, «hosted outside the stack's modifiers». Модифікатор треба ставити на рівень, який бачать і вони, і перевірити кожен тип сторінки. Оверлей сторінки плеєра теж має опинитися всередині цієї безпечної зони.

**Закриває:** UX-01 у корені (#110), UX-04 (#113), значну частину UX-05 (#114), обрізаний рядок лірики з UX-22 (#131).

### A2. Справжній toolbar вікна і `.searchable`

**Що зараз.** Toolbar вікна сховано; замість нього — власний `TopBar` з `HStack`, власною зоною перетягування вікна (`TitleBarDragArea: NSViewRepresentable`), власним полем пошуку на `TextField` і власним випадним списком ([TopBar.swift](../App/Shell/TopBar.swift), [SearchField.swift](../App/Search/SearchField.swift)). У застосунку один `.toolbar(` — той, що прибирає системний перемикач панелі.

**Що радить Apple.** HIG (Toolbars) описує три зони: на початку — повернення назад і показ бічної панелі, далі заголовок; у центрі — часті дії; у кінці — важливі елементи, кнопки інспекторів і поле пошуку. Груп має бути не більше трьох. HIG (Search fields) для macOS радить поле пошуку в кінці toolbar, особливо в застосунках із розділеним виглядом. Стандартні компоненти отримують Liquid Glass і ефект краю прокрутки автоматично (HIG, Materials: «Standard components from system frameworks pick up the appearance and behavior of this material automatically»).

**Що пропоную — у два кроки.**

1. Перенести перемикач панелі, назад/вперед і аватар у `.toolbar` з відповідними розміщеннями (`.navigation` для історії). Власне поле пошуку поки лишити як `ToolbarItem(placement: .principal)`. Це вже дає системне скло, перетягування вікна без `NSViewRepresentable`, згортання елементів у вузькому вікні та правильний порядок із UX-19.
2. Оцінити `.searchable(text:placement:)` із `searchSuggestions`, `searchScopes` і `searchFocused`. Scopes — це готова заміна чипам фільтрів пошуку (All / Songs / Albums…): за документацією, SwiftUI сам додає до поля `Picker`. Поле отримує кнопку очищення й стандартну поведінку фокуса.

**Компроміс другого кроку.** Теперішній список підказок багатший за стандартний: рядки історії з кнопкою видалення, сутності з обкладинками, три рівні Esc. `searchSuggestions` приймає довільні view, але керування клавіатурою й закриттям там системне. Якщо ця поведінка важлива — зупинитися на першому кроці.

**Мінімальна версія:** `.toolbar`, `.searchable` — macOS 12; `searchScopes` — macOS 13; `searchFocused` — звірити (імовірно macOS 15).

**Закриває:** UX-19 (#128), UX-09 (#118), частково UX-10 (#119) і UX-04 (#113).

### A3. Бічна панель як `List(selection:)`

**Що зараз.** `ScrollView` + `LazyVStack` із власних кнопок `NavItem` і `PlaylistRow` ([SidebarView.swift](../App/Shell/SidebarView.swift)). Виділення, наведення, фокус і розміри рядків намальовано вручну. У всьому застосунку `List` трапляється один раз.

**Що радить Apple.** HIG (Sidebars, macOS): висота рядка, розмір тексту й гліфа залежать від розміру бічної панелі, який користувач обирає в системних налаштуваннях; не варто класти важливі дії внизу панелі; панель може ховатися сама при звуженні вікна (це вже зроблено). Стандартна бічна панель у SwiftUI — `List(selection:)` зі стилем `.sidebar`.

**Що пропоную.** `List(selection:)` із двома секціями: розділи (`Label` з назвою й символом) і «Playlists». Це дає без коду: навігацію стрілками, вибір за першими літерами, системне підсвічування виділення, повагу до системного розміру панелі, згортання секції, `onMove` для перевпорядкування. Кнопку New playlist перенести в заголовок секції. Перетягування треків на плейлист (`dropDestination`) і контекстне меню лишаються.

**Мінімальна версія:** macOS 13. **Ризик:** губиться частина власного вигляду (рядки 48 pt, пігулка New playlist) — це свідомий обмін на нативну поведінку.

**Закриває:** плутанину з виділенням із UX-20 (#129), частково UX-35 (#144).

### A4. Життєвий цикл вікон

**Що зараз.** Головне вікно — `WindowGroup`; після закриття його не повернути з меню (UX-03). Міні-плеєр — `Window` зі стандартним заголовком; рівень «поверх усіх» задає власний `WindowLevel: NSViewRepresentable`.

**Що радить Apple.** Документація `Window` каже важливе для музичного застосунку: якщо `Window` — основна сцена, «the app quits when the window closes», тоді як із `WindowGroup` застосунок працює далі. Тож `WindowGroup` тут — правильний вибір, і міняти його не треба. Та сама сторінка пояснює, чому Mini Player є в меню Window: система сама показує там список одиничних вікон. Для головного вікна такого пункту немає, його слід додати самим.

**Що пропоную.**

```swift
func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    showMainWindow()
    return true
}
```

- Не покладатися на `hasVisibleWindows`: приховане вікно плеєра 1×1 pt, імовірно, рахується як видиме — можливо, саме тому стандартне відновлення зараз не спрацьовує. `showMainWindow()` уже шукає головне вікно за ідентифікатором.
- Додати пункт у меню Window: `CommandGroup(before: .windowList) { Button("RutaWave") { … }.keyboardShortcut("0") }`.
- Міні-плеєр: `.windowStyle(.hiddenTitleBar)`; на macOS 15+ `.windowLevel(.floating)` замість `WindowLevel`, `.restorationBehavior(.disabled)` і `.windowBackgroundDragBehavior(.enabled)`.

**Мінімальна версія:** делегат і команди — macOS 14; сцен-модифікатори рівня й відновлення — macOS 15 (потрібна перевірка доступності).

**Закриває:** UX-03 (#112), UX-26 (#135).

---

## B. Списки й колекції

### B1. Списки треків як `Table`

**Що зараз.** `LazyVStack` із `TrackRow` (16 `LazyVStack` у застосунку, жодної `Table`). Виділення, ⌘- і ⇧-клік, «вибрати все» реалізовано вручну в [TrackSelection.swift](../App/Components/TrackSelection.swift); модифікатори читаються з `NSEvent.modifierFlags`. Колонки (назва, альбом, тривалість) — це `HStack`, тому вони не вирівняні між рядками з різними мініатюрами (UX-16) і не сортуються.

**Що радить Apple.** HIG (Lists and tables, macOS): дозволяти сортування кліком по заголовку колонки, зміну ширини колонок, за потреби — чергування кольору рядків. SwiftUI: `Table(_:selection:sortOrder:columns:)` з множинним виділенням і `contextMenu(forSelectionType:menu:primaryAction:)`. Документація прямо описує поведінку: «In macOS, a single click on a row in a selectable container selects that row, and a double click performs the primary action».

**Що пропоную.** Пілот на двох екранах — Library → Songs і сторінка плейлиста:

```swift
Table(songs, selection: $selection, sortOrder: $sortOrder) {
    TableColumn("Title", value: \.title) { TrackTitleCell(song: $0) }
    TableColumn("Album", value: \.albumTitle)
    TableColumn("Time", value: \.duration) { Text(verbatim: PlaybackRules.formatTime($0.duration)) }
        .width(64)
}
.contextMenu(forSelectionType: Song.ID.self) { ids in
    ItemMenu(songs: songs(for: ids))
} primaryAction: { ids in
    play(ids)
}
```

Виділення, ⌘A, стрілки, ⇧-розширення, сортування й вирівняні колонки приходять від системи; `TrackSelection` і частина `trackSelection(…)` стають непотрібними. Каруселі й рядки на Home, Explore і в черзі лишаються як є.

**Потрібне рішення.** Специфікація (08 §8.1) каже «Row click plays». У `Table` один клік виділяє, подвійний — відтворює; так поводиться і Music. Це зміна звички, тому спершу варто вирішити, чи вона прийнятна.

**Мінімальна версія:** macOS 13. **Ризик:** високий за обсягом — комірка з діями при наведенні, перетягування рядків, вигляд на темі з обкладинки.

**Закриває:** UX-16 (#125), частину UX-30 (#139), спрощує UX-11 (#120).

### B2. Полиці: розмір карток від контейнера і прилипання

**Що зараз.** Картки фіксованої ширини 180 pt у `LazyHStack` ([ShelfView.swift](../App/Browse/ShelfView.swift)), тож остання видима картка обрізається де доведеться, а третя колонка рядкових полиць — посеред тексту. Прокрутку стрілками зроблено через `scrollPosition(id:)`.

**Що радить Apple.** Для каруселей SwiftUI (macOS 14) має `containerRelativeFrame(_:count:span:spacing:)` — розмір елемента як частка видимої ширини, і `scrollTargetBehavior(.viewAligned)` — зупинка на межі елемента. `scrollTargetLayout()` у коді вже є.

**Що пропоную.** Рахувати кількість карток від ширини (`count` залежить від ширини колонки), додати `.scrollTargetBehavior(.viewAligned)`; поля сторінки задати через `contentMargins(.horizontal, …, for: .scrollContent)` на самій каруселі, щоб вона доходила до країв вікна, а перша картка стояла по сітці. Стрілки ховати, коли полиця не переповнена.

**Мінімальна версія:** macOS 14. **Закриває:** обрізані колонки з UX-18 (#127), щільність сіток із UX-27 (#136), стрілки з UX-36 (#145).

### B3. Скелети через `.redacted` на справжній розкладці

**Що зараз.** Окремі `SkeletonRows`, `SkeletonCards`, `SkeletonChips` ([PageStates.swift](../App/Components/PageStates.swift)); `.redacted` використано один раз. Скелет — це інше дерево view, тому він легко розходиться з результатом (UX-14).

**Що радить Apple.** `redacted(reason: .placeholder)` показує ту саму ієрархію у вигляді заглушок: «Displayed data should appear as generic placeholders».

**Що пропоную.** Кожен екран малює свою справжню розкладку на даних-заглушках:

```swift
ShelfView(shelf: .placeholder)
    .redacted(reason: .placeholder)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
```

Розбіжність скелета з розкладкою стає неможливою за побудовою. Потрібні легкі моделі-заглушки поза `#if DEBUG` (зараз схожі дані живуть у `PreviewFixtures`).

**Мінімальна версія:** macOS 11. **Закриває:** UX-14 (#123).

### B4. Порожні стани й помилки через `ContentUnavailableView`

**Що зараз.** Три власні view: `PageErrorView` («Couldn't load this page»), `UnavailableView`, текстові підказки. `ContentUnavailableView` не використано.

**Що радить Apple.** `ContentUnavailableView` — стандартний спосіб показати відсутність вмісту: заголовок, опис, дії. Для пошуку є готовий варіант `ContentUnavailableView.search(text:)`.

**Що пропоную.**

```swift
ContentUnavailableView {
    Label("Couldn't load related music", systemImage: "wifi.exclamationmark")
} description: {
    Text("Check your connection and try again.")
} actions: {
    Button("Retry", action: onRetry)
}
```

Немає результатів пошуку → `.search(text: query)`. Помилка отримує причину й назву того, що не завантажилось.

**Зауваження.** Специфікація (08 §14.1) просить порожні стани «без ілюстрацій». Символ SF у `ContentUnavailableView` — це, по суті, ілюстрація; або уточнити правило, або передавати підпис без символу.

**Мінімальна версія:** macOS 14. **Закриває:** UX-23 (#132).

---

## C. Елементи керування та візуальна мова

### C1. Сімейство `ButtonStyle`

**Що зараз.** 63 кнопки з `.buttonStyle(.plain)` і жодного власного `ButtonStyle`. Вигляд кнопки живе в її мітці (`InversePillLabel`), тому немає стану натискання, вимкнений стан кожен малює сам, а біла пігулка використовується і для головних, і для другорядних дій (UX-17).

**Що радить Apple.** Стиль кнопки — це `ButtonStyle`: він бачить `configuration.isPressed` і `isEnabled`, а отже дає відгук на натискання в одному місці. Для елементів над вмістом на macOS 26 є скляні стилі кнопок (`.glass`, `.glassProminent` — звірити сигнатури).

**Що пропоную.**

```swift
struct PillButtonStyle: ButtonStyle {
    var isProminent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rwButton)
            .foregroundStyle(isProminent ? .textOnInverse : .textPrimary)
            .padding(.horizontal, Metrics.space16)
            .frame(height: Metrics.pillHeight)
            .background(isProminent ? .surfaceInverse : .surfaceFill, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : Metrics.unavailableOpacity)
    }
}
```

Плюс `IconButtonStyle` на заміну `BarIconButton`. Правило: `isProminent` — одна кнопка на екран (Play / Shuffle); More, Show all, Add, Save — звичайні. У листах головній кнопці дати `.keyboardShortcut(.defaultAction)`.

**Мінімальна версія:** macOS 14. **Закриває:** UX-17 (#126), частину UX-32 (#141).

### C2. Liquid Glass за настановами HIG

**Що зараз.** Скло стоїть на елементах верхньої панелі, полі пошуку, плеєр-барі й тості ([Glass.swift](../App/Theme/Glass.swift)); `GlassEffectContainer` використано. Картки й рядки скла не мають — це правильно.

**Що радить Apple (HIG, Materials).**
- Скло — окремий функціональний шар для керування й навігації, що «floats above the content layer».
- «Don't use Liquid Glass in the content layer».
- «Use Liquid Glass effects sparingly» — у власних елементах лише для найважливішого.
- Варіант regular розмиває тло й коригує його яскравість заради читабельності; його слід брати там, де багато тексту.

**Що пропоную.**
1. Плеєр-бар містить назву, виконавця й час — це «значна кількість тексту». Замість власного затемнення дати йому системний ефект краю (A1) і перевірити, що використано саме regular.
2. Сторінка артиста: фото зараз заходить під верхню панель через відʼємний відступ ([EntityScreen.swift:49](../App/Entity/EntityScreen.swift)) і обривається на межі бічної панелі. `backgroundExtensionEffect()` зроблено саме для цього: документація називає типовим випадком зображення в колонці detail, яке продовжується під бічну панель.
3. Тост лишити скляним — це тимчасовий елемент над вмістом.
4. Узгодити радіуси: бар із радіусом 20 pt лежить у вікні з власним радіусом; на macOS 26 є засоби для концентричних форм (звірити).

**Мінімальна версія:** macOS 26. **Закриває:** UX-05 (#114); покращує сторінку артиста.

### C3. Семантичні кольори й каталог ресурсів

**Що зараз.** Девʼять кольорів задано hex-константами ([DesignTokens.swift](../App/Theme/DesignTokens.swift)), тема завжди темна (`preferredColorScheme(.dark)` у `RootView` і міні-плеєрі), а Settings — світле (UX-25). Акцент для тумблерів підставляє власний `AccentSwitchToggleStyle`.

**Що радить Apple.** HIG (Color): стежити за контрастом між шаром вмісту й елементами керування; кольорам потрібні варіанти для різних умов. Каталог ресурсів дозволяє задати для одного кольору варіанти Dark і High Contrast, які система перемикає сама. Ієрархічні стилі `.primary` / `.secondary` / `.tertiary` підлаштовуються під матеріал, на якому лежать.

**Що пропоную.**
1. Перенести токени в каталог ресурсів із варіантом High Contrast — налаштування «Збільшити контраст» запрацює без коду.
2. Текст на склі й матеріалах малювати ієрархічними стилями, а не білим із фіксованою прозорістю.
3. Задати `AccentColor` у каталозі (фірмовий червоний) і прибрати `AccentSwitchToggleStyle` та ручні `.tint(.accentProgress)`.
4. Розвʼязати суперечність тем: або Settings теж темне (один рядок), або повна підтримка світлої теми. Постійно темний вигляд для медіазастосунку HIG допускає (розділ Dark Mode — формулювання звірити).

**Мінімальна версія:** macOS 14. **Ризик:** середній — зміна торкається кожного екрана; переносити варто токен за токеном. **Закриває:** частину UX-24 (#133), UX-25 (#134).

### C4. Типографіка

**Що зараз.** Дванадцять шрифтів через `Font.system(size:)`: 12, 14, 16, 24, 40 pt. Текстові стилі трапляються тричі (у Settings).

**Що радить Apple.** HIG (Typography): типовий розмір у macOS — 13 pt, мінімальний — 10 pt; радить вбудовані текстові стилі, бо вони задають ієрархію розміром і вагою та підтримують масштабування тексту там, де воно доступне.

**Оцінка.** Розміри в межах норми — менше 12 pt у застосунку немає. Проблема не в розмірах, а в тому, що вони не повʼязані із системою: основний текст 14 pt поруч із системними елементами на 13 pt (лист New playlist, Settings, меню) помітно відрізняється.

**Що пропоную.**
- Описати токени через текстові стилі (`.body`, `.headline`, `.title2`, `.largeTitle`) там, де розмір близький до системного; для навмисно більших (заголовок полиці, заголовок сторінки) лишити власні значення.
- Лірика й текст About: `.textSelection(.enabled)` — на Mac текст очікувано копіюється; для лірики ще й `.lineSpacing`.
- Обрізані назви: `.help(title)` на картках і рядках.

**Мінімальна версія:** macOS 14. **Закриває:** частину UX-22 (#131), UX-37 (#146).

### C5. SF Symbols: `Label` і переходи символів

**Що зараз.** 28 `Image(systemName:)` проти 7 `Label`; до кожної кнопки-іконки окремо дописано `.help` і `.accessibilityLabel` (51 мітка вручну). Зміна play/pause, рівнів гучності й лайка — миттєва заміна картинки.

**Що радить Apple.** `Label` несе і символ, і назву: назва автоматично стає міткою доступності, а `labelStyle(.iconOnly)` ховає текст візуально. Для зміни стану символу є `contentTransition(.symbolEffect(.replace))`; `symbolEffect` у коді вже використано для `waveform`.

**Що пропоную.** Кнопки-іконки будувати з `Label` + `.labelStyle(.iconOnly)`; play/pause, гучність і лайк перемикати через `.contentTransition(.symbolEffect(.replace))`; обраний стан — `.symbolVariant(.fill)`. Індикатор `waveform` показувати в рядках усіх щільностей, а не лише нумерованих.

**Мінімальна версія:** macOS 14. **Закриває:** UX-11 (#120).

### C6. Вкладки й розділи як сегментований `Picker`

**Що зараз.** Вкладки сторінки плеєра — власні кнопки 20 pt заввишки з підкресленням; розділи Library — горизонтально прокручуваний рядок чипів (той самий, що зник в UX-01).

**Що радить Apple.** Для перемикання між кількома поданнями одного вмісту — сегментований елемент керування. У SwiftUI це `Picker` зі стилем `.segmented`: стандартний розмір цілі, стрілки з клавіатури, озвучення «вкладка N з M», системний вигляд.

**Що пропоную.**

```swift
Picker("Player page tabs", selection: $selection) {
    ForEach(availableTabs, id: \.self) { Text($0.title).tag($0) }
}
.pickerStyle(.segmented)
.labelsHidden()
```

- Сторінка плеєра: Up next / Lyrics / Related (Comments не показувати, доки вкладки немає).
- Library: чотири розділи завжди влазять — горизонтальна прокрутка там не потрібна, а разом із нею зникає і сам клас помилки UX-01.
- Чипи настроїв на Home (десять і більше, з прокруткою) лишити власними, але як `Toggle` зі стилем `.button`, щоб обраний стан був семантичним.

**Мінімальна версія:** macOS 14. **Закриває:** вкладки з UX-21 (#130).

### C7. Черга й лірика в `.inspector` (варіант на рішення)

**Що зараз.** Сторінка плеєра — оверлей на всю колонку detail зі зсувом на живу ширину бічної панелі (`detailLeadingEdge`). Цей механізм уже двічі ламався: PR #106 і #107.

**Що радить Apple.** HIG (Toolbars) згадує «buttons that open nearby inspectors» у кінці toolbar; інспектор — бічна панель із відомостями про поточний вміст. У SwiftUI це `.inspector(isPresented:)` з `inspectorColumnWidth` (macOS 14); розкладку рахує система.

**Що пропоную розглянути.** Up next, Lyrics і Related — в інспекторі, який відкривається поруч із будь-якою сторінкою: можна гортати бібліотеку й бачити чергу чи текст пісні. Повноекранна сторінка плеєра лишається як окремий режим або зникає.

**Компроміс.** Це зміна задуму з 08 §10, а не полірування. Натомість зникає ручний облік ширини панелі й проблема «немає назви треку на сторінці».

**Мінімальна версія:** macOS 14. **Закриває:** частину UX-21 (#130) і UX-22 (#131).

---

## D. Рух

### D1. Пружинні анімації й проявлення обкладинок

**Що зараз.** Усі анімації — `easeOut` із тривалістю 0.12 або 0.2 с ([DesignTokens.swift](../App/Theme/DesignTokens.swift), `Motion.animation`); пружин немає. Обкладинки зʼявляються без переходу.

**Що радить Apple.** Починаючи з macOS 14 типова анімація SwiftUI — пружина; є готові `.smooth`, `.snappy`, `.bouncy`. Пружини зберігають швидкість при перериванні, тому швидкі повторні дії не смикаються.

**Що пропоную.** `Motion.animation` повертає `.snappy(duration:)` для наведення й панелей і `.smooth` для сторінки плеєра; перевірку Reduce Motion лишити. В `ArtworkImage` додати `.transition(.opacity)` з анімацією за значенням зображення.

**Мінімальна версія:** macOS 14. **Закриває:** частину UX-37 (#146).

---

## E. Вказівник, фокус, перевірки

### E1. Дрібні платформні звички й автоматичний аудит

- **Вказівник.** Для текстових посилань (виконавець і альбом у барі) — `.pointerStyle(.link)` (macOS 15, звірити).
- **Фокус.** `focusSection()` для трьох областей — бічна панель, вміст, бар — дає порядок Tab із 08 §14.4 без ручної логіки. Варто перевірити, чи `defaultFocus` замінить `InitialFocusClearer: NSViewRepresentable`.
- **Доступність прогресу.** Власна лінія прогресу вже має `accessibilityAdjustableAction`; `accessibilityRepresentation { Slider(…) }` зробить її для допоміжних технологій звичайним повзунком.
- **Автоматичний аудит.** У UI-тестах Xcode є `performAccessibilityAudit()`: він ловить малі цілі, брак міток і низький контраст. Один тест на кожен головний екран закриє частину ручної перевірки, якої аудит 09 не охопив.

**Закриває:** частину UX-24 (#133).

---

## F. Системні налаштування доступності

### F1. Прозорість, контраст, розрізнення без кольору

**Що зараз.** Reduce Motion враховано всюди. `accessibilityReduceTransparency`, `colorSchemeContrast`, `accessibilityDifferentiateWithoutColor` у коді не читаються.

**Що радить Apple.** Стандартні матеріали й компоненти реагують на ці налаштування самі; власні поверхні мають робити це явно через значення середовища.

**Що пропоную.**
- `WindowBackdrop` і `glassSurface`: при `accessibilityReduceTransparency` — непрозорий `themeBase`.
- Контраст: після C3 варіанти High Contrast візьме на себе каталог ресурсів.
- `accessibilityDifferentiateWithoutColor`: поточний трек, стан Repeat / Shuffle і тренди в чартах мають відрізнятися формою, а не лише кольором.

**Мінімальна версія:** macOS 14. **Закриває:** UX-24 (#133), UX-11 (#120).

---

## G. Форматування

### G1. Format styles замість `String(format:)`

**Що зараз.** Час форматується через `String(format:)` ([PlaybackRules.swift:43](../App/PlayerBar/PlaybackRules.swift)), а черга показує тривалість у власному форматі («63:02» замість «1:03:02»).

**Що радить Apple.** Форматування через `FormatStyle` (`Duration.formatted(.time(pattern:))`, `.number.notation(.compactName)`) враховує локаль і дає один формат на весь застосунок.

**Що пропоную.** Одна функція форматування тривалості на `Duration` і її використання в барі, списках і черзі. Рядки з числами, які складає сам застосунок («N selected»), вести через плюральні форми String Catalog — файл `Localizable.xcstrings` уже є.

**Мінімальна версія:** macOS 13. **Закриває:** формат тривалості з UX-21 (#130), частину UX-38 (#147).

---

## Що вже відповідає рекомендаціям Apple

Це варто зберегти під час змін:

- `NavigationSplitView` + `NavigationStack(path:)` з типізованими маршрутами;
- `@Observable` і `@Entry` замість старих `ObservableObject` і ключів середовища;
- сцена `Settings` з `TabView` і `Form` зі стилем `.grouped`; запуск при вході через `SMAppService`;
- команди меню через `CommandMenu` і `@FocusedValue`, з вимиканням недоступних пунктів;
- `confirmationDialog` з ролями `.destructive` і `.cancel` для видалення;
- `draggable` / `dropDestination` для перетягування треків;
- `onGeometryChange` замість `GeometryReader` (11 проти 2);
- послідовна підтримка Reduce Motion; String Catalog для локалізації;
- `GlassEffectContainer` для сусідніх скляних елементів, `containerBackground(for: .window)` для тла вікна;
- перевірки доступності API з запасним варіантом для старіших систем.

## Запропонований порядок

| Етап | Пропозиції | Чому так |
|---|---|---|
| 1. Швидкі здобутки | A4, B4, C5, C6, D1, E1, G1 | Малі, незалежні, майже без ризику |
| 2. Каркас | A1, потім перший крок A2; C1, B3, B2 | A1 прибирає причину UX-01 і готує ґрунт для toolbar |
| 3. Візуальна мова | C2, C3, C4, F1 | Після каркаса, бо скло й кольори залежать від того, де лежать панелі |
| 4. Рішення | другий крок A2, A3, B1, C7 | Змінюють звичну поведінку або задум — спершу вирішити, потім робити |

## Доступність API

Ціль — macOS 14, тож усе новіше потребує `if #available` і запасного варіанту.

| API | macOS | Статус |
|---|---|---|
| `safeAreaInset` | 12 | з памʼяті |
| `Table`, `.searchable` | 12 | `Table` підтверджено |
| `searchScopes`, `contextMenu(forSelectionType:)`, `focusSection` | 13 | з памʼяті, звірити |
| `ContentUnavailableView`, `.inspector`, `containerRelativeFrame`, `scrollTargetBehavior`, `symbolEffect`, пружини `.snappy` / `.smooth` | 14 | з памʼяті, звірити |
| `windowLevel` | 15 | підтверджено |
| `restorationBehavior`, `windowBackgroundDragBehavior`, `pointerStyle`, `searchFocused` | 15 | з памʼяті, звірити |
| `scrollEdgeEffectStyle` | 26 | підтверджено |
| `safeAreaBar`, `glassEffect`, `GlassEffectContainer`, `backgroundExtensionEffect` | 26 | існування підтверджено, версію звірити |
| Скляні стилі кнопок, концентричні форми | 26 | з памʼяті, звірити |
