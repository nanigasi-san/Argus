package com.argus.orienteering

import android.content.Context
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> {
                        val volume = call.argument<Double>("volume") ?: 1.0
                        NativeAlarmPlayer.play(applicationContext, volume)
                        result.success(null)
                    }
                    "stop" -> {
                        NativeAlarmPlayer.stop(applicationContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onStop() {
        if (isFinishing) {
            NativeAlarmPlayer.stop(applicationContext)
        }
        super.onStop()
    }

    override fun onDestroy() {
        NativeAlarmPlayer.stop(applicationContext)
        super.onDestroy()
    }

    companion object {
        private const val ALARM_CHANNEL = "argus/alarm"
    }
}

private object NativeAlarmPlayer {
    private var ringtone: Ringtone? = null

    @Synchronized
    fun play(context: Context, requestedVolume: Double) {
        stop(context)

        val volume = requestedVolume.coerceIn(0.0, 1.0).toFloat()
        val appContext = context.applicationContext
        val alarmUri = resolveAlarmUri(appContext) ?: return
        ringtone = RingtoneManager.getRingtone(appContext, alarmUri)?.apply {
            @Suppress("DEPRECATION")
            streamType = AudioManager.STREAM_ALARM
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                isLooping = true
                setVolume(volume)
            }
            play()
        }
    }

    @Synchronized
    fun stop(context: Context? = null) {
        ringtone?.let { player ->
            try {
                player.stop()
            } catch (_: RuntimeException) {
                // The player may already be stopping while the activity is being destroyed.
            }
        }
        ringtone = null
        context?.let(::cancelVibration)
    }

    private fun resolveAlarmUri(context: Context): Uri? {
        return RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_RINGTONE)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
    }

    private fun cancelVibration(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = context.getSystemService(VibratorManager::class.java)
            manager?.defaultVibrator?.cancel()
            return
        }

        @Suppress("DEPRECATION")
        val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        vibrator?.cancel()
    }
}
