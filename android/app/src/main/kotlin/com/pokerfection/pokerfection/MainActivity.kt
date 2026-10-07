package com.pokerfection.pokerfection

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Held while hosting a room: without it Android may drop the Wi-Fi
    // broadcasts of friends looking for the room by its code.
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Where the app keeps its settings file; while hosting a room, keeping
        // the screen on (the room stops when the app goes to sleep) and
        // hearing the Wi-Fi's broadcasts.
        MethodChannel(messenger, "pokerfection/platform").setMethodCallHandler { call, result ->
            when (call.method) {
                "dataFolder" -> result.success(filesDir.absolutePath)
                "keepScreenOn" -> {
                    if (call.arguments == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                "hearBroadcasts" -> {
                    if (call.arguments == true) {
                        if (multicastLock == null) {
                            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                            multicastLock = wifi?.createMulticastLock("PokerFection room")?.apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                        }
                    } else {
                        multicastLock?.release()
                        multicastLock = null
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Sound effects: short 16-bit mono WAV files made by the app.
        MethodChannel(messenger, "pokerfection/sound").setMethodCallHandler { call, result ->
            if (call.method == "play") {
                (call.arguments as? ByteArray)?.let { play(it) }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun play(wav: ByteArray) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || wav.size <= 44) return
        val rate = (wav[24].toInt() and 0xff) or ((wav[25].toInt() and 0xff) shl 8) or
            ((wav[26].toInt() and 0xff) shl 16) or ((wav[27].toInt() and 0xff) shl 24)
        val pcm = wav.copyOfRange(44, wav.size)
        try {
            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_GAME)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(rate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setTransferMode(AudioTrack.MODE_STATIC)
                .setBufferSizeInBytes(pcm.size)
                .build()
            track.write(pcm, 0, pcm.size)
            track.play()
            // Free the track once it has finished.
            val millis = pcm.size / 2 * 1000L / rate + 200
            Handler(Looper.getMainLooper()).postDelayed({ track.release() }, millis)
        } catch (e: Exception) {
            // No sound this time.
        }
    }
}
