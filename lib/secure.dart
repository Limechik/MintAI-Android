import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Шифрование данных приложения: AES-256-GCM.
/// Мастер-ключ генерируется на устройстве и лежит в защищённом хранилище
/// Android (Keystore) через flutter_secure_storage.
class Crypto {
  static const _store = FlutterSecureStorage();
  static final _aes = AesGcm.with256bits();
  static const _keyName = 'mintai_master_key';
  static late SecretKey _key;

  static Future<void> init() async {
    String? b64;
    try {
      b64 = await _store.read(key: _keyName);
    } catch (_) {
      // Хранилище повреждено (например, после восстановления из бэкапа):
      // старые данные расшифровать уже нельзя, начинаем с чистого ключа.
      await _store.deleteAll();
    }
    if (b64 == null) {
      final bytes = await (await _aes.newSecretKey()).extractBytes();
      b64 = base64Encode(bytes);
      await _store.write(key: _keyName, value: b64);
    }
    _key = SecretKey(base64Decode(b64));
  }

  /// Формат: "v1:" + base64(nonce[12] + шифртекст + тег[16]).
  static Future<String> encrypt(String plain) async {
    final box = await _aes.encrypt(utf8.encode(plain), secretKey: _key);
    return 'v1:${base64Encode(box.concatenation())}';
  }

  /// Возвращает null, если данные повреждены или зашифрованы другим ключом.
  static Future<String?> decrypt(String data) async {
    if (!data.startsWith('v1:')) return null;
    try {
      final box = SecretBox.fromConcatenation(
        base64Decode(data.substring(3)),
        nonceLength: 12,
        macLength: 16,
      );
      return utf8.decode(await _aes.decrypt(box, secretKey: _key));
    } catch (_) {
      return null;
    }
  }

  /// Для файлов (фото): nonce[12] + шифртекст + тег[16].
  static Future<Uint8List> encryptBytes(List<int> data) async {
    final box = await _aes.encrypt(data, secretKey: _key);
    return Uint8List.fromList(box.concatenation());
  }

  static Future<Uint8List?> decryptBytes(List<int> data) async {
    try {
      final box = SecretBox.fromConcatenation(data, nonceLength: 12, macLength: 16);
      return Uint8List.fromList(await _aes.decrypt(box, secretKey: _key));
    } catch (_) {
      return null;
    }
  }
}
