package com.argus.orienteering

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
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
            cancelVibration(appContext)
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

private class NativeAlarmException(
    val code: String,
    override val message: String
) : Exception(message)
