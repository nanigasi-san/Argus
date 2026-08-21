package com.argus.orienteering

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
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
                        try {
                            NativeAlarmPlayer.play(applicationContext, volume)
                            result.success(null)
                        } catch (error: NativeAlarmException) {
                            result.error(error.code, error.message, null)
                        } catch (error: Exception) {
                            result.error(
                                "alarm_play_failed",
                                error.localizedMessage ?: "Android could not start alarm playback.",
                                null
                            )
                        }
                    }
                    "stopAlarm" -> {
                        NativeAlarmPlayer.stop(applicationContext)
                        result.success(null)
                    }
                    "startVibration" -> {
                        NativeVibrationPlayer.start(applicationContext)
                        result.success(null)
                    }
                    "stopVibration" -> {
                        NativeVibrationPlayer.stop(applicationContext)
                        result.success(null)
                    }
                    "pulseVibration" -> {
                        val durationMs =
                            call.argument<Number>("durationMs")?.toLong() ?: 350L
                        NativeVibrationPlayer.pulse(applicationContext, durationMs)
                        result.success(null)
                    }
                    "getAlarmVolumeState" -> {
                        result.success(NativeAlarmPlayer.getAlarmVolumeState(applicationContext))
                    }
                    "getAlertPlaybackState" -> {
                        result.success(
                            mapOf(
                                "alarmActive" to NativeAlarmPlayer.isActive(),
                                "vibrationPatternActive" to NativeVibrationPlayer.isPatternActive()
                            )
                        )
                    }
                    "openSoundSettings" -> {
                        result.success(openSoundSettings())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onStop() {
        if (isFinishing) {
            NativeAlarmPlayer.stop(applicationContext)
            NativeVibrationPlayer.stop(applicationContext)
        }
        super.onStop()
    }

    override fun onDestroy() {
        NativeAlarmPlayer.stop(applicationContext)
        NativeVibrationPlayer.stop(applicationContext)
        super.onDestroy()
    }

    companion object {
        private const val ALARM_CHANNEL = "argus/alarm"
    }

    private fun openSoundSettings(): Boolean {
        return try {
            startActivity(Intent(Settings.ACTION_SOUND_SETTINGS))
            true
        } catch (_: RuntimeException) {
            try {
                startActivity(Intent(Settings.ACTION_SETTINGS))
                true
            } catch (_: RuntimeException) {
                false
            }
        }
    }
}

private object NativeAlarmPlayer {
    private var mediaPlayer: MediaPlayer? = null
    private var focusRequest: AudioFocusRequest? = null
    private val focusChangeListener = AudioManager.OnAudioFocusChangeListener { }

    @Synchronized
    fun play(context: Context, requestedVolume: Double) {
        stop(context)

        val volume = requestedVolume.coerceIn(0.0, 1.0).toFloat()
        val appContext = context.applicationContext
        val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            ?: throw NativeAlarmException(
                "alarm_audio_service_unavailable",
                "Android audio service is unavailable."
            )

        if (!requestAudioFocus(audioManager)) {
            throw NativeAlarmException(
                "alarm_audio_focus_denied",
                "Android denied alarm audio focus."
            )
        }

        val asset = try {
            appContext.resources.openRawResourceFd(R.raw.alarm)
        } catch (_: Exception) {
            releaseAudioFocus(audioManager)
            throw NativeAlarmException(
                "alarm_sound_missing",
                "alarm.mp3 is missing from Android raw resources."
            )
        } ?: run {
            releaseAudioFocus(audioManager)
            throw NativeAlarmException(
                "alarm_sound_missing",
                "alarm.mp3 is missing from Android raw resources."
            )
        }

        var player: MediaPlayer? = null
        try {
            player = MediaPlayer().apply {
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
            mediaPlayer = player
        } catch (error: Exception) {
            player?.release()
            mediaPlayer = null
            releaseAudioFocus(audioManager)
            throw NativeAlarmException(
                "alarm_play_failed",
                error.localizedMessage ?: "Android could not start alarm playback."
            )
        } finally {
            asset.close()
        }

        if (mediaPlayer?.isPlaying != true) {
            player?.release()
            mediaPlayer = null
            releaseAudioFocus(audioManager)
            throw NativeAlarmException(
                "alarm_play_failed",
                "Android could not start alarm playback."
            )
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
        context?.let { appContext ->
            val audioManager =
                appContext.applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            releaseAudioFocus(audioManager)
        }
    }

    fun getAlarmVolumeState(context: Context): Map<String, Any> {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val current = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        val percent = if (max > 0) current.toDouble() / max.toDouble() else 1.0
        return mapOf(
            "current" to current,
            "max" to max,
            "percent" to percent,
        )
    }

    @Synchronized
    fun isActive(): Boolean {
        return try {
            mediaPlayer?.isPlaying == true
        } catch (_: IllegalStateException) {
            false
        }
    }

    private fun requestAudioFocus(audioManager: AudioManager): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                .setOnAudioFocusChangeListener(focusChangeListener)
                .build()
            focusRequest = request
            audioManager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusChangeListener,
                AudioManager.STREAM_ALARM,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
            ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    private fun releaseAudioFocus(audioManager: AudioManager?) {
        if (audioManager == null) {
            focusRequest = null
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let(audioManager::abandonAudioFocusRequest)
            focusRequest = null
            return
        }

        @Suppress("DEPRECATION")
        audioManager.abandonAudioFocus(focusChangeListener)
    }

}

private object NativeVibrationPlayer {
    private val pattern = longArrayOf(0, 5000, 2000)
    private var patternActive = false

    @Synchronized
    fun start(context: Context) {
        patternActive = false
        val vibrator = getVibrator(context.applicationContext) ?: return
        if (!vibrator.hasVibrator()) {
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(
                VibrationEffect.createWaveform(pattern, 0)
            )
            patternActive = true
            return
        }

        @Suppress("DEPRECATION")
        vibrator.vibrate(pattern, 0)
        patternActive = true
    }

    @Synchronized
    fun pulse(context: Context, requestedDurationMs: Long) {
        patternActive = false
        val vibrator = getVibrator(context.applicationContext) ?: return
        if (!vibrator.hasVibrator()) {
            return
        }

        val durationMs = requestedDurationMs.coerceIn(1L, 2_000L)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(
                VibrationEffect.createOneShot(
                    durationMs,
                    VibrationEffect.DEFAULT_AMPLITUDE
                )
            )
            return
        }

        @Suppress("DEPRECATION")
        vibrator.vibrate(durationMs)
    }

    @Synchronized
    fun stop(context: Context) {
        patternActive = false
        getVibrator(context.applicationContext)?.cancel()
    }

    @Synchronized
    fun isPatternActive(): Boolean = patternActive

    private fun getVibrator(context: Context): Vibrator? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = context.getSystemService(VibratorManager::class.java)
            return manager?.defaultVibrator
        }

        @Suppress("DEPRECATION")
        return context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }
}

private class NativeAlarmException(
    val code: String,
    override val message: String
) : Exception(message)
