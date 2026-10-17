import 'package:flutter/material.dart' as m;

/// Язык интерфейса. Внутри приложения все строки написаны по-русски и служат
/// ключами: при выборе English они переводятся словарём ниже. Значения настроек
/// (например, «Женский») хранятся русскими, переводится только отображение.
class Lang {
  static bool en = false;
  static void set(String lang) => en = lang == 'English';
}

/// Перерисовывает все Text при смене языка (в том числе const-виджеты).
class LangScope extends m.InheritedWidget {
  final bool en;
  const LangScope({super.key, required this.en, required super.child});
  @override
  bool updateShouldNotify(LangScope old) => en != old.en;
}

/// Text, который сам переводит строку. Подставляется вместо Text из Flutter.
class Text extends m.StatelessWidget {
  final String data;
  final m.TextStyle? style;
  final m.TextAlign? textAlign;
  final int? maxLines;
  final m.TextOverflow? overflow;
  final bool? softWrap;
  const Text(this.data,
      {super.key, this.style, this.textAlign, this.maxLines, this.overflow, this.softWrap});

  @override
  m.Widget build(m.BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<LangScope>();
    return m.Text(tr(data),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap);
  }
}

final _cyr = RegExp(r'[А-Яа-яЁё]');
final _lat = RegExp(r'[A-Za-z]');

/// Озвучка VoxSynth читает только по-русски: кнопку показываем для русского текста.
bool looksRussian(String t) => _cyr.allMatches(t).length >= _lat.allMatches(t).length;

/// Перевод строки. Точное совпадение берётся из словаря, строки с подстановками
/// («Ошибка: {}») сопоставляются по шаблону. Незнакомый текст возвращается как есть.
String tr(String ru) {
  if (!Lang.en || !_cyr.hasMatch(ru)) return ru;
  final hit = _en[ru];
  if (hit != null) return hit;
  for (final (re, tpl) in _templates) {
    final mt = re.firstMatch(ru);
    if (mt != null) {
      var i = 1;
      return tpl.replaceAllMapped('{}', (_) => mt.group(i++) ?? '');
    }
  }
  return ru;
}

final List<(RegExp, String)> _templates = [
  for (final e in _en.entries)
    if (e.key.contains('{}'))
      (
        RegExp('^${RegExp.escape(e.key).replaceAll(r'\{\}', '(.+?)')}\$', dotAll: true),
        e.value
      ),
];

const Map<String, String> _en = {
  'Скоро появится': 'Coming soon',
  'Локальная модель': 'Local model',
  'Женский': 'Female',
  'Мужской': 'Male',
  '📷 Фото': '📷 Photo',
  'Ошибка: {}': 'Error: {}',
  'Ошибка генерации: {}': 'Generation error: {}',
  'HTTP {}: ответ не похож на API, проверьте Base URL': 'HTTP {}: the response does not look like an API, check the Base URL',
  'Выкл.': 'Off',
  'генерация выключена: Настройки → Изображения': 'generation is off: Settings → Images',
  'добавьте API-ключ для «{}» в Настройки → Чат': 'add an API key for “{}” in Settings → Chat',
  'модель не вернула изображение (проверьте модель)': 'the model returned no image (check the model)',
  'Добавьте API-ключ для «{}» в Настройки → Чат.': 'Add an API key for “{}” in Settings → Chat.',
  'Чат': 'Chat',
  'История чатов': 'Chat history',
  'Настройки': 'Settings',
  'Добавить фото': 'Add photo',
  'Сгенерировать изображение': 'Generate image',
  'Не удалось выбрать фото: {}': 'Could not pick a photo: {}',
  'Генерация выключена: Настройки → Изображения': 'Generation is off: Settings → Images',
  'Опишите, что нарисовать': 'Describe what to draw',
  'Отмена': 'Cancel',
  'Создать': 'Create',
  'Новый чат': 'New chat',
  'Инкогнито — {}': 'Incognito — {}',
  'Выключить инкогнито': 'Turn off incognito',
  'Режим инкогнито': 'Incognito mode',
  'Инкогнито включён: чат не сохраняется': 'Incognito on: this chat is not saved',
  'Инкогнито выключен': 'Incognito off',
  'Провайдер': 'Provider',
  'Режим инкогнито\nЭтот чат не будет сохранён.': 'Incognito mode\nThis chat will not be saved.',
  'Привет! Я "{}"\nНапиши сообщение.': 'Hi! I am "{}"\nWrite a message.',
  'Сообщение…': 'Message…',
  'Озвучка: {}': 'Speech: {}',
  'Озвучить': 'Read aloud',
  'Сегодня': 'Today',
  'Очистить всё': 'Clear all',
  'Удалить всю историю?': 'Delete all history?',
  'Удалить': 'Delete',
  'Поиск по истории': 'Search history',
  'Ничего нет': 'Nothing here',
  'Системная': 'System',
  'Светлая': 'Light',
  'Тёмная': 'Dark',
  'Инструкция': 'Instructions',
  'Например: отвечай кратко': 'E.g. keep answers short',
  'Сохранить': 'Save',
  'ИИ': 'AI',
  'Изображения': 'Images',
  'Не задана': 'Not set',
  'Приложение': 'App',
  'Голос': 'Voice',
  'Оформление': 'Appearance',
  'Иконка': 'Icon',
  'Приватность': 'Privacy',
  'PIN + биометрия': 'PIN + biometrics',
  'Чаты не сохраняются, скриншоты запрещены': 'Chats are not saved, screenshots are blocked',
  'Блокировка': 'App lock',
  'Запретить скриншоты': 'Block screenshots',
  'Скрывает приложение в списке недавних. В инкогнито включено всегда': 'Hides the app in the recents list. Always on in incognito',
  'Шифрование': 'Encryption',
  'История чатов и API-ключи хранятся в зашифрованном виде (AES-256-GCM). Ключ шифрования создаётся на устройстве и лежит в защищённом хранилище Android (Keystore). Чаты в режиме инкогнито никуда не записываются.': 'Chat history and API keys are stored encrypted (AES-256-GCM). The encryption key is created on the device and kept in Android secure storage (Keystore). Incognito chats are never written anywhere.',
  'Автор': 'Author',
  'Скопировано': 'Copied',
  'Сервер вернул пустой список': 'The server returned an empty list',
  'Модели ({})': 'Models ({})',
  'Не удалось подключиться: {}': 'Could not connect: {}',
  'Модель работает на вашем ПК или сервере, телефон подключается по сети. Укажите IP компьютера: http://192.168.0.10:11434/v1 (Ollama) или :1234/v1 (LM Studio). Сервер должен слушать 0.0.0.0.': 'The model runs on your PC or server and the phone connects over the network. Enter your computer’s IP: http://192.168.0.10:11434/v1 (Ollama) or :1234/v1 (LM Studio). The server must listen on 0.0.0.0.',
  'API-ключ (необязательно)': 'API key (optional)',
  'API-ключ': 'API key',
  'Модель': 'Model',
  'Модели': 'Models',
  'Использовать': 'Use',
  'Модель изображений': 'Image model',
  'API-ключ и адрес берутся из «Чат → {}». Для OpenRouter нужна модель с выводом изображений.': 'The API key and URL are taken from “Chat → {}”. OpenRouter needs a model that can output images.',
  'Иконка сменится через несколько секунд': 'The icon will change in a few seconds',
  'Не удалось сменить иконку': 'Could not change the icon',
  'Иконка приложения': 'App icon',
  'Иконка меняется на рабочем столе через несколько секунд. На некоторых лаунчерах ярлык при этом пропадает: тогда добавьте приложение на экран заново.': 'The icon on your home screen changes after a few seconds. On some launchers the shortcut disappears; if so, add the app to the home screen again.',
  'Слишком много попыток. Подождите {} с': 'Too many attempts. Wait {} s',
  'Неверный PIN': 'Wrong PIN',
  'Разблокируйте MintAI': 'Unlock MintAI',
  'Далее': 'Next',
  'Введите PIN': 'Enter PIN',
  'PIN не совпадает, попробуйте снова': 'PINs do not match, try again',
  'PIN-код': 'PIN code',
  'Придумайте PIN (4–8 цифр)': 'Create a PIN (4–8 digits)',
  'Повторите PIN': 'Repeat the PIN',
  'Подтверждение': 'Confirm',
  'Введите текущий PIN': 'Enter current PIN',
  'Сразу': 'Immediately',
  'Через 1 мин': 'After 1 min',
  'Через 5 мин': 'After 5 min',
  'Блокировать': 'Lock',
  'Блокировка PIN-кодом': 'PIN lock',
  'Запрашивать PIN при открытии приложения': 'Ask for the PIN when opening the app',
  'Сменить PIN': 'Change PIN',
  'Вход по биометрии': 'Unlock with biometrics',
  'Отпечаток пальца или лицо': 'Fingerprint or face',
  'Недоступно: биометрия не настроена на устройстве': 'Unavailable: no biometrics set up on this device',
  'Мятная': 'Mint',
  'Графит': 'Graphite',
  'Синяя': 'Blue',
  'Остановить': 'Stop',
  'Голосовой ввод': 'Voice input',
  'Слушаю…': 'Listening…',
  'Отправить': 'Send',
  'Ошибка распознавания: {}': 'Recognition error: {}',
  'Распознавание речи недоступно: проверьте доступ к микрофону и наличие службы распознавания речи': 'Speech recognition is unavailable: check microphone access and that a speech recognition service is installed',
};
