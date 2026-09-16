# 001 · voicemode MVP — Research

Собрано 2026-09-16. Всё, что помечено **[?]**, найдено в одном слабом источнике или не
проверено. **[оценка]** — прикидка, а не замер.

## 1. Что уже есть

| Продукт | Движок | Управление и плашка | Чем выделяется | Цена |
|---|---|---|---|---|
| [Wispr Flow](https://wisprflow.ai) | облако, своя модель Canto (08.2026) | зажать Fn; двойное Fn — без рук; пилюля снизу, с 07.2026 перетаскивается к краю | «@file» в Cursor, видит имена переменных через режим скринридера; Command Mode | $15/мес |
| [superwhisper](https://superwhisper.com) | локально (Whisper, Parakeet) + облако; своя S1 | ⌥Space; окно с волной, режимом и живым текстом, либо мини-пилюля | режимы под приложения, Super Mode берёт контекст из выделения и буфера | ~$8,5/мес [?] |
| [Aqua Voice](https://aquavoice.com) | облако, модель Avalon | зажать Fn; текст через ~450 мс после отпускания | Deep Context читает экран, Edit Mode, «send it» | $8/мес |
| [VoiceInk](https://github.com/Beingpax/VoiceInk) | Whisper, Parakeet, Apple Speech, облака | event tap; плашка у выреза или снизу | ближайший аналог по коду; GPLv3 | $29–69 за сборку |
| [Handy](https://github.com/cjpais/Handy) | Whisper, Parakeet, GigaAM v3 | удержание или нажатие, порог 300 мс | обходит Secure Input, восстанавливает буфер только после того, как приложение его прочитало; MIT | бесплатно |
| FluidVoice | Parakeet, Apple SpeechAnalyzer | живой текст у выреза через DynamicNotchKit | цепочка из пяти способов вставки; GPLv3 | бесплатно |
| [Spokenly](https://spokenly.app) | локально или свои ключи | push-to-talk | MCP-сервер: агент задаёт вопрос, отвечаешь голосом | бесплатно / $9,99 |
| Claude Code `/voice` | облако Anthropic | удержание пробела | подсказки из имён проекта и ветки; работает только внутри Claude Code | в подписке |

**Выводы для нас.**

- Русский вперемешку с английскими терминами не решён ни у кого. По
  [Habr](https://habr.com/ru/articles/1024634/): Whisper large-v3 держит английские слова
  латиницей, turbo иногда переводит в кириллицу. GigaAM отлично понимает русский, но пишет
  «Jemni» вместо Gemini. Wispr Flow теряет русскую пунктуацию.
- Главная техническая боль — вставка в терминалы. Поле ввода Claude Code принимает только
  настоящую вставку ([#51725](https://github.com/anthropics/claude-code/issues/51725)).
- Люди уходят с подписок на локальные модели ([HN](https://news.ycombinator.com/item?id=49334327)).
  Живой текст называют «неожиданно важным» ([обзор 21 приложения](https://adamjones.me/blog/best-dictation-apps-2026/)).
- Ни одно open-source приложение не использует Liquid Glass (поиск по `glassEffect` и
  `NSGlassEffectView`).
- У Wispr Flow была история с отправкой скриншотов активного окна [?]
  ([пересказ](https://modelpiper.com/blog/wispr-flow-privacy-incident)). Отсюда наше правило: никаких
  скриншотов.

## 2. Локальное распознавание

| Движок | Размер | Скорость на M-серии | Русский | Английские термины | Живой текст | Лицензия |
|---|---|---|---|---|---|---|
| WhisperKit, large-v3-turbo (`large-v3-v20240930_626MB`) | 626 МБ | RTF 0,084 на M5 Pro, на M3 Pro ~0,1–0,15 [оценка] | на уровне large-v3 [?] | чаще уходит в кириллицу | простой цикл, на русском «прыгает» ([#206](https://github.com/argmaxinc/argmax-oss-swift/issues/206)) | MIT |
| WhisperKit, large-v3 (`large-v3_947MB`) | 947 МБ | в 3–5 раз медленнее turbo [оценка] | WER: FLEURS 3,1, CommonVoice 5,5 ([оценка GigaAM](https://github.com/salute-developers/GigaAM/blob/main/evaluation.md)) | в основном латиница | так же | MIT |
| whisper.cpp, turbo q5_0 | 574 МБ | близко к WhisperKit | те же веса | те же | наивный `whisper-stream`, встроенный Silero VAD | MIT |
| Parakeet TDT v3 ([FluidAudio](https://github.com/FluidInference/FluidAudio)) | ~0,5 ГБ | RTF ~0,005–0,009 | FLEURS 5,5 | смешанная речь уходит в английский целиком ([обсуждение](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3/discussions/1)) | окна по ~15 с | Apache-2.0 / CC-BY-4.0 |
| GigaAM v3 (sherpa-onnx) | 318 МБ int8 | RTF 0,03 | лучший: Golos crowd 2,4 | ломает английские слова | только пакетно | MIT |
| Apple `DictationTranscriber`, ru-RU | системный | RTF 0,017, режет сложный звук [?] | не опубликовано | неизвестно | лучший из коробки | система |
| Apple `SpeechTranscriber` | — | — | **русского нет** (проверено на этом Mac, macOS 27.0) | — | — | — |

**Факты, которые повлияли на дизайн:**

- **WhisperKit переименован в [`argmax-oss-swift`](https://github.com/argmaxinc/argmax-oss-swift/releases).**
  Версия 1.1.0 от 2026-08-06; в ней починили пустой вывод при `promptTokens` (#514).
- **Имена моделей обманчивы.** `large-v3-v20240930*` — это turbo. Суффикс `_turbo` означает
  ускоренный декодер Argmax. `distil-large-v3` — только английский.
- **Подготовка Core ML под чип при первой загрузке долгая:** turbo на M1 Pro ~10 минут
  ([#268](https://github.com/argmaxinc/argmax-oss-swift/issues/268)). После обновления macOS кеш
  сбрасывается.
- **`download()` лезет в сеть, даже когда файлы уже есть**
  ([#468](https://github.com/argmaxinc/argmax-oss-swift/issues/468)). Грузить из `modelFolder` с
  `download: false`.
- **Утечка ~50 МБ при пересоздании `AudioStreamTranscriber`** (#517). Поэтому свой цикл.
- **Задержка ~0,45 с из статьи Argmax — это платный Pro SDK**
  ([сравнение](https://app.argmaxinc.com/docs/wiki/open-source-vs-pro-sdk)). Pro стоит
  $1,33 за устройство в месяц при минимуме 1000 лицензий — не для нас.
- **Живой текст:** политика LocalAgreement-2 из
  [ufal/whisper_streaming](https://github.com/ufal/whisper_streaming).
- **Галлюцинации Whisper на русском:**
  [список](https://gist.github.com/waveletdeboshir/8bf52f04bf78018194f25b2390c08309).

## 3. Локальное оформление текста

| Вариант | Размер | Задержка на ~150 слов, M3 Pro | Русский | Риск переписать смысл | Лицензия |
|---|---|---|---|---|---|
| Apple Foundation Models | системная | — | **не поддерживается** ([доступность](https://www.apple.com/ios/feature-availability/)) | — | — |
| RUPunct_big (BERT) | 711 МБ fp32 | ~20–60 мс [оценка] | лучший из BERT по запятым (по словам авторов) | нет, только расставляет метки | MIT |
| RUPunct_small | 116 МБ | < 10 мс [оценка] | слабее | нет | MIT |
| Silero TE | малый | быстро | нормально | нет | **CC BY-NC**, не подходит |
| Qwen3.5-0.8B 4 бит (MLX) | ~0,5 ГБ | ~1,3 с, с PLD ~0,8 с [оценка] | средне без дообучения | средний–высокий | Apache-2.0 |
| Qwen3.5-2B 4 бит (MLX) | ~1,2 ГБ | ~3 с, с PLD ~1,6 с [оценка] | хорошо | средний | Apache-2.0 |
| GigaChat3.1 Lightning | 6,5 ГБ | ~3–5 с [оценка] | лучший русский | средний | MIT |
| superwhisper S1-mini | 462 МБ | < 1 с | **только английский** | низкий | Apache-2.0 |

**Что узнали:**

- **Скорость LLM упирается в генерацию.** Оформить 150 слов — это переписать ~300 токенов. В 1–2 с
  на M3 Pro укладываются только модели до 2B. Ускоряет prompt-lookup decoding (PLD): большая
  часть ответа совпадает со входом. В приложении
  [pomvox](https://github.com/pomvox/pomvox/pull/145) генерация на M1 ускорилась вдвое, а оформление — с 1,68 до 1,1 с.
- **Длинные русские отрезки turbo оставляет без пунктуации.**
  [Дообучение](https://huggingface.co/coriollon/whisper-large-v3-turbo-russian) подняло F1 границ
  предложений с 0,45 до 0,81. Русский prompt с пунктуацией помогает, но иногда протекает в
  вывод ([openai/whisper #1150](https://github.com/openai/whisper/discussions/1150)).
- **Промпт VoiceInk** (`Core/Enhancement/AIPrompts.swift`, GPLv3) — хороший ориентир по правилам:
  не менять смысл, списки вертикально, абзацы до трёх предложений, вопросы в тексте — это
  содержимое, а не вопрос к модели. Код не копируем.
- **S1-mini** показывает, что дообученная 0.6B справляется с оформлением. Для русского такой
  модели нет — кандидат на работу после MVP.
- **В macOS 27 появился протокол `LanguageModel`,** mlx-swift-lm его уже реализует. Когда Apple
  добавит русский, модель можно будет заменить без переписывания.

## 4. Интеграция с macOS

**Liquid Glass.**

- **API с macOS 26:**
  - SwiftUI: `glassEffect(_:in:)`, `Glass.regular / .clear / .tint / .interactive`,
    `GlassEffectContainer`, `glassEffectID`, `.buttonStyle(.glass)`;
  - AppKit: `NSGlassEffectView`, `NSGlassEffectContainerView`.
  ([гайд Apple](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views))
- **Нового в macOS 27:**
  - `NSGlassEffectView.effectIsInteractive`, `NSView.cornerConfiguration`
    ([WWDC26 289](https://developer.apple.com/videos/play/wwdc2026/289/));
  - системное стекло стало плотнее;
  - у пользователя слайдер «прозрачное ↔ тонированное».
- **HIG:** стекло для плавающих элементов, не для контента. `.clear` — только над пёстрым фоном
  ([Materials](https://developer.apple.com/design/human-interface-guidelines/materials)).
- **Окно без рамки само стекло не получает:** `NSGlassEffectView` как contentView,
  `backgroundColor = .clear`, `isOpaque = false`
  ([onmyway133](https://github.com/onmyway133/blog/issues/1025)).
- **Регрессия 26.2:** в неперемещаемом окне без рамки фон стекла «замерзает»
  ([форум 810314](https://developer.apple.com/forums/thread/810314)).
- **Читаемость поверх движущегося контента** — известная слабость стекла, поэтому нужен тёмный
  вариант плашки.

**Плашка без фокуса** (по [VoiceInk](https://github.com/Beingpax/VoiceInk)):

- `NSPanel` с `[.nonactivatingPanel, .fullSizeContentView]`, `hidesOnDeactivate = false`,
  `orderFrontRegardless()`;
- поведение `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`;
- переключить приложение в `.accessory` до создания панели, иначе она не попадёт на полноэкранные
  рабочие столы ([Tiro](https://github.com/tbuettgen/tiro/pull/1)).

**Горячие клавиши.**

- **[KeyboardShortcuts 3.1.0](https://github.com/sindresorhus/KeyboardShortcuts/releases)**
  (2026-09-11): без разрешений, видит отпускание, но не умеет Fn и одиночные модификаторы.
- **Удержание Fn:** `CGEvent.tapCreate` на `flagsChanged`, keycode 63.
- **Разрешения:** слушать события — Input Monitoring, отправлять — Accessibility
  ([форум 820594](https://developer.apple.com/forums/thread/820594)).
- **Secure Input глушит event tap,** Carbon-хоткеи продолжают работать
  ([uttrflow #608](https://github.com/uttrflow/uttrflow-swift/issues/608)).
- **Переподписанная сборка** может оставить tap, который выглядит включённым, но ничего не получает
  ([raffel](https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/)).

**Вставка.**

- **Буфер + ⌘V — отраслевой стандарт.** Рецепт VoiceInk
  ([CursorPaster](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Infrastructure/SystemIntegration/Paste/CursorPaster.swift)):
  - снимок буфера;
  - пометки [nspasteboard.org](http://nspasteboard.org/);
  - 100 мс, затем ⌘V через `CGEventSource(.privateState)`;
  - восстановление через ≥ 250 мс, если в буфере всё ещё наш маркер.
- **TypeWhisper:** 150 / 350 / 900 мс для терминалов.
- **OpenWhispr** ищет клавишу V в текущей раскладке и прямо предупреждает не считать её
  американской.
- **Accessibility API** в Chromium-приложениях (Slack) принимает запись и молча её теряет
  ([aside](https://github.com/cmwright/aside)).
- **`keyboardSetUnicodeString`:** до 20 символов за событие, текст теряется в терминалах xterm.js
  с kitty-протоколом.

**Перетаскивание.**

- **Первый клик в неактивной панели проглатывается** → `acceptsFirstMouse`
  ([Tietze](https://christiantietze.de/posts/2024/04/enable-swiftui-button-click-through-inactive-windows/)).
- **Регрессия 26.2:** вложенные `NSHostingView` теряют события мыши
  ([форум 812113](https://developer.apple.com/forums/thread/812113)).
- **Terminal при сбросе файла вставляет его путь,** поэтому отдаём простой текст.

**Распространение.**

- **App Sandbox несовместим** с Accessibility API и программным ⌘V.
- **Sparkle 2.10.0** (2026-09-13): требует macOS 12+, чинит дельта-обновления на 27.
- **Запуск при входе:** `SMAppService.mainApp.register()`.
- **Swift 6:** tap `AVAudioEngine`, созданный на главном акторе, падает на аудиопотоке
  ([YapToText #6](https://github.com/ryleighnewman/YapToText/issues/6)).

## 5. Дизайн

**CleanMyMac.**

- **Редизайн 2024:** 3D-интерфейс, шесть модулей, плитки результатов
  ([MacStories](https://www.macstories.net/reviews/macpaw-updates-cleanmymac-with-a-fresh-design-and-new-tools/)).
- **Инструменты:** 3D в Cinema 4D / Blender, анимации в After Effects и Rive
  ([Dribbble MacPaw](https://dribbble.com/MacPaw/shots)).
- **Жюри [UX Design Awards](https://ux-design-awards.com/events-media/deep-dive-award-winners-macpaw-inc)**
  отметило «ровно столько визуального отклика, сколько нужно, и ровно тогда».
- **Приём [?]:** на экране один 3D-объект, одна главная круглая кнопка внизу, свой насыщенный
  цвет у модуля.

**Онбординги.**

- **[Wispr Flow](https://docs.wisprflow.ai/articles/3152211871-setup-guide):**
  - карточка микрофона сама переходит дальше, когда доступ выдан;
  - тест микрофона с волной;
  - клавиша задаётся нажатием;
  - «попробуй» с кнопкой пропуска.
- **[Ice](https://github.com/jordanbaird/Ice):**
  - карточка на разрешение со списком «зачем»;
  - опрос статуса раз в секунду, диплинк в настройки;
  - «Продолжить в ограниченном режиме».
- **[PermissionFlow](https://github.com/jaywcjlove/PermissionFlow)** (MIT): плавающий помощник,
  который показывает, куда перетащить приложение в списке разрешений.
- **[Raycast](https://manual.raycast.com/settings):** онбординг можно открыть повторно. Никаких
  веб-привычек в десктопе: без курсора-руки и без hover-подсветок.

**Остров у выреза.**

- **[DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)** (MIT):
  - `NotchShape` с анимируемыми радиусами; вогнутый верхний угол — `addQuadCurve`;
  - радиусы 15/20;
  - открытие `.bouncy(0.4)`, закрытие `.smooth(0.4)`;
  - вырез определяется по `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`;
  - без выреза — 300 × высота строки меню.
- **boring.notch** и **Atoll** — GPLv3, только читать. В полноэкранных приложениях у выреза
  чёрная полоса, остров с ней сливается
  ([Panaitiu](https://notes.alinpanaitiu.com/Fullscreen-apps-above-the-MacBook-notch)).

**Плашка записи.**

- **Неподвижная пилюля Wispr Flow** получила 700+ жалоб: перекрывала кнопки. Её сделали
  перетаскиваемой ([Yahoo](https://tech.yahoo.com/apps/articles/wispr-flow-finally-fixed-toolbar-103632302.html)).
- **Волна VoiceInk:** 15 полос по 3 pt с зазором 2 pt, высота 4–28 pt, `TimelineView` 60 fps.
- **Честная волна:** ровная, когда микрофон молчит.
- **Хаптика трекпада** срабатывает только при касании. Во время удержания Fn руки на клавиатуре,
  так что хаптика — только для перетаскивания.

**Анимация.**

- PhaseAnimator и KeyframeAnimator, шейдеры `.layerEffect`
  ([Inferno](https://github.com/twostraws/Inferno), MIT).
- `MeshGradient` (macOS 15).
- `TextRenderer` — слова проявляются по одному
  ([fatbobman](https://fatbobman.com/en/posts/creating-stunning-dynamic-text-effects-with-textrender/)).
- SF Symbols 7 Draw On/Off — галочки разрешений.
- [Rive](https://rive.app/docs/runtimes/apple/apple) поддерживает macOS 13.1+ и подходит для
  клавиши Fn, которая реагирует на нажатие.
