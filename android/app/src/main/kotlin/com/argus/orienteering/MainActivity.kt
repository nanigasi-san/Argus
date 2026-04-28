package com.argus.orienteering

import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onDestroy() {
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, RINGTONE_CHANNEL).invokeMethod("stop", null)
        }
        super.onDestroy()
    }

    companion object {
        private const val RINGTONE_CHANNEL = "flutter_ringtone_player"
    }
}



