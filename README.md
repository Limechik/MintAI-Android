# MintAI

A privacy-focused AI chat client for Android, built with Flutter and Material 3.
Bring your own API key: talk to DeepSeek, OpenAI, Claude, Gemini, Mistral, OpenRouter, OpenCode Zen,
any OpenAI-compatible server, or a local model running on your own PC.

> **Русская версия — ниже / Russian version below.**

<!-- Add screenshots to docs/screenshots and uncomment:
<p>
  <img src="docs/screenshots/chat.png" width="240">
  <img src="docs/screenshots/history.png" width="240">
  <img src="docs/screenshots/settings.png" width="240">
</p>
-->

## Features

**Chat**
- Three tabs: **Chat**, **Chat history**, **Settings**; Material 3 with light and dark themes (seed color `#3EB489`)
- Many providers, switchable on the fly, with a per-provider URL, key and model
- System instruction, searchable history, swipe to delete
- Add a photo to a message (vision models) and generate images (OpenAI / OpenRouter) from the **+** menu
- Voice input (Android speech recognition) and voice output ([VoxSynth](https://github.com/Limechik/VoxSynth), Russian, male/female voice)
- English and Russian interface
- Three app icons (mint by default, graphite, blue), switchable in Settings

**Privacy and security**
- Chat history, API keys and attached photos are stored **encrypted** (AES-256-GCM); the key is generated on the device and kept in the Android Keystore
- **Incognito mode**: chats are kept in memory only, never written to disk, screenshots are blocked
- **App lock**: PIN (salted PBKDF2 hash, growing delay after wrong attempts) and optional biometrics
- Optional **screenshot blocking** and hidden preview in the recent apps list
- No analytics, no ads, no trackers. The app talks only to the provider you configure

## Providers

| Provider | API | Default base URL |
|---|---|---|
| DeepSeek | OpenAI-compatible | `https://api.deepseek.com/v1` |
| OpenAI | OpenAI | `https://api.openai.com/v1` |
| Claude | Anthropic Messages API | `https://api.anthropic.com/v1` |
| OpenRouter | OpenAI-compatible | `https://openrouter.ai/api/v1` |
| Mistral | OpenAI-compatible | `https://api.mistral.ai/v1` |
| Gemini | OpenAI-compatible endpoint | `https://generativelanguage.googleapis.com/v1beta/openai` |
| OpenCode Zen | OpenAI-compatible (`/chat/completions`) | `https://opencode.ai/zen/v1` |
| Custom | any OpenAI-compatible server | your URL |
| Local model | Ollama, LM Studio, llama.cpp on your PC or server | e.g. `http://192.168.0.10:11434/v1` |

Default model names are only suggestions and can be changed. Press **Models** in the provider settings to load the list from the server
(this also works as a connection test).

### Local models

Run the model on your PC or server; the phone connects over your network.

- **Ollama:** start it with `OLLAMA_HOST=0.0.0.0`, then use `http://<PC-IP>:11434/v1`
- **LM Studio:** enable *Local Server* and *Serve on local network*, then use `http://<PC-IP>:1234/v1`
- The phone and the PC must be on the same network, and the port must be open in the firewall. An API key is optional.

### Image generation

Settings → Images. Uses the key and URL of the matching provider:
**OpenAI** (`/images/generations`) or **OpenRouter** (a model with image output). The model name is editable.

## Privacy notes

- Your messages, photos and keys go **only** to the provider you chose. The app has no server of its own.
- The encryption key is bound to the device (Android Keystore), not derived from your PIN. The PIN and biometrics lock the app UI.
  Android backup is disabled so that encrypted data is never restored without its key.
- **Voice input** uses the speech recognition service of your Android system. On most phones that is Google's, which may send audio to its servers
  unless an offline language pack is installed. The app itself never stores audio.
- Voice output runs fully offline on the device.

## Build

Requirements: Flutter (stable), JDK 17, Android SDK with **NDK** and **CMake** (needed for the VoxSynth native library).

```bash
flutter pub get
flutter run                      # debug on a connected device
flutter build apk --release      # release APK
```

`minSdk` is 23. Release builds need your own signing config (see the Flutter docs).

### Project layout

```
lib/
  main.dart       app, state, chat, history, settings, providers
  lock.dart       PIN, biometrics, lock screen, screenshot guard
  secure.dart     AES-256-GCM, Keystore-backed key
  images.dart     encrypted storage for photos
  vox.dart        text-to-speech via dart:ffi
  i18n.dart       English/Russian strings
  app_icon.dart   app icon switching
native/voxsynth/  VoxSynth C sources + FFI wrapper (built with CMake)
android/          MainActivity, manifest (icon aliases, permissions)
```

## Known limitations

- Android only.
- Voice output is Russian only; the speaker button is hidden for non-Russian text.
- Images and photos work only with models that support them.
- OpenCode Zen models that require `/messages` or `/responses` instead of `/chat/completions` are not supported yet.
- On some launchers the home-screen shortcut disappears after changing the app icon; add it again.
- Language of AI replies is decided by the model, not by the interface language.

## Contributing

Issues and pull requests are welcome. Please keep the app free of trackers and proprietary dependencies (F-Droid friendly).
Telegram: [@LimeDeveloper](https://t.me/LimeDeveloper)

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).

The text-to-speech engine is [VoxSynth](https://github.com/Limechik/VoxSynth) (GPL-3.0), which is why the whole app is GPL-3.0.
Main Flutter packages: `http`, `shared_preferences`, `flutter_secure_storage`, `cryptography`, `local_auth`,
`image_picker`, `path_provider`, `audioplayers`, `speech_to_text`, `ffi`.

---

<details>
<summary><b>🇷🇺 Русская версия</b></summary>

# MintAI

Приватный ИИ-клиент для Android на Flutter в стиле Material 3. Используйте свой API-ключ и общайтесь с DeepSeek, OpenAI, Claude, Gemini,
Mistral, OpenRouter, OpenCode Zen, любым OpenAI-совместимым сервером или локальной моделью на вашем ПК.

## Возможности

**Чат**
- Три вкладки: **Чат**, **История чатов**, **Настройки**; Material 3, светлая и тёмная темы (цвет `#3EB489`)
- Много провайдеров с переключением на лету; у каждого свои адрес, ключ и модель
- Системная инструкция, поиск по истории, удаление свайпом
- Меню **+**: добавить фото (для моделей с поддержкой изображений) и сгенерировать изображение (OpenAI / OpenRouter)
- Голосовой ввод (распознавание речи Android) и озвучка ответов ([VoxSynth](https://github.com/Limechik/VoxSynth), русский, мужской/женский голос)
- Интерфейс на русском и английском
- Три иконки приложения (по умолчанию мятная, графит, синяя)

**Приватность и безопасность**
- История чатов, API-ключи и фото хранятся **в зашифрованном виде** (AES-256-GCM); ключ создаётся на устройстве и лежит в Android Keystore
- **Режим инкогнито**: чаты только в памяти, на диск не пишутся, скриншоты запрещены
- **Блокировка приложения**: PIN (хэш PBKDF2 с солью, растущая задержка после ошибок) и биометрия
- Запрет скриншотов и скрытие содержимого в списке недавних приложений
- Ни аналитики, ни рекламы, ни трекеров. Приложение общается только с выбранным вами провайдером

## Локальные модели

Модель работает на вашем ПК или сервере, телефон подключается по сети.

- **Ollama:** запустите с `OLLAMA_HOST=0.0.0.0` и укажите `http://<IP-ПК>:11434/v1`
- **LM Studio:** включите Local Server и «Serve on local network», адрес `http://<IP-ПК>:1234/v1`
- Телефон и ПК должны быть в одной сети, порт открыт в брандмауэре. API-ключ не обязателен.

Кнопка **Модели** в настройках провайдера загружает список моделей с сервера и заодно проверяет соединение.

## О приватности

- Сообщения, фото и ключи уходят **только** выбранному провайдеру. Собственного сервера у приложения нет.
- Ключ шифрования привязан к устройству (Keystore) и не выводится из PIN. PIN и биометрия блокируют интерфейс приложения.
  Резервное копирование Android отключено, чтобы зашифрованные данные не восстанавливались без ключа.
- **Голосовой ввод** использует системную службу распознавания речи Android. На большинстве телефонов это Google: звук может уходить на его
  серверы, если не установлен офлайн-пакет языка. Само приложение звук не сохраняет.
- Озвучка работает полностью офлайн.

## Сборка

Нужны: Flutter (stable), JDK 17, Android SDK с **NDK** и **CMake** (для нативной библиотеки VoxSynth).

```bash
flutter pub get
flutter run
flutter build apk --release
```

`minSdk` 23. Для release-сборки нужна своя подпись.

## Ограничения

- Только Android.
- Озвучка только на русском: для нерусского текста кнопка динамика скрыта.
- Фото и изображения работают только с моделями, которые их поддерживают.
- Модели OpenCode Zen, которым нужны `/messages` или `/responses`, пока не поддерживаются.
- На некоторых лаунчерах после смены иконки пропадает ярлык: добавьте приложение на экран заново.
- Язык ответов ИИ определяет сама модель, а не язык интерфейса.

## Лицензия

GPL-3.0-or-later, см. [LICENSE](LICENSE). Движок озвучки [VoxSynth](https://github.com/Limechik/VoxSynth) распространяется под GPL-3.0,
поэтому всё приложение тоже под GPL-3.0.

Связь: Telegram [@LimeDeveloper](https://t.me/LimeDeveloper)

</details>
