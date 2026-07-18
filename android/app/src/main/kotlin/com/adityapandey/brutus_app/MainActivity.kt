package com.adityapandey.brutus_app

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val pcmPlayer = PcmStreamPlayer(this)
    private lateinit var automationChannel: MethodChannel

    /**
     * Pending screen-capture request. Set when Flutter calls
     * `requestScreenCapture` and consumed by [onActivityResult].
     */
    private data class PendingCapture(
        val result: MethodChannel.Result,
        val intervalMs: Long,
        val jpegQuality: Int,
        val maxDimension: Int,
    )
    private var pendingCapture: PendingCapture? = null

    companion object {
        private const val SCREEN_CAPTURE_REQUEST_CODE = 9912
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── PCM player (Phase 2 audio output) ──
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.adityapandey.brutus_app/pcm_player"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    pcmPlayer.start()
                    result.success(null)
                }
                "write" -> {
                    val bytes = call.arguments as? ByteArray
                    if (bytes != null) {
                        pcmPlayer.write(bytes)
                        result.success(null)
                    } else {
                        result.error("BAD_ARGS", "expected ByteArray", null)
                    }
                }
                "flush" -> {
                    pcmPlayer.flushQueue()
                    result.success(null)
                }
                "pause" -> {
                    pcmPlayer.pause()
                    result.success(null)
                }
                "stop" -> {
                    pcmPlayer.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // ── Phone Automation (Phase 4) ──
        automationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.adityapandey.brutus_app/phone_automation"
        )
        val handler = PhoneAutomationChannel(this, automationChannel)
        automationChannel.setMethodCallHandler { call, result ->
            // Intercept screen-capture calls — they need Activity-level
            // intent dispatch, not the channel handler's stateless context.
            when (call.method) {
                "requestScreenCapture" -> {
                    val intervalMs = (call.argument<Number>("intervalMs")
                        ?: 2000L).toLong()
                    val jpegQuality = (call.argument<Number>("jpegQuality")
                        ?: 60).toInt()
                    val maxDimension = (call.argument<Number>("maxDimension")
                        ?: 1280).toInt()
                    requestScreenCapture(result, intervalMs, jpegQuality, maxDimension)
                }
                "stopScreenCapture" -> {
                    val stop = Intent(this, ScreenCaptureService::class.java)
                        .setAction(ScreenCaptureService.ACTION_STOP)
                    startService(stop)
                    result.success(true)
                }
                "isScreenCapturing" -> result.success(ScreenCaptureService.isRunning())
                else -> handler.handle(call, result)
            }
        }

        // The notification listener service uses this same channel to
        // push events back to Flutter via `onNotificationPosted` /
        // `onNotificationRemoved` invokeMethod calls.
        BrutusNotificationListenerService.eventSink = automationChannel
        // The screen capture service uses the same sink for `onScreenCaptureFrame`.
        ScreenCaptureService.eventSink = automationChannel

        // ── Robot (BLE / HM-10) ──
        // BLE is now handled entirely in Dart via flutter_blue_plus.
        // No native MethodChannel needed — the old RobotChannel / Brutus Link
        // IPC stack has been removed.
    }

    private fun requestScreenCapture(
        result: MethodChannel.Result,
        intervalMs: Long,
        jpegQuality: Int,
        maxDimension: Int,
    ) {
        if (ScreenCaptureService.isRunning()) {
            result.success(true)
            return
        }
        if (pendingCapture != null) {
            result.error("BUSY", "Screen capture consent already in flight.", null)
            return
        }
        pendingCapture = PendingCapture(result, intervalMs, jpegQuality, maxDimension)
        try {
            val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            startActivityForResult(
                mpm.createScreenCaptureIntent(),
                SCREEN_CAPTURE_REQUEST_CODE,
            )
        } catch (t: Throwable) {
            pendingCapture = null
            result.error("EXCEPTION", t.message ?: t.javaClass.simpleName, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == SCREEN_CAPTURE_REQUEST_CODE) {
            val pending = pendingCapture
            pendingCapture = null
            if (pending == null) {
                super.onActivityResult(requestCode, resultCode, data)
                return
            }
            if (resultCode != Activity.RESULT_OK || data == null) {
                pending.result.success(false)
                return
            }
            val intent = Intent(this, ScreenCaptureService::class.java).apply {
                action = ScreenCaptureService.ACTION_START
                putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
                putExtra(ScreenCaptureService.EXTRA_RESULT_INTENT, data)
                putExtra(ScreenCaptureService.EXTRA_INTERVAL_MS, pending.intervalMs)
                putExtra(ScreenCaptureService.EXTRA_JPEG_QUALITY, pending.jpegQuality)
                putExtra(ScreenCaptureService.EXTRA_MAX_DIMENSION, pending.maxDimension)
            }
            try {
                if (Build.VERSION.SDK_INT >= 26) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
                pending.result.success(true)
            } catch (t: Throwable) {
                pending.result.error("EXCEPTION", t.message, null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun onDestroy() {
        try {
            pcmPlayer.stop()
        } catch (_: Throwable) {
        }
        BrutusNotificationListenerService.eventSink = null
        ScreenCaptureService.eventSink = null
        super.onDestroy()
    }
}
