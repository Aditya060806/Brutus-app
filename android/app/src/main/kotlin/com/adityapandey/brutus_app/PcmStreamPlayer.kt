package com.adityapandey.brutus_app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Streams 24kHz mono 16-bit PCM into a persistent AudioTrack.
 *
 * Designed for Gemini Live native-audio replies. Unlike [android.media.MediaPlayer]
 * (used by `audioplayers`), AudioTrack stays open between chunks, so we don't
 * re-acquire audio focus or seek/prepare for every blob. That gives us:
 *   • zero gaps between chunks (continuous playback)
 *   • no audio-focus storms that kill the mic stream
 *   • bounded latency (writes block when the internal buffer is full)
 */
class PcmStreamPlayer(private val context: Context) {

    private var track: AudioTrack? = null
    private val isPlaying = AtomicBoolean(false)
    private var writerThread: Thread? = null
    private val pendingChunks = ArrayDeque<ByteArray>()
    private val pendingLock = Object()

    private val sampleRate = 24000
    private val channelConfig = AudioFormat.CHANNEL_OUT_MONO
    private val audioFormat = AudioFormat.ENCODING_PCM_16BIT

    @Synchronized
    fun start() {
        if (track != null) return

        val minBuf = AudioTrack.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        // Buffer = ~300 ms. Big enough to absorb GC / scheduler jitter on
        // Samsung devices during long voice-chat replies, but small enough
        // that AudioTrack's default start threshold (half the buffer) is
        // crossed by short bursts too. Previously we used a 2-second buffer
        // which meant the start threshold was 48 KB — a single 3 KB TTS
        // chunk never crossed it, so short Speak-for-me clips never
        // actually reached the speaker even though `write()` returned
        // success.
        val bufferSize = maxOf(minBuf * 4, sampleRate * 2 * 300 / 1000)

        val attrs = AudioAttributes.Builder()
            // CONTENT_TYPE_MUSIC + USAGE_MEDIA — forces output to the
            // loudspeaker on Samsung One UI even when the audio mode is
            // MODE_IN_COMMUNICATION (set by the recorder for BT/SCO
            // routing). With CONTENT_TYPE_SPEECH, short bursts under
            // communication mode get routed to the earpiece, which is
            // why short Speak-for-me clips were either inaudible or
            // played quietly through the earpiece while longer voice
            // chat replies eventually warmed up to the speaker.
            // MUSIC content type bypasses that decision and always goes
            // to the configured media output.
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .build()
        val format = AudioFormat.Builder()
            .setSampleRate(sampleRate)
            .setEncoding(audioFormat)
            .setChannelMask(channelConfig)
            .build()

        track = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            AudioTrack.Builder()
                .setAudioAttributes(attrs)
                .setAudioFormat(format)
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STREAM)
                // PERFORMANCE_MODE_NONE — we want stability, not the
                // shrunk-buffer low-latency path. Underrun glitches were
                // causing speaker re-engagement reverb to bleed into the
                // mic and confuse Gemini's VAD.
                .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_NONE)
                .build()
        } else {
            @Suppress("DEPRECATION")
            AudioTrack(
                AudioManager.STREAM_MUSIC,
                sampleRate,
                channelConfig,
                audioFormat,
                bufferSize,
                AudioTrack.MODE_STREAM
            )
        }

        track?.play()
        isPlaying.set(true)

        // Force the AudioTrack to a real loud output. On Samsung One UI
        // when the recorder has put the system into MODE_IN_COMMUNICATION
        // (or when BT SCO is active for voice chat), the policy will
        // happily route a MEDIA stream to the earpiece for short bursts.
        // Picking the device explicitly bypasses that decision.
        //
        // Preference order:
        //   1. Wired headset / USB headset — user explicitly plugged it in
        //   2. Bluetooth A2DP — high-quality stereo BT (NOT SCO, which is
        //      mono and reserved for the recorder)
        //   3. Built-in loudspeaker — the answer for the bare phone case
        //
        // We deliberately exclude BUILTIN_EARPIECE and BLUETOOTH_SCO.
        try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            val priorities = intArrayOf(
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_USB_HEADSET,
                AudioDeviceInfo.TYPE_USB_DEVICE,
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                AudioDeviceInfo.TYPE_BLE_HEADSET,
                AudioDeviceInfo.TYPE_BLE_SPEAKER,
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
            )
            var picked: AudioDeviceInfo? = null
            for (priority in priorities) {
                picked = devices.firstOrNull { it.type == priority }
                if (picked != null) break
            }
            if (picked != null) {
                val ok = track?.setPreferredDevice(picked) ?: false
                Log.i(
                    "PcmStreamPlayer",
                    "Preferred output device: ${deviceTypeName(picked.type)} (set=$ok)",
                )
            } else {
                Log.w("PcmStreamPlayer", "No output device matched our priority list")
            }
        } catch (t: Throwable) {
            Log.w("PcmStreamPlayer", "setPreferredDevice failed: ${t.message}")
        }

        // Drop the start threshold to ~50 ms. AudioTrack's default
        // threshold equals half the buffer size, which on a 300 ms buffer
        // = 150 ms (about 7 KB of 24 kHz mono PCM) — fine for our shortest
        // TTS bursts, but explicitly lowering it makes single-chunk clips
        // start playing immediately instead of waiting for more data.
        try {
            track?.setStartThresholdInFrames(sampleRate * 50 / 1000)
        } catch (_: Throwable) {
            // setStartThresholdInFrames was added in API 31. Older devices
            // fall back to the default (half the buffer).
        }

        // Prime the AudioTrack with 80 ms of silence (PCM zeros). This
        // guarantees two things on Samsung One UI when the audio mode is
        // MODE_IN_COMMUNICATION (set by the recorder for BT/SCO routing):
        //
        //   1. The track always crosses the start threshold immediately,
        //      so single-chunk Speak-for-me clips ("hi", "नमस्ते") start
        //      playing instead of sitting silently in the ring buffer.
        //   2. Android's audio policy gets ~80 ms to resolve the output
        //      device (USAGE_MEDIA → loudspeaker) before the first real
        //      sample lands. Without this, the policy decision was racing
        //      with the chunk consumption and short clips occasionally
        //      ended up routed to the earpiece before the routing settled.
        //
        // The silence is enqueued BEFORE the writer thread starts so it
        // always runs before any chunk that arrives via [write].
        val silenceBytes = sampleRate * 2 * 80 / 1000 // 80 ms, 16-bit mono
        val silence = ByteArray(silenceBytes)
        synchronized(pendingLock) {
            pendingChunks.addLast(silence)
        }

        writerThread = Thread {
            // Boost priority so OS scheduler treats this like a media
            // playback thread. Without this, GC pauses or unrelated work
            // can starve our writes for >100 ms and the AudioTrack ring
            // buffer underruns — producing audible glitches and a fresh
            // speaker re-engagement reverb that confuses Gemini's VAD.
            try {
                android.os.Process.setThreadPriority(
                    android.os.Process.THREAD_PRIORITY_URGENT_AUDIO,
                )
            } catch (_: Throwable) {}
            while (isPlaying.get()) {
                val chunk: ByteArray? = synchronized(pendingLock) {
                    while (isPlaying.get() && pendingChunks.isEmpty()) {
                        try {
                            pendingLock.wait(250)
                        } catch (_: InterruptedException) {
                            return@synchronized null
                        }
                    }
                    if (!isPlaying.get()) null else pendingChunks.removeFirstOrNull()
                }
                val bytes = chunk ?: continue
                val t = track ?: break
                var offset = 0
                while (offset < bytes.size && isPlaying.get()) {
                    val written = t.write(bytes, offset, bytes.size - offset)
                    if (written <= 0) break
                    offset += written
                }
            }
        }.also {
            it.isDaemon = true
            it.name = "BrutusPcmWriter"
            it.start()
        }
    }

    fun write(bytes: ByteArray) {
        if (!isPlaying.get()) start()
        // If we were paused (idle timeout fired), resume playback before
        // accepting the new chunk. Without this, paused tracks silently
        // drop writes until you call play() again.
        try {
            val t = track
            if (t != null && t.playState == AudioTrack.PLAYSTATE_PAUSED) {
                t.play()
            }
        } catch (_: Throwable) {}
        synchronized(pendingLock) {
            pendingChunks.addLast(bytes)
            pendingLock.notifyAll()
        }
    }

    /**
     * Pause the AudioTrack without releasing it. Called from Dart when 600ms
     * of silence elapses after the last chunk. This is critical on Samsung
     * devices: an active STREAM_MUSIC AudioTrack keeps the audio policy in
     * "media playing" mode and silences the concurrent mic recorder. Pausing
     * the track flushes that state so the mic unsuspends and the user's next
     * utterance reaches Gemini.
     */
    @Synchronized
    fun pause() {
        try {
            val t = track
            if (t != null && t.playState == AudioTrack.PLAYSTATE_PLAYING) {
                t.pause()
                t.flush()
            }
        } catch (_: Throwable) {}
    }

    fun flushQueue() {
        synchronized(pendingLock) {
            pendingChunks.clear()
            pendingLock.notifyAll()
        }
        try {
            track?.pause()
            track?.flush()
            track?.play()
        } catch (_: Throwable) {
        }
    }

    @Synchronized
    fun stop() {
        isPlaying.set(false)
        synchronized(pendingLock) {
            pendingChunks.clear()
            pendingLock.notifyAll()
        }
        try {
            writerThread?.interrupt()
        } catch (_: Throwable) {
        }
        writerThread = null
        try {
            track?.pause()
            track?.flush()
            track?.stop()
            track?.release()
        } catch (_: Throwable) {
        }
        track = null
    }

    private fun deviceTypeName(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "BUILTIN_SPEAKER"
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "BUILTIN_EARPIECE"
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "WIRED_HEADSET"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "WIRED_HEADPHONES"
        AudioDeviceInfo.TYPE_USB_HEADSET -> "USB_HEADSET"
        AudioDeviceInfo.TYPE_USB_DEVICE -> "USB_DEVICE"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "BLUETOOTH_A2DP"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "BLUETOOTH_SCO"
        AudioDeviceInfo.TYPE_BLE_HEADSET -> "BLE_HEADSET"
        AudioDeviceInfo.TYPE_BLE_SPEAKER -> "BLE_SPEAKER"
        else -> "OTHER($type)"
    }
}
