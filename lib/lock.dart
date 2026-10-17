import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'i18n.dart';
import 'main.dart';

// ───────────────────────── Запрет скриншотов ─────────────────────────

/// FLAG_SECURE через MainActivity (см. android_patch/MainActivity.kt).
class ScreenGuard {
  static const _c = MethodChannel('mintai/secure');
  static Future<void> setSecure(bool on) async {
    try {
      await _c.invokeMethod('setSecure', on);
    } catch (_) {} // на других платформах канала нет
  }
}

// ───────────────────────── PIN ─────────────────────────

class PinCheck {
  final bool ok;
  final int wait; // секунд до следующей попытки
  const PinCheck(this.ok, this.wait);
}

String pinError(PinCheck r) =>
    r.wait > 0 ? 'Слишком много попыток. Подождите ${r.wait} с' : 'Неверный PIN';

/// PIN хранится как PBKDF2-хэш с солью в защищённом хранилище (Keystore).
/// После 5 неверных попыток включается растущая задержка (30 с … 1 час).
class PinStore {
  static const _s = FlutterSecureStorage();
  static final _kdf =
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 20000, bits: 256);

  static Future<List<int>> _hash(String pin, List<int> salt) async =>
      (await _kdf.deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: salt))
          .extractBytes();

  static Future<int?> length() async =>
      int.tryParse(await _s.read(key: 'pin_len') ?? '');

  static Future<void> set(String pin) async {
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    await _s.write(key: 'pin_salt', value: base64Encode(salt));
    await _s.write(key: 'pin_hash', value: base64Encode(await _hash(pin, salt)));
    await _s.write(key: 'pin_len', value: '${pin.length}');
    await _s.write(key: 'pin_fails', value: '0');
    await _s.write(key: 'pin_until', value: '0');
  }

  static Future<void> clear() async {
    for (final k in ['pin_salt', 'pin_hash', 'pin_len', 'pin_fails', 'pin_until']) {
      await _s.delete(key: k);
    }
  }

  static Future<PinCheck> verify(String pin) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final until = int.tryParse(await _s.read(key: 'pin_until') ?? '') ?? 0;
    if (until > now) return PinCheck(false, ((until - now) / 1000).ceil());

    final salt = base64Decode(await _s.read(key: 'pin_salt') ?? '');
    final saved = base64Decode(await _s.read(key: 'pin_hash') ?? '');
    final h = await _hash(pin, salt);
    var diff = h.length ^ saved.length; // сравнение без раннего выхода
    for (var i = 0; i < h.length && i < saved.length; i++) {
      diff |= h[i] ^ saved[i];
    }
    if (diff == 0) {
      await _s.write(key: 'pin_fails', value: '0');
      await _s.write(key: 'pin_until', value: '0');
      return const PinCheck(true, 0);
    }
    final fails = (int.tryParse(await _s.read(key: 'pin_fails') ?? '') ?? 0) + 1;
    final wait = fails >= 5 ? min(30 * (1 << min(fails - 5, 7)), 3600) : 0;
    await _s.write(key: 'pin_fails', value: '$fails');
    await _s.write(key: 'pin_until', value: '${now + wait * 1000}');
    return PinCheck(false, wait);
  }
}

// ───────────────────────── Биометрия ─────────────────────────

class Bio {
  static final _a = LocalAuthentication();

  /// Пока true, смена состояния приложения (окно биометрии) не блокирует экран.
  static bool busy = false;

  static Future<bool> available() async {
    try {
      return await _a.canCheckBiometrics &&
          (await _a.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> auth() async {
    busy = true;
    try {
      return await _a.authenticate(
        localizedReason: tr('Разблокируйте MintAI'),
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } catch (_) {
      return false;
    } finally {
      Future.delayed(const Duration(milliseconds: 800), () => busy = false);
    }
  }
}

// ───────────────────────── Экран PIN ─────────────────────────

/// length != null — фиксированная длина, ввод отправляется сам.
/// length == null — свободная длина (4–8), отправка кнопкой «Далее».
class PinPad extends StatefulWidget {
  final int? length;
  final String title;
  final String? error;
  final ValueChanged<String> onSubmit;
  final VoidCallback? onBio;
  const PinPad({
    super.key,
    this.length,
    required this.title,
    this.error,
    required this.onSubmit,
    this.onBio,
  });
  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';

  void _add(String d) {
    final limit = widget.length ?? 8;
    if (_pin.length >= limit) return;
    setState(() => _pin += d);
    if (widget.length != null && _pin.length == widget.length) _submit();
  }

  void _del() {
    if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _submit() {
    final p = _pin;
    setState(() => _pin = '');
    widget.onSubmit(p);
  }

  Widget _btn(Widget child, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.all(6),
        child: SizedBox(
          width: 72,
          height: 72,
          child: onTap == null
              ? null
              : TextButton(
                  style: TextButton.styleFrom(
                      shape: const CircleBorder(), padding: EdgeInsets.zero),
                  onPressed: onTap,
                  child: child,
                ),
        ),
      );

  Widget _digit(String d) => _btn(
      Text(d, style: Theme.of(context).textTheme.headlineMedium), () => _add(d));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = widget.length ?? (_pin.length < 4 ? 4 : _pin.length);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 20),
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < n; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _pin.length ? cs.primary : Colors.transparent,
                border: Border.all(color: cs.primary, width: 1.5),
              ),
            ),
        ]),
        SizedBox(
          width: 260,
          height: 44,
          child: Center(
            child: Text(widget.error ?? '',
                textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
          ),
        ),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) _digit(d)]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _btn(const Icon(Icons.fingerprint, size: 32), widget.onBio),
          _digit('0'),
          _btn(const Icon(Icons.backspace_outlined), _del),
        ]),
        if (widget.length == null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: FilledButton(
                onPressed: _pin.length >= 4 ? _submit : null,
                child: const Text('Далее')),
          ),
      ],
    );
  }
}

// ───────────────────────── Блокировка ─────────────────────────

/// Накрывает приложение экраном PIN и прячет содержимое при сворачивании.
class LockGate extends StatefulWidget {
  final AppState state;
  final Widget child;
  const LockGate({super.key, required this.state, required this.child});
  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  DateTime? _left;
  bool _cover = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    final s = widget.state;
    if (!s.lockEnabled || Bio.busy) return;
    if (st == AppLifecycleState.inactive) {
      setState(() => _cover = true);
    } else if (st == AppLifecycleState.paused ||
        st == AppLifecycleState.hidden) {
      _left ??= DateTime.now();
    } else if (st == AppLifecycleState.resumed) {
      final l = _left;
      _left = null;
      if (l != null &&
          !s.locked &&
          DateTime.now().difference(l).inSeconds >= s.lockAfter) {
        s.lockNow();
      }
      setState(() => _cover = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        widget.child,
        if (s.locked)
          Positioned.fill(child: LockScreen(state: s))
        else if (_cover && s.lockEnabled)
          Positioned.fill(
            child: ColoredBox(
              color: cs.surface,
              child: Center(
                  child: Icon(Icons.eco_rounded, size: 72, color: cs.primary)),
            ),
          ),
      ],
    );
  }
}

class LockScreen extends StatefulWidget {
  final AppState state;
  const LockScreen({super.key, required this.state});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.state.bioEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bio());
    }
  }

  Future<void> _bio() async {
    final ok = await Bio.auth();
    if (ok && mounted) widget.state.unlock();
  }

  Future<void> _submit(String pin) async {
    final r = await PinStore.verify(pin);
    if (!mounted) return;
    if (r.ok) {
      widget.state.unlock();
    } else {
      setState(() => _error = pinError(r));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.eco_rounded, size: 64, color: cs.primary),
                const SizedBox(height: 8),
                Text('MintAI', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 28),
                PinPad(
                  length: widget.state.pinLen,
                  title: 'Введите PIN',
                  error: _error,
                  onSubmit: _submit,
                  onBio: widget.state.bioEnabled ? _bio : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Настройки блокировки ─────────────────────────

class PinSetupPage extends StatefulWidget {
  const PinSetupPage({super.key});
  @override
  State<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends State<PinSetupPage> {
  String? _first;
  String? _error;

  void _submit(String pin) {
    if (_first == null) {
      setState(() {
        _first = pin;
        _error = null;
      });
    } else if (_first == pin) {
      Navigator.pop(context, pin);
    } else {
      setState(() {
        _first = null;
        _error = 'PIN не совпадает, попробуйте снова';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PIN-код')),
      body: Center(
        child: SingleChildScrollView(
          child: PinPad(
            title: _first == null ? 'Придумайте PIN (4–8 цифр)' : 'Повторите PIN',
            error: _error,
            onSubmit: _submit,
          ),
        ),
      ),
    );
  }
}

class PinVerifyPage extends StatefulWidget {
  final int length;
  const PinVerifyPage({super.key, required this.length});
  @override
  State<PinVerifyPage> createState() => _PinVerifyPageState();
}

class _PinVerifyPageState extends State<PinVerifyPage> {
  String? _error;

  Future<void> _submit(String pin) async {
    final r = await PinStore.verify(pin);
    if (!mounted) return;
    if (r.ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = pinError(r));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Подтверждение')),
      body: Center(
        child: SingleChildScrollView(
          child: PinPad(
            length: widget.length,
            title: 'Введите текущий PIN',
            error: _error,
            onSubmit: _submit,
          ),
        ),
      ),
    );
  }
}

class LockSettingsPage extends StatefulWidget {
  final AppState state;
  const LockSettingsPage({super.key, required this.state});
  @override
  State<LockSettingsPage> createState() => _LockSettingsPageState();
}

class _LockSettingsPageState extends State<LockSettingsPage> {
  bool _bioOk = false;

  static const _delays = {0: 'Сразу', 60: 'Через 1 мин', 300: 'Через 5 мин'};

  @override
  void initState() {
    super.initState();
    Bio.available().then((v) {
      if (mounted) setState(() => _bioOk = v);
    });
  }

  Future<String?> _newPin() => Navigator.push<String>(
      context, MaterialPageRoute(builder: (_) => const PinSetupPage()));

  Future<bool> _checkPin() async =>
      await Navigator.push<bool>(
          context,
          MaterialPageRoute(
              builder: (_) => PinVerifyPage(length: widget.state.pinLen))) ??
      false;

  Future<void> _toggle(bool on) async {
    final s = widget.state;
    if (on) {
      final pin = await _newPin();
      if (pin != null) await s.enableLock(pin);
    } else if (await _checkPin()) {
      await s.disableLock();
    }
    if (mounted) setState(() {});
  }

  Future<void> _change() async {
    if (!await _checkPin() || !mounted) return;
    final pin = await _newPin();
    if (pin != null) await widget.state.changePin(pin);
  }

  Future<void> _toggleBio(bool on) async {
    final s = widget.state;
    if (on && !await Bio.auth()) return; // включаем только после успешной проверки
    s.change(() => s.bioEnabled = on);
    if (mounted) setState(() {});
  }

  Future<void> _pickDelay() async {
    final s = widget.state;
    final r = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Блокировать'),
        children: [
          for (final e in _delays.entries)
            ListTile(
              title: Text(e.value),
              trailing: e.key == s.lockAfter ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, e.key),
            ),
        ],
      ),
    );
    if (r != null) {
      s.change(() => s.lockAfter = r);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Scaffold(
      appBar: AppBar(title: const Text('Блокировка')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Блокировка PIN-кодом'),
            subtitle: const Text('Запрашивать PIN при открытии приложения'),
            value: s.lockEnabled,
            onChanged: _toggle,
          ),
          if (s.lockEnabled) ...[
            ListTile(
              title: const Text('Сменить PIN'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _change,
            ),
            SwitchListTile(
              title: const Text('Вход по биометрии'),
              subtitle: Text(_bioOk
                  ? 'Отпечаток пальца или лицо'
                  : 'Недоступно: биометрия не настроена на устройстве'),
              value: s.bioEnabled,
              onChanged: _bioOk ? _toggleBio : null,
            ),
            ListTile(
              title: const Text('Блокировать'),
              trailing: Text(_delays[s.lockAfter] ?? 'Сразу'),
              onTap: _pickDelay,
            ),
          ],
        ],
      ),
    );
  }
}
