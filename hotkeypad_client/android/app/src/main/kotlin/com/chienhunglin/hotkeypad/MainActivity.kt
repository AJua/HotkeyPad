package com.chienhunglin.hotkeypad

import android.bluetooth.BluetoothAdapter
import android.os.Bundle
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Serves this phone's own Bluetooth-assigned name to the Dart side, so the
 * host can tell connected clients apart by name rather than a bare id, and
 * keeps the status/navigation bars hidden — see [hideSystemBars]'s own doc
 * comment for why that needs doing natively rather than solely through
 * Flutter's own `SystemChrome` call (`main.dart`'s `_hideSystemBars`, kept
 * for iOS and pre-15 Android, where it still works fine on its own). */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        hideSystemBars()
    }

    /**
     * Android 15+'s mandatory edge-to-edge enforcement is about *layout* —
     * content draws behind the bars, which this app wants anyway — not
     * *visibility*: `WindowInsetsControllerCompat.hide` still actually
     * hides them. What stopped working at that OS version is Flutter's own
     * `SystemChrome.setEnabledSystemUIMode(immersiveSticky)`, built on the
     * older system-UI-flags API edge-to-edge enforcement overrides (see
     * https://docs.flutter.dev/release/breaking-changes/default-systemuimode-edge-to-edge).
     * This drives the modern AndroidX API directly instead, bypassing that.
     */
    private fun hideSystemBars() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.hide(WindowInsetsCompat.Type.systemBars())
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    }

    // The standard place Android itself recommends reapplying immersive
    // flags: onResume alone misses a focus change with no lifecycle
    // transition of its own — a permission dialog or the keyboard closing,
    // either of which can leave the bars shown again — while this fires on
    // every one of those too.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemBars()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "btlink/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "name" -> result.success(deviceName())
                    else -> result.notImplemented()
                }
            }
    }

    /** Null if Bluetooth is off, unsupported, or the permission was denied —
     * any of which the Dart side already treats as "no name available". */
    private fun deviceName(): String? {
        return try {
            BluetoothAdapter.getDefaultAdapter()?.name
        } catch (_: SecurityException) {
            null
        }
    }
}
