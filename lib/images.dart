import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'secure.dart';

/// Тип изображения по первым байтам (для data-URL и API).
String mimeOf(Uint8List b) {
  if (b.length > 12) {
    if (b[0] == 0x89 && b[1] == 0x50) return 'image/png';
    if (b[0] == 0x47 && b[1] == 0x49) return 'image/gif';
    if (b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45) {
      return 'image/webp';
    }
  }
  return 'image/jpeg';
}

/// Фото из чатов хранятся отдельными зашифрованными файлами (AES-256-GCM),
/// а не внутри истории, чтобы она не раздувалась. В инкогнито на диск не пишется ничего.
class ImgStore {
  static Directory? _dir;

  static Future<Directory> _d() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getApplicationDocumentsDirectory();
    return _dir = await Directory('${base.path}/imgs').create(recursive: true);
  }

  /// Возвращает id файла или null, если сохранить не удалось.
  static Future<String?> save(Uint8List bytes) async {
    try {
      final id =
          '${DateTime.now().microsecondsSinceEpoch}${Random.secure().nextInt(1 << 20)}';
      final f = File('${(await _d()).path}/$id.enc');
      await f.writeAsBytes(await Crypto.encryptBytes(bytes), flush: true);
      return id;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> load(String id) async {
    try {
      final f = File('${(await _d()).path}/$id.enc');
      return await Crypto.decryptBytes(await f.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  static Future<void> delete(String id) async {
    try {
      await File('${(await _d()).path}/$id.enc').delete();
    } catch (_) {}
  }
}
