// Скопируйте поверх android/app/src/main/kotlin/com/lime/mintai/MainActivity.kt
package com.lime.mintai

import android.content.ComponentName
import android.content.pm.PackageManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity нужен для биометрии (local_auth).
// Канал mintai/secure — FLAG_SECURE (запрет скриншотов и превью в «Недавних»).
// Канал mintai/icon — смена иконки приложения через activity-alias из манифеста.
class MainActivity : FlutterFragmentActivity() {
    private val aliases = mapOf(
        "mint" to "IconMint",
        "graphite" to "IconGraphite",
        "blue" to "IconBlue",
    )

    private fun component(alias: String) = ComponentName(packageName, "$packageName.$alias")

    private fun isEnabled(id: String, alias: String): Boolean =
        when (packageManager.getComponentEnabledSetting(component(alias))) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
            else -> id == "mint" // по умолчанию, как в манифесте, включён только мятный
        }

    private fun setIcon(id: String) {
        val target = aliases[id] ?: return
        // сначала включаем новый, потом выключаем остальные
        packageManager.setComponentEnabledSetting(
            component(target),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        for ((_, alias) in aliases) {
            if (alias != target) {
                packageManager.setComponentEnabledSetting(
                    component(alias),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP,
                )
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "mintai/secure").setMethodCallHandler { call, result ->
            if (call.method == "setSecure") {
                val on = call.arguments as? Boolean ?: false
                runOnUiThread {
                    if (on) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(messenger, "mintai/icon").setMethodCallHandler { call, result ->
            when (call.method) {
                "get" -> result.success(
                    aliases.entries.firstOrNull { isEnabled(it.key, it.value) }?.key ?: "mint"
                )
                "set" -> {
                    setIcon(call.arguments as? String ?: "mint")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
