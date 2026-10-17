import 'package:flutter/services.dart';

class IconOpt {
  final String id, name, asset;
  const IconOpt(this.id, this.name, this.asset);
}

/// Смена иконки приложения: на Android включается один из activity-alias
/// (см. android_patch/AndroidManifest.xml и MainActivity.kt).
class AppIcon {
  static const _c = MethodChannel('mintai/icon');

  static const options = [
    IconOpt('mint', 'Мятная', 'assets/icons/mint.png'),
    IconOpt('graphite', 'Графит', 'assets/icons/graphite.png'),
    IconOpt('blue', 'Синяя', 'assets/icons/blue.png'),
  ];

  static String nameOf(String id) =>
      options.firstWhere((o) => o.id == id, orElse: () => options.first).name;

  static Future<String> get() async {
    try {
      return await _c.invokeMethod<String>('get') ?? 'mint';
    } catch (_) {
      return 'mint';
    }
  }

  static Future<bool> set(String id) async {
    try {
      await _c.invokeMethod('set', id);
      return true;
    } catch (_) {
      return false;
    }
  }
}
