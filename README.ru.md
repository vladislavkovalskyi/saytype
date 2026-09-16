<p align="center">
  <img src="docs/media/icon.png" width="128" height="128" alt="Иконка saytype">
</p>

<h1 align="center">saytype</h1>

<p align="center">
  Зажми <kbd>fn</kbd>, скажи, отпусти. Текст с запятыми, абзацами и списками появится в любом приложении.<br>
  Whisper работает на твоём Mac, звук никуда не уходит.
</p>

<p align="center">
  <a href="https://github.com/vladislavkovalskyi/saytype/releases/latest/download/saytype.dmg"><img src="docs/media/download.svg" height="44" alt="Скачать для macOS"></a>
</p>

<p align="center">
  macOS 26+ · Apple Silicon · Бесплатно, открытый код · <a href="README.md">English</a>
</p>

<p align="center">
  <img src="docs/media/hero.png" width="880" alt="Остров saytype у выреза показывает живой текст во время диктовки в терминал">
</p>

## Зачем

- **Текст виден, пока говоришь.** Слова появляются в острове у выреза прямо во время речи.
- **Русский и английский в одной фразе.** Скажи «поправь useEffect в Header» и получишь `useEffect` так, как он пишется в коде, а не «юз эффект».
- **Текст сразу оформлен.** Знаки препинания, абзацы по паузам, нумерованный список, когда перечисляешь. Маленькая локальная модель расставляет структуру в длинных диктовках и не меняет слова.
- **Офлайн.** Распознавание и оформление идут на Neural Engine и GPU. Сеть нужна только для загрузки моделей.

Сделано для тех, кто весь день говорит с агентами: Claude Code, Cursor, Codex, терминал, браузер, мессенджеры.

## Установка

Проще всего через Homebrew:

```sh
brew install --cask vladislavkovalskyi/tap/saytype
```

Или [скачай saytype.dmg](https://github.com/vladislavkovalskyi/saytype/releases/latest/download/saytype.dmg) и перетащи saytype в «Программы».

Открой. Первый запуск проведёт через выбор клавиши, микрофон и разрешения и скачает Whisper (632 МБ).

> [!NOTE]
> saytype бесплатный и не нотаризован Apple: нотаризация стоит $99 в год. После установки из DMG macOS может не открыть приложение с первого раза: открой **Системные настройки → Конфиденциальность и безопасность** и нажми **Всё равно открыть**, или выполни
> `xattr -dr com.apple.quarantine /Applications/saytype.app`. Homebrew делает это сам.

## Как пользоваться

| | |
|---|---|
| держать <kbd>fn</kbd> | запись, отпустил — вставка |
| дважды <kbd>fn</kbd> | запись без рук, ещё раз — стоп |
| <kbd>esc</kbd> | отмена |
| <kbd>⌃</kbd><kbd>⌥</kbd><kbd>V</kbd> | вставить последнюю диктовку ещё раз |
| <kbd>⌃</kbd><kbd>⌥</kbd><kbd>C</kbd> | скопировать последнюю диктовку |

Клавиша записи: <kbd>fn</kbd>, правый <kbd>⌥</kbd> или правый <kbd>⌘</kbd>. Наведи курсор на вырез: откроется панель с кнопкой записи, последней диктовкой, языком, структурой и микрофоном.

## Модели

| Модель | Размер | Что делает |
|---|---|---|
| Whisper large-v3-turbo через [WhisperKit](https://github.com/argmaxinc/WhisperKit) | 632 МБ | речь в текст на Neural Engine, живой и финальный проход |
| Qwen3 1.7B 4-bit через [MLX](https://github.com/ml-explore/mlx-swift-lm) | 944 МБ, по желанию | размечает предложения как абзацы или пункты списка; текст собирается из меток, слова не меняются |

Модели лежат в `~/Library/Application Support/dev.kovalskyi.saytype/Models` и скачиваются с Hugging Face при первом запуске.

На M3 Pro фраза в 5 секунд готова примерно через 1,2 с после отпускания клавиши. Умная структура добавляет ~0,6 с к длинным диктовкам и пропускается для коротких.

## Приватность

- Звук обрабатывается в памяти и не пишется на диск.
- История диктовок — локальный JSON-файл, её можно очистить или ограничить срок хранения.
- Ни аккаунтов, ни аналитики. Сеть нужна только для загрузки моделей и проверки обновлений.

## Разрешения

| Разрешение | Зачем |
|---|---|
| Микрофон | слушать, пока зажата клавиша записи |
| Мониторинг ввода | замечать клавишу записи в любом приложении |
| Универсальный доступ | вставлять текст в активное поле |

saytype вставляет через буфер обмена и возвращает прежнее содержимое. В поля паролей не вставляет.

## Вопросы

**Текст не вставляется.** Проверь saytype в «Универсальном доступе». Если обновление сменило подпись, удали saytype из списка и добавь снова.

**fn открывает эмодзи.** Системные настройки → Клавиатура → «Нажатие клавиши 🌐» → «Ничего не делать», или выбери правый ⌥ клавишей записи.

**Первый запуск долгий.** Core ML один раз готовит Whisper под твой чип, это 2–3 минуты. Дальше запуск занимает секунды.

**Сбросить всё.** `tccutil reset All dev.kovalskyi.saytype` и удалить `~/Library/Application Support/dev.kovalskyi.saytype`.

## Сборка из исходников

Нужны Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) и компонент Metal Toolchain.

```sh
brew install xcodegen
xcodebuild -downloadComponent MetalToolchain
xcodegen generate
open saytype.xcodeproj
```

Логика — в Swift-пакете `Packages/SaytypeKit`, тесты: `swift test --skip VMTranscriptionTests`. Техдизайн — в [`docs/dev`](docs/dev).

## Автор

Vladislav Kovalskyi.
[GitHub](https://github.com/vladislavkovalskyi) · [Telegram @yxuxo](https://t.me/yxuxo)

Внутри [WhisperKit](https://github.com/argmaxinc/WhisperKit), [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm), [swift-transformers](https://github.com/huggingface/swift-transformers), [Sparkle](https://sparkle-project.org), OpenAI Whisper и Qwen3. Шрифты [Onest](https://github.com/simpals/onest) и [JetBrains Mono](https://www.jetbrains.com/lp/mono/) под лицензией OFL.

## Лицензия

[MIT](LICENSE)
