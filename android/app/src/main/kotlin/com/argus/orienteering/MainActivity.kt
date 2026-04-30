package com.argus.orienteering

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
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
    private var mediaPlayer: MediaPlayer? = null

    @Synchronized
    fun play(context: Context, requestedVolume: Double) {
        stop(context)

        val volume = requestedVolume.coerceIn(0.0, 1.0).toFloat()
        val appContext = context.applicationContext
        val asset = appContext.resources.openRawResourceFd(R.raw.alarm) ?: return
        try {
            mediaPlayer = MediaPlayer().apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    )
                }
                setDataSource(asset.fileDescriptor, asset.startOffset, asset.length)
                isLooping = true
                setVolume(volume, volume)
                prepare()
                start()
            }
        } finally {
            asset.close()
        }
    }

    @Synchronized
    fun stop(context: Context? = null) {
        mediaPlayer?.let { player ->
            try {
                if (player.isPlaying) {
                    player.stop()
                }
            } catch (_: IllegalStateException) {
                // The player may already be stopping while the activity is being destroyed.
            } finally {
                player.release()
            }
        }
        mediaPlayer = null
        context?.let(::cancelVibration)
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


