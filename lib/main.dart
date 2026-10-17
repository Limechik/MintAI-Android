import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'app_icon.dart';
import 'i18n.dart';
import 'images.dart';
import 'lock.dart';
import 'secure.dart';
import 'vox.dart';

const mintSeed = Color(0xFF3EB489);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.load();
  runApp(MintAIApp(state: state));
}

// ───────────────────────── Models ─────────────────────────

class Prov {
  final String id, name, defUrl, defModel;
  final bool anthropic; // нативный API Anthropic (/messages)
  final bool keyOptional; // ключ не обязателен (локальные и свои серверы)
  const Prov(this.id, this.name, this.defUrl, this.defModel,
      {this.anthropic = false, this.keyOptional = false});
}

const provs = [
  Prov('deepseek', 'DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat'),
  Prov('openai', 'OpenAI', 'https://api.openai.com/v1', 'gpt-4o-mini'),
  Prov('claude', 'Claude', 'https://api.anthropic.com/v1', 'claude-sonnet-5-5',
      anthropic: true),
  Prov('openrouter', 'OpenRouter', 'https://openrouter.ai/api/v1',
      'openai/gpt-4o-mini'),
  Prov('mistral', 'Mistral', 'https://api.mistral.ai/v1', 'mistral-small-latest'),
  Prov('gemini', 'Gemini',
      'https://generativelanguage.googleapis.com/v1beta/openai', 'gemini-2.5-flash'),
  Prov('zen', 'OpenCode Zen', 'https://opencode.ai/zen/v1',
      'deepseek-v4-flash-free'),
  Prov('custom', 'Custom', 'https://example.com/v1', 'model', keyOptional: true),
  Prov('local', 'Локальная модель', 'http://192.168.0.10:11434/v1', 'llama3.2',
      keyOptional: true),
];

class Msg {
  final String role;
  final String text;
  String? imgId; // зашифрованный файл с фото на диске
  Uint8List? bytes; // фото в памяти (кэш; в инкогнито — единственная копия)
  Msg(this.role, this.text, {this.imgId, this.bytes});

  Map<String, dynamic> toJson() =>
      {'role': role, 'content': text, if (imgId != null) 'img': imgId};
  factory Msg.fromJson(Map<String, dynamic> j) =>
      Msg(j['role'], j['content'], imgId: j['img']);

  Future<Uint8List?> image() async {
    if (bytes != null) return bytes;
    final id = imgId;
    if (id == null) return null;
    return bytes = await ImgStore.load(id);
  }
}

class Chat {
  final String id;
  String title;
  final List<Msg> msgs;
  DateTime updated;
  bool temp; // чат инкогнито: живёт только в памяти
  Chat(this.id, this.title, this.msgs, this.updated, {this.temp = false});

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updated': updated.toIso8601String(),
        'msgs': msgs.map((m) => m.toJson()).toList(),
      };
  factory Chat.fromJson(Map<String, dynamic> j) => Chat(
        j['id'],
        j['title'],
        (j['msgs'] as List).map((m) => Msg.fromJson(m)).toList(),
        DateTime.parse(j['updated']),
      );
}

// ───────────────────────── State ─────────────────────────

class AppState extends ChangeNotifier {
  late SharedPreferences _p;
  List<Chat> chats = [];
  Chat? current;
  bool loading = false;
  int tab = 0;

  String chatProv = 'mistral';
  String imageProv = 'OpenRouter';
  String instruction = '';
  String voice = 'Женский';
  String lang = 'Русский';
  ThemeMode themeMode = ThemeMode.system;

  Prov get prov => provs.firstWhere((p) => p.id == chatProv);
  Prov _r(Prov? p) => p ?? prov;
  String url([Prov? p]) => _p.getString('url_${_r(p).id}') ?? _r(p).defUrl;
  String key([Prov? p]) => _keys[_r(p).id] ?? '';
  String model([Prov? p]) => _p.getString('model_${_r(p).id}') ?? _r(p).defModel;
  void setCfg(Prov p, String f, String v) {
    if (f == 'key') {
      _keys[p.id] = v;
      _persistKeys();
    } else {
      _p.setString('${f}_${p.id}', v);
    }
  }

  final Map<String, String> _keys = {};
  bool incognito = false; // только на время сессии
  bool lockEnabled = false, bioEnabled = false, noShots = false, locked = false;
  int lockAfter = 0; // секунд в фоне до блокировки
  int pinLen = 0;
  String appIcon = 'mint'; // хранится самой системой (activity-alias)
  bool _secureOn = false;
  bool get secure => incognito || noShots;
  bool _dirty = false; // история изменилась и требует записи
  Future<void> _queue = Future.value(); // записи идут строго по очереди

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    await Crypto.init();
    chatProv = _p.getString('chatProv') ?? chatProv;
    imageProv = _p.getString('imageProv') ?? imageProv;
    instruction = _p.getString('instruction') ?? '';
    voice = _p.getString('voice') ?? voice;
    lang = _p.getString('lang') ??
        (WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'ru'
            ? 'Русский'
            : 'English');
    Lang.set(lang);
    themeMode = ThemeMode.values[_p.getInt('theme') ?? 0];
    lockEnabled = _p.getBool('lock') ?? false;
    bioEnabled = _p.getBool('bio') ?? false;
    noShots = _p.getBool('noShots') ?? false;
    lockAfter = _p.getInt('lockAfter') ?? 0;
    pinLen = await PinStore.length() ?? 0;
    if (lockEnabled && pinLen == 0) {
      lockEnabled = false; // PIN потерян (сброс защищённого хранилища)
      bioEnabled = false;
    }
    locked = lockEnabled; // при запуске приложение всегда закрыто
    appIcon = await AppIcon.get();

    // API-ключи
    final ke = _p.getString('keys_enc');
    final keysPlain = ke == null ? null : await Crypto.decrypt(ke);
    if (keysPlain != null) {
      (jsonDecode(keysPlain) as Map).forEach((k, v) => _keys[k] = v as String);
    }
    // миграция: открытые ключи из старых версий
    var legacyKeys = false;
    for (final p in provs) {
      final old = _p.getString('key_${p.id}');
      if (old != null) {
        legacyKeys = true;
        if (old.isNotEmpty) _keys.putIfAbsent(p.id, () => old);
      }
    }
    if (legacyKeys) _persistKeys();

    // история чатов
    final ce = _p.getString('chats_enc');
    String? raw = ce == null ? null : await Crypto.decrypt(ce);
    final legacyChats = _p.getString('chats');
    if (raw == null && legacyChats != null) {
      raw = legacyChats; // миграция: старая открытая история
      _dirty = true;
    }
    if (raw != null) {
      chats = (jsonDecode(raw) as List).map((c) => Chat.fromJson(c)).toList();
    }
    await save();
    notifyListeners(); // применит запрет скриншотов, если он включён
  }

  void _persistKeys() {
    final json = jsonEncode(_keys);
    _queue = _queue.then((_) async {
      await _p.setString('keys_enc', await Crypto.encrypt(json));
      for (final p in provs) {
        await _p.remove('key_${p.id}'); // открытая копия больше не нужна
      }
    }).catchError((_) {});
  }

  void _persistChats() {
    final json = jsonEncode(chats.map((c) => c.toJson()).toList());
    _queue = _queue.then((_) async {
      await _p.setString('chats_enc', await Crypto.encrypt(json));
      await _p.remove('chats'); // открытая копия больше не нужна
    }).catchError((_) {});
  }

  Future<void> save() async {
    await _p.setString('chatProv', chatProv);
    await _p.setString('imageProv', imageProv);
    await _p.setString('instruction', instruction);
    await _p.setString('voice', voice);
    await _p.setString('lang', lang);
    await _p.setInt('theme', themeMode.index);
    await _p.setBool('lock', lockEnabled);
    await _p.setBool('bio', bioEnabled);
    await _p.setBool('noShots', noShots);
    await _p.setInt('lockAfter', lockAfter);
    if (_dirty) {
      _dirty = false;
      _persistChats();
    }
  }

  void change(VoidCallback f) {
    f();
    save();
    notifyListeners();
  }

  void setTab(int i) => change(() => tab = i);
  void newChat() => change(() {
        current = null;
        tab = 0;
      });
  void open(Chat c) => change(() {
        incognito = false; // открыли сохранённый чат — выходим из инкогнито
        current = c;
        tab = 0;
      });
  void _dropImages(Chat c) {
    for (final m in c.msgs) {
      final id = m.imgId;
      if (id != null) ImgStore.delete(id);
    }
  }

  void delete(Chat c) => change(() {
        _dropImages(c);
        chats.remove(c);
        if (current == c) current = null;
        _dirty = true;
      });
  void clearAll() => change(() {
        for (final c in chats) {
          _dropImages(c);
        }
        chats.clear();
        current = null;
        _dirty = true;
      });

  /// Включить/выключить инкогнито: всегда начинаем с нового пустого чата,
  /// временный чат при выходе из режима исчезает.
  void setIncognito(bool v) => change(() {
        incognito = v;
        current = null;
        tab = 0;
      });

  @override
  void notifyListeners() {
    if (_secureOn != secure) {
      _secureOn = secure;
      ScreenGuard.setSecure(secure); // FLAG_SECURE: без скриншотов и превью
    }
    super.notifyListeners();
  }

  Future<void> enableLock(String pin) async {
    await PinStore.set(pin);
    change(() {
      lockEnabled = true;
      pinLen = pin.length;
    });
  }

  Future<void> changePin(String pin) async {
    await PinStore.set(pin);
    change(() => pinLen = pin.length);
  }

  Future<void> disableLock() async {
    await PinStore.clear();
    change(() {
      lockEnabled = false;
      bioEnabled = false;
      locked = false;
      pinLen = 0;
    });
  }

  void lockNow() {
    locked = true;
    notifyListeners();
  }

  void unlock() {
    locked = false;
    notifyListeners();
  }

  Chat _ensureChat(String title) {
    var chat = current;
    if (chat == null) {
      chat = Chat(
        DateTime.now().microsecondsSinceEpoch.toString(),
        title.length > 40 ? '${title.substring(0, 40)}…' : title,
        [],
        DateTime.now(),
        temp: incognito,
      );
      if (!incognito) chats.insert(0, chat); // инкогнито-чат в историю не попадает
      current = chat;
    }
    return chat;
  }

  Future<void> send(String text, {Uint8List? photo}) async {
    final chat = _ensureChat(text.isEmpty ? '📷 Фото' : text);
    final um = Msg('user', text, bytes: photo);
    // в инкогнито фото на диск не пишется
    final idF = (photo != null && !chat.temp) ? ImgStore.save(photo) : null;
    chat.msgs.add(um);
    chat.updated = DateTime.now();
    loading = true;
    notifyListeners();

    String reply;
    try {
      reply = await _ask(chat);
    } catch (e) {
      reply = tr('Ошибка: $e');
    }
    if (idF != null) um.imgId = await idF;
    chat.msgs.add(Msg('assistant', reply));
    chat.updated = DateTime.now();
    loading = false;
    if (!chat.temp) _dirty = true;
    await save();
    notifyListeners();
  }

  Future<void> generateImage(String prompt) async {
    final chat = _ensureChat('🎨 $prompt');
    chat.msgs.add(Msg('user', '🎨 $prompt'));
    chat.updated = DateTime.now();
    loading = true;
    notifyListeners();

    Msg reply;
    try {
      reply = Msg('assistant', '', bytes: await _imageGen(prompt));
    } catch (e) {
      reply = Msg('assistant', tr('Ошибка генерации: $e'));
    }
    chat.msgs.add(reply);
    chat.updated = DateTime.now();
    loading = false;
    notifyListeners();
    final b = reply.bytes;
    if (b != null && !chat.temp) reply.imgId = await ImgStore.save(b);
    if (!chat.temp) _dirty = true;
    await save();
    notifyListeners();
  }

  String imageModel() {
    final v = _p.getString('imgModel_$imageProv');
    if (v != null && v.isNotEmpty) return v;
    return imageProv == 'OpenAI' ? 'gpt-image-1' : 'google/gemini-2.5-flash-image';
  }

  void setImageModel(String v) => _p.setString('imgModel_$imageProv', v);

  dynamic _decode(http.Response res) {
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw tr('HTTP ${res.statusCode}: ответ не похож на API, проверьте Base URL');
    }
    if (res.statusCode != 200) {
      final e = body is Map ? body['error'] : null;
      throw (e is Map ? e['message'] : e) ??
          (body is Map ? body['message'] : null) ??
          'HTTP ${res.statusCode}';
    }
    return body;
  }

  /// Ключ и адрес берутся из настроек одноимённого провайдера чата.
  Future<Uint8List> _imageGen(String prompt) async {
    if (imageProv == 'Выкл.') {
      throw tr('генерация выключена: Настройки → Изображения');
    }
    final openai = imageProv == 'OpenAI';
    final p = provs.firstWhere((x) => x.id == (openai ? 'openai' : 'openrouter'));
    final k = key(p).trim();
    if (k.isEmpty) throw tr('добавьте API-ключ для «${p.name}» в Настройки → Чат');
    final base = url(p).replaceAll(RegExp(r'/+$'), '');
    final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer $k'};
    const wait = Duration(minutes: 3);

    if (openai) {
      final res = await http
          .post(Uri.parse('$base/images/generations'),
              headers: headers,
              body: jsonEncode({
                'model': imageModel(),
                'prompt': prompt,
                'size': '1024x1024',
                'n': 1,
              }))
          .timeout(wait);
      final d = (_decode(res)['data'] as List).first;
      if (d['b64_json'] != null) return base64Decode(d['b64_json']);
      final img = await http.get(Uri.parse(d['url'])).timeout(wait);
      return img.bodyBytes;
    }

    // OpenRouter: картинки приходят через chat/completions с modalities
    final res = await http
        .post(Uri.parse('$base/chat/completions'),
            headers: headers,
            body: jsonEncode({
              'model': imageModel(),
              'messages': [
                {'role': 'user', 'content': prompt}
              ],
              'modalities': ['image', 'text'],
            }))
        .timeout(wait);
    final msg = _decode(res)['choices'][0]['message'];
    final imgs = msg['images'] as List?;
    if (imgs == null || imgs.isEmpty) {
      final t = (msg['content'] as String?)?.trim() ?? '';
      throw t.isNotEmpty ? t : tr('модель не вернула изображение (проверьте модель)');
    }
    final u = imgs.first['image_url']['url'] as String;
    return base64Decode(u.substring(u.indexOf(',') + 1));
  }

  /// Сообщения для API: фото уходят в формате выбранного протокола.
  Future<List<Map<String, dynamic>>> _apiMsgs(Chat chat, bool anthropic) async {
    final out = <Map<String, dynamic>>[];
    for (final m in chat.msgs) {
      final bytes = m.role == 'user' ? await m.image() : null;
      if (bytes == null) {
        out.add({'role': m.role, 'content': m.text.isEmpty ? '[image]' : m.text});
        continue;
      }
      final b64 = base64Encode(bytes), mime = mimeOf(bytes);
      out.add({
        'role': m.role,
        'content': anthropic
            ? [
                {
                  'type': 'image',
                  'source': {'type': 'base64', 'media_type': mime, 'data': b64}
                },
                if (m.text.isNotEmpty) {'type': 'text', 'text': m.text},
              ]
            : [
                if (m.text.isNotEmpty) {'type': 'text', 'text': m.text},
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:$mime;base64,$b64'}
                },
              ],
      });
    }
    return out;
  }

  Future<String> _ask(Chat chat) async {
    final p = prov;
    final k = key().trim();
    if (k.isEmpty && !p.keyOptional) {
      return tr('Добавьте API-ключ для «${p.name}» в Настройки → Чат.');
    }
    final base = url().replaceAll(RegExp(r'/+$'), '');
    final msgs = await _apiMsgs(chat, p.anthropic);
    const wait = Duration(minutes: 5); // локальные модели бывают медленными
    final http.Response res;
    if (p.anthropic) {
      res = await http
          .post(
            Uri.parse('$base/messages'),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': k,
              'anthropic-version': '2023-06-01',
            },
            body: jsonEncode({
              'model': model(),
              'max_tokens': 4096,
              if (instruction.isNotEmpty) 'system': instruction,
              'messages': msgs,
            }),
          )
          .timeout(wait);
    } else {
      res = await http
          .post(
            Uri.parse('$base/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              if (k.isNotEmpty) 'Authorization': 'Bearer $k',
            },
            body: jsonEncode({
              'model': model(),
              'messages': [
                if (instruction.isNotEmpty)
                  {'role': 'system', 'content': instruction},
                ...msgs,
              ],
            }),
          )
          .timeout(wait);
    }
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw tr('HTTP ${res.statusCode}: ответ не похож на API, проверьте Base URL');
    }
    if (res.statusCode != 200) {
      final e = body is Map ? body['error'] : null;
      throw (e is Map ? e['message'] : e) ??
          (body is Map ? body['message'] : null) ??
          'HTTP ${res.statusCode}';
    }
    final text = p.anthropic
        ? (body['content'] as List)
            .where((b) => b['type'] == 'text')
            .map((b) => b['text'])
            .join()
        : body['choices'][0]['message']['content'];
    return (text as String).trim();
  }

  /// Список моделей сервера (GET /models) для выбора в настройках.
  Future<List<String>> listModels(Prov p, String url, String key) async {
    final res = await http.get(
      Uri.parse('${url.replaceAll(RegExp(r'/+$'), '')}/models'),
      headers: p.anthropic
          ? {'x-api-key': key, 'anthropic-version': '2023-06-01'}
          : {if (key.isNotEmpty) 'Authorization': 'Bearer $key'},
    ).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
    final data = jsonDecode(utf8.decode(res.bodyBytes))['data'] as List;
    return data
        .map((m) => (m['id'] ?? m['name']).toString().replaceFirst('models/', ''))
        .toList()
      ..sort();
  }
}

// ───────────────────────── App ─────────────────────────

class MintAIApp extends StatelessWidget {
  final AppState state;
  const MintAIApp({super.key, required this.state});

  ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: mintSeed, brightness: b),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (_, __) => MaterialApp(
        title: 'MintAI',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: state.themeMode,
        locale: Locale(Lang.en ? 'en' : 'ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => LangScope(
          en: Lang.en,
          child: LockGate(state: state, child: child ?? const SizedBox()),
        ),
        home: HomeShell(state: state),
      ),
    );
  }
}

class HomeShell extends StatelessWidget {
  final AppState state;
  const HomeShell({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: state.tab,
        children: [
          ChatPage(state: state),
          HistoryPage(state: state),
          SettingsPage(state: state),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: state.tab,
        onDestinationSelected: state.setTab,
        destinations: [
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: tr('Чат')),
          NavigationDestination(
              icon: Icon(Icons.history), label: tr('История чатов')),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: tr('Настройки')),
        ],
      ),
    );
  }
}

// ───────────────────────── Chat ─────────────────────────

class ChatPage extends StatefulWidget {
  final AppState state;
  const ChatPage({super.key, required this.state});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final _ctrl = TextEditingController();

  // ── голосовой ввод (системная служба распознавания речи Android) ──
  final _stt = SpeechToText();
  Future<bool>? _sttInit;
  bool _listening = false;
  String _base = ''; // текст, который уже был в поле до диктовки

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stt.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    // при сворачивании приложения микрофон не держим
    if (st != AppLifecycleState.resumed && _listening) {
      _stt.stop();
      setState(() => _listening = false);
    }
  }

  Future<bool> _initStt() => _sttInit ??= _stt.initialize(
        onStatus: (st) {
          if ((st == 'done' || st == 'notListening') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (e) {
          if (!mounted) return;
          setState(() => _listening = false);
          if (e.errorMsg != 'error_no_match' &&
              e.errorMsg != 'error_speech_timeout') {
            _snack(tr('Ошибка распознавания: ${e.errorMsg}'));
          }
        },
      );

  Future<void> _toggleListen() async {
    if (_listening) {
      await _stt.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (widget.state.loading) return;
    final ok = await _initStt(); // при первом запуске спросит доступ к микрофону
    if (!ok) {
      _sttInit = null; // попробуем снова, если разрешение дадут позже
      if (mounted) {
        _snack(tr(
            'Распознавание речи недоступно: проверьте доступ к микрофону и наличие службы распознавания речи'));
      }
      return;
    }
    String? id; // язык распознавания = язык интерфейса
    final want = Lang.en ? 'en' : 'ru';
    for (final l in await _stt.locales()) {
      if (l.localeId.toLowerCase().startsWith(want)) {
        id = l.localeId;
        break;
      }
    }
    if (!mounted) return;
    _base = _ctrl.text.trim().isEmpty ? '' : '${_ctrl.text.trimRight()} ';
    setState(() => _listening = true);
    await _stt.listen(
      onResult: (r) {
        if (!mounted) return;
        final t = _base + r.recognizedWords;
        _ctrl.value = TextEditingValue(
            text: t, selection: TextSelection.collapsed(offset: t.length));
      },
      localeId: id,
      listenFor: const Duration(minutes: 2),
      pauseFor: const Duration(seconds: 4),
      listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true),
    );
  }

  Uint8List? _photo; // выбранное, но ещё не отправленное фото

  void _send() {
    final t = _ctrl.text.trim();
    if ((t.isEmpty && _photo == null) || widget.state.loading) return;
    final p = _photo;
    _ctrl.clear();
    if (_listening) _stt.cancel();
    setState(() {
      _photo = null;
      _listening = false;
    });
    widget.state.send(t, photo: p);
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  void _attachMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.add_photo_alternate_outlined),
            title: const Text('Добавить фото'),
            onTap: () {
              Navigator.pop(context);
              _pickPhoto();
            },
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Сгенерировать изображение'),
            onTap: () {
              Navigator.pop(context);
              _generate();
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    try {
      final f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
      );
      if (f == null) return;
      final bytes = await f.readAsBytes();
      try {
        await File(f.path).delete(); // убираем открытую копию из кэша
      } catch (_) {}
      if (mounted) setState(() => _photo = bytes);
    } catch (e) {
      if (mounted) _snack('Не удалось выбрать фото: $e');
    }
  }

  Future<void> _generate() async {
    final s = widget.state;
    if (s.imageProv == 'Выкл.') {
      _snack('Генерация выключена: Настройки → Изображения');
      return;
    }
    final c = TextEditingController(text: _ctrl.text.trim());
    final prompt = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Сгенерировать изображение'),
        content: TextField(
          controller: c,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
              hintText: tr('Опишите, что нарисовать'), border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: const Text('Создать')),
        ],
      ),
    );
    if (prompt == null || prompt.isEmpty || s.loading) return;
    _ctrl.clear();
    s.generateImage(prompt);
  }

  Widget _preview() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_photo!,
                  width: 72, height: 72, fit: BoxFit.cover, cacheWidth: 200),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: () => setState(() => _photo = null),
                icon: const Icon(Icons.close),
              ),
            ),
          ]),
        ),
      );

  void _pickProv() {
    final s = widget.state;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final p in provs)
            ListTile(
              title: Text(p.name),
              trailing: p.id == s.chatProv ? const Icon(Icons.check) : null,
              onTap: () {
                s.change(() => s.chatProv = p.id);
                Navigator.pop(context);
              },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final cs = Theme.of(context).colorScheme;
    final msgs = s.current?.msgs ?? [];
    final items = msgs.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: s.incognito ? cs.tertiaryContainer : null,
        leading: IconButton(
            tooltip: tr('Новый чат'),
            icon: const Icon(Icons.add),
            onPressed: s.newChat),
        title: Text(s.incognito
            ? 'Инкогнито — ${s.prov.name}'
            : 'MintAI — ${s.prov.name}'),
        actions: [
          IconButton(
            tooltip: tr(s.incognito ? 'Выключить инкогнито' : 'Режим инкогнито'),
            isSelected: s.incognito,
            icon: const Icon(Icons.visibility_off_outlined),
            selectedIcon: const Icon(Icons.visibility_off),
            onPressed: () {
              s.setIncognito(!s.incognito);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(s.incognito
                      ? 'Инкогнито включён: чат не сохраняется'
                      : 'Инкогнито выключен')));
            },
          ),
          FilledButton.tonal(onPressed: _pickProv, child: const Text('Провайдер')),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: msgs.isEmpty && !s.loading
                ? Center(
                    child: Text(
                      s.incognito
                          ? 'Режим инкогнито\nЭтот чат не будет сохранён.'
                          : 'Привет! Я "${s.prov.name}"\nНапиши сообщение.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length + (s.loading ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (s.loading && i == 0) {
                        return const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        );
                      }
                      return _Bubble(msg: items[s.loading ? i - 1 : i], state: s);
                    },
                  ),
          ),
          if (_photo != null) _preview(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  IconButton.filledTonal(
                      onPressed: _attachMenu, icon: const Icon(Icons.add)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _ctrl,
                      builder: (_, v, __) {
                        final micRight = v.text.trim().isEmpty && _photo == null;
                        return TextField(
                          controller: _ctrl,
                          minLines: 1,
                          maxLines: 5,
                          decoration: InputDecoration(
                            hintText: tr(_listening ? 'Слушаю…' : 'Сообщение…'),
                            filled: true,
                            fillColor: cs.surfaceContainerHighest,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide.none,
                            ),
                            // когда справа «отправить», диктовать можно кнопкой в поле
                            suffixIcon: (!micRight && !_listening)
                                ? IconButton(
                                    tooltip: tr('Голосовой ввод'),
                                    onPressed: _toggleListen,
                                    icon: const Icon(Icons.mic_none))
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _ctrl,
                    builder: (_, v, __) {
                      if (_listening) {
                        return IconButton.filled(
                          style: IconButton.styleFrom(
                              backgroundColor: cs.error,
                              foregroundColor: cs.onError),
                          tooltip: tr('Остановить'),
                          onPressed: _toggleListen,
                          icon: const Icon(Icons.stop),
                        );
                      }
                      final empty = v.text.trim().isEmpty && _photo == null;
                      return IconButton.filled(
                        tooltip: tr(empty ? 'Голосовой ввод' : 'Отправить'),
                        onPressed:
                            empty ? _toggleListen : (s.loading ? null : _send),
                        icon: Icon(empty ? Icons.mic : Icons.arrow_upward),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Msg msg;
  final AppState state;
  const _Bubble({required this.msg, required this.state});

  void _speak(BuildContext context) {
    Vox.speak(msg, msg.text, female: state.voice == 'Женский').catchError((e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Озвучка: $e')));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = msg.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: user ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(user ? 20 : 4),
            bottomRight: Radius.circular(user ? 4 : 20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.imgId != null || msg.bytes != null)
              Padding(
                padding: EdgeInsets.only(bottom: msg.text.isEmpty ? 0 : 8),
                child: _MsgImage(msg: msg),
              ),
            if (msg.text.isNotEmpty)
              SelectableText(
                msg.text,
                style: TextStyle(
                    color: user ? cs.onPrimaryContainer : cs.onSurface,
                    height: 1.35),
              ),
            if (!user &&
                msg.text.isNotEmpty &&
                looksRussian(msg.text) &&
                Vox.supported &&
                state.voice != 'Выкл.')
              ValueListenableBuilder<Object?>(
                valueListenable: Vox.current,
                builder: (_, cur, __) => IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Озвучить'),
                  icon: Icon(
                      cur == msg
                          ? Icons.stop_circle_outlined
                          : Icons.volume_up_outlined,
                      size: 20),
                  onPressed: () => cur == msg ? Vox.stop() : _speak(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MsgImage extends StatelessWidget {
  final Msg msg;
  const _MsgImage({required this.msg});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      initialData: msg.bytes,
      future: msg.bytes != null ? null : msg.image(),
      builder: (_, snap) {
        final b = snap.data;
        if (b == null) {
          return SizedBox(
            width: 160,
            height: 160,
            child: Center(
              child: snap.connectionState == ConnectionState.done
                  ? const Icon(Icons.broken_image_outlined)
                  : const CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return GestureDetector(
          onTap: () => showDialog(
            context: context,
            builder: (_) => Dialog.fullscreen(
              child: Stack(children: [
                InteractiveViewer(child: Center(child: Image.memory(b))),
                Positioned(
                  top: 8,
                  right: 8,
                  child: SafeArea(
                    child: IconButton.filledTonal(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(b,
                  fit: BoxFit.contain, gaplessPlayback: true, cacheWidth: 800),
            ),
          ),
        );
      },
    );
  }
}

// ───────────────────────── History ─────────────────────────

class HistoryPage extends StatefulWidget {
  final AppState state;
  const HistoryPage({super.key, required this.state});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String q = '';

  String _two(int n) => n.toString().padLeft(2, '0');
  String _fmt(DateTime d) {
    final n = DateTime.now();
    final t = '${d.hour}:${_two(d.minute)}';
    if (d.year == n.year && d.month == n.month && d.day == n.day) {
      return '${tr('Сегодня')}, $t';
    }
    return '${_two(d.day)}.${_two(d.month)}.${_two(d.year % 100)}, $t';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final cs = Theme.of(context).colorScheme;
    final list = s.chats
        .where((c) =>
            q.isEmpty ||
            c.title.toLowerCase().contains(q) ||
            c.msgs.any((m) => m.text.toLowerCase().contains(q)))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('История чатов'),
        actions: [
          if (s.chats.isNotEmpty)
            IconButton(
              tooltip: tr('Очистить всё'),
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Удалить всю историю?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Отмена')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Удалить')),
                    ],
                  ),
                );
                if (ok == true) s.clearAll();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SearchBar(
              hintText: tr('Поиск по истории'),
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: (v) => setState(() => q = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('Ничего нет'))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = list[i];
                      final last = c.msgs.isEmpty
                          ? ''
                          : c.msgs.last.text.replaceAll('\n', ' ');
                      return Dismissible(
                        key: ValueKey(c.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: cs.errorContainer,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: Icon(Icons.delete, color: cs.onErrorContainer),
                        ),
                        onDismissed: (_) => s.delete(c),
                        child: ListTile(
                          title: Text(c.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${_fmt(c.updated)} — $last',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => s.open(c),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Settings ─────────────────────────

const themeNames = {
  ThemeMode.system: 'Системная',
  ThemeMode.light: 'Светлая',
  ThemeMode.dark: 'Тёмная',
};

class SettingsPage extends StatelessWidget {
  final AppState state;
  const SettingsPage({super.key, required this.state});

  Widget _group(BuildContext c, String title, List<Widget> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(title,
                style: Theme.of(c)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: Theme.of(c).colorScheme.primary)),
          ),
          Card.filled(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            clipBehavior: Clip.antiAlias,
            child: Column(children: rows),
          ),
        ],
      );

  Widget _row(BuildContext c, IconData icon, Color color, String title,
      String value, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
      title: Text(title),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant)),
        ),
        const Icon(Icons.chevron_right),
      ]),
      onTap: onTap,
    );
  }

  Future<String?> _pick(
      BuildContext c, String title, List<String> opts, String cur) {
    return showDialog<String>(
      context: c,
      builder: (_) => SimpleDialog(
        title: Text(title),
        children: [
          for (final o in opts)
            ListTile(
              title: Text(o),
              trailing: o == cur ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(c, o),
            ),
        ],
      ),
    );
  }

  Future<void> _editInstruction(BuildContext c) async {
    final ctrl = TextEditingController(text: state.instruction);
    final r = await showDialog<String>(
      context: c,
      builder: (_) => AlertDialog(
        title: const Text('Инструкция'),
        content: TextField(
          controller: ctrl,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
              hintText: tr('Например: отвечай кратко'), border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (r != null) state.change(() => state.instruction = r);
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _group(context, 'ИИ', [
            _row(context, Icons.chat_bubble, const Color(0xFF3EB489), 'Чат',
                s.prov.name, () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ProviderPage(state: s)));
            }),
            _row(context, Icons.palette, const Color(0xFF8E5BD0), 'Изображения',
                s.imageProv, () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ImageSettingsPage(state: s)));
            }),
            _row(context, Icons.edit_note, const Color(0xFFF29A2E), 'Инструкция',
                s.instruction.isEmpty ? 'Не задана' : s.instruction,
                () => _editInstruction(context)),
          ]),
          _group(context, 'Приложение', [
            _row(context, Icons.volume_up, const Color(0xFF2F8FE8), 'Голос',
                s.voice, () async {
              final r = await _pick(
                  context, 'Голос', ['Женский', 'Мужской', 'Выкл.'], s.voice);
              if (r != null) s.change(() => s.voice = r);
            }),
            _row(context, Icons.image, const Color(0xFFE5557A), 'Оформление',
                themeNames[s.themeMode]!, () async {
              final r = await _pick(context, 'Оформление',
                  themeNames.values.toList(), themeNames[s.themeMode]!);
              if (r != null) {
                s.change(() => s.themeMode = themeNames.entries
                    .firstWhere((e) => e.value == r)
                    .key);
              }
            }),
            _row(context, Icons.apps, const Color(0xFF3EB489), 'Иконка',
                AppIcon.nameOf(s.appIcon), () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => IconSettingsPage(state: s)));
            }),
            _row(context, Icons.language, const Color(0xFF6B7A8F),
                'Язык / Language', s.lang, () async {
              final r = await _pick(
                  context, 'Язык / Language', ['Русский', 'English'], s.lang);
              if (r != null) {
                s.change(() {
                  s.lang = r;
                  Lang.set(r);
                });
              }
            }),
          ]),
          _group(context, 'Приватность', [
            SwitchListTile(
              secondary: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: const Color(0xFF455A64),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.visibility_off,
                    color: Colors.white, size: 22),
              ),
              title: const Text('Режим инкогнито'),
              subtitle: const Text('Чаты не сохраняются, скриншоты запрещены'),
              value: s.incognito,
              onChanged: s.setIncognito,
            ),
            _row(context, Icons.password, const Color(0xFFE5557A), 'Блокировка',
                !s.lockEnabled ? 'Выкл.' : (s.bioEnabled ? 'PIN + биометрия' : 'PIN'),
                () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => LockSettingsPage(state: s)));
            }),
            SwitchListTile(
              secondary: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: const Color(0xFF8E5BD0),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.block, color: Colors.white, size: 22),
              ),
              title: const Text('Запретить скриншоты'),
              subtitle: const Text(
                  'Скрывает приложение в списке недавних. В инкогнито включено всегда'),
              value: s.noShots || s.incognito,
              onChanged: s.incognito ? null : (v) => s.change(() => s.noShots = v),
            ),
            _row(context, Icons.lock, const Color(0xFF3EB489), 'Шифрование',
                'AES-256', () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Шифрование'),
                  content: const Text(
                      'История чатов и API-ключи хранятся в зашифрованном виде '
                      '(AES-256-GCM). Ключ шифрования создаётся на устройстве и '
                      'лежит в защищённом хранилище Android (Keystore). '
                      'Чаты в режиме инкогнито никуда не записываются.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK')),
                  ],
                ),
              );
            }),
          ]),
          _group(context, 'Автор', [
            _row(context, Icons.send, const Color(0xFF29A9EB), 'Telegram',
                '@LimeDeveloper', () {
              Clipboard.setData(const ClipboardData(text: '@LimeDeveloper'));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Скопировано')));
            }),
          ]),
        ],
      ),
    );
  }
}

class ProviderPage extends StatefulWidget {
  final AppState state;
  const ProviderPage({super.key, required this.state});
  @override
  State<ProviderPage> createState() => _ProviderPageState();
}

class _ProviderPageState extends State<ProviderPage> {
  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Scaffold(
      appBar: AppBar(title: const Text('Чат')),
      body: ListView(
        children: [
          for (final p in provs)
            ListTile(
              leading: Icon(p.id == s.chatProv
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off),
              title: Text(p.name),
              subtitle: Text(s.model(p), maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ProviderEditPage(state: s, p: p)),
                );
                setState(() {});
              },
            ),
        ],
      ),
    );
  }
}

class ProviderEditPage extends StatelessWidget {
  final AppState state;
  final Prov p;
  const ProviderEditPage({super.key, required this.state, required this.p});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ProvEditor(state: state, p: p, onUse: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}

class _ProvEditor extends StatefulWidget {
  final AppState state;
  final Prov p;
  final VoidCallback onUse;
  const _ProvEditor({required this.state, required this.p, required this.onUse});
  @override
  State<_ProvEditor> createState() => _ProvEditorState();
}

class _ProvEditorState extends State<_ProvEditor> {
  late final _url = TextEditingController(text: widget.state.url(widget.p));
  late final _key = TextEditingController(text: widget.state.key(widget.p));
  late final _model = TextEditingController(text: widget.state.model(widget.p));

  void _snack(String t) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(t)));

  Future<void> _models() async {
    final p = widget.p;
    try {
      final ids = await widget.state
          .listModels(p, _url.text.trim(), _key.text.trim());
      if (!mounted) return;
      if (ids.isEmpty) return _snack('Сервер вернул пустой список');
      final r = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Модели (${ids.length})'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(shrinkWrap: true, children: [
              for (final id in ids)
                ListTile(title: Text(id), onTap: () => Navigator.pop(context, id)),
            ]),
          ),
        ),
      );
      if (r != null) {
        _model.text = r;
        widget.state.setCfg(p, 'model', r);
      }
    } catch (e) {
      if (mounted) _snack('Не удалось подключиться: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state, p = widget.p;
    return Column(
      children: [
        if (p.id == 'local')
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Модель работает на вашем ПК или сервере, телефон подключается по '
              'сети. Укажите IP компьютера: http://192.168.0.10:11434/v1 '
              '(Ollama) или :1234/v1 (LM Studio). Сервер должен слушать 0.0.0.0.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
              labelText: 'Base URL', border: OutlineInputBorder()),
          onChanged: (v) => s.setCfg(p, 'url', v.trim()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _key,
          obscureText: true,
          decoration: InputDecoration(
              labelText: tr(p.keyOptional ? 'API-ключ (необязательно)' : 'API-ключ'),
              border: const OutlineInputBorder()),
          onChanged: (v) => s.setCfg(p, 'key', v.trim()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _model,
          decoration: InputDecoration(
              labelText: tr('Модель'), border: const OutlineInputBorder()),
          onChanged: (v) => s.setCfg(p, 'model', v.trim()),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(onPressed: _models, child: const Text('Модели')),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () {
                s.change(() => s.chatProv = p.id);
                widget.onUse();
              },
              child: const Text('Использовать'),
            ),
          ],
        ),
      ],
    );
  }
}

class ImageSettingsPage extends StatefulWidget {
  final AppState state;
  const ImageSettingsPage({super.key, required this.state});
  @override
  State<ImageSettingsPage> createState() => _ImageSettingsPageState();
}

class _ImageSettingsPageState extends State<ImageSettingsPage> {
  late final _model = TextEditingController(text: widget.state.imageModel());

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Scaffold(
      appBar: AppBar(title: const Text('Изображения')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final n in const ['OpenRouter', 'OpenAI', 'Выкл.'])
            ListTile(
              leading: Icon(n == s.imageProv
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off),
              title: Text(n),
              onTap: () {
                s.change(() => s.imageProv = n);
                _model.text = s.imageModel();
                setState(() {});
              },
            ),
          if (s.imageProv != 'Выкл.') ...[
            const SizedBox(height: 16),
            TextField(
              controller: _model,
              decoration: InputDecoration(
                  labelText: tr('Модель изображений'), border: const OutlineInputBorder()),
              onChanged: (v) => s.setImageModel(v.trim()),
            ),
            const SizedBox(height: 12),
            Text(
              'API-ключ и адрес берутся из «Чат → ${s.imageProv}». '
              'Для OpenRouter нужна модель с выводом изображений.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class IconSettingsPage extends StatefulWidget {
  final AppState state;
  const IconSettingsPage({super.key, required this.state});
  @override
  State<IconSettingsPage> createState() => _IconSettingsPageState();
}

class _IconSettingsPageState extends State<IconSettingsPage> {
  Future<void> _pick(String id) async {
    final s = widget.state;
    if (id == s.appIcon) return;
    final ok = await AppIcon.set(id);
    if (!mounted) return;
    if (ok) s.change(() => s.appIcon = id);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Иконка сменится через несколько секунд'
            : 'Не удалось сменить иконку')));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Иконка приложения')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in AppIcon.options)
                InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => _pick(o.id),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: o.id == s.appIcon
                                  ? cs.primary
                                  : Colors.transparent,
                              width: 3),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset(o.asset, width: 80, height: 80),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(o.name,
                          style: TextStyle(
                              fontWeight: o.id == s.appIcon
                                  ? FontWeight.bold
                                  : FontWeight.normal)),
                    ]),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Иконка меняется на рабочем столе через несколько секунд. На некоторых '
            'лаунчерах ярлык при этом пропадает: тогда добавьте приложение на экран заново.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
