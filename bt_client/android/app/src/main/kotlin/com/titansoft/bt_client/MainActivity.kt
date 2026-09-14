package com.titansoft.bt_client

import android.bluetooth.BluetoothAdapter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Serves this phone's own Bluetooth-assigned name to the Dart side, so the
 * host can tell connected clients apart by name rather than a bare id. */
class MainActivity : FlutterActivity() {
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
