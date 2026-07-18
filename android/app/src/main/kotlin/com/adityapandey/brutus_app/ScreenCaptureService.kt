package com.adityapandey.brutus_app

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.util.Base64
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicReference

/**
 * Brutus — Screen capture foreground service.
 *
 * Runs MediaProjection in the foreground (Android 10+ mandates it) so we can
 * grab the framebuffer at a configurable cadence and ship JPEG snapshots to
 * Flutter. The Flutter side forwards each one to Gemini Live as a video
 * frame, mirroring the camera-vision flow but for whatever's on-screen.
 *
 * Lifecycle:
 *   1. Flutter calls `requestScreenCapture` → Activity asks the system for
 *      MediaProjection consent (one-shot dialog).
 *   2. On grant, Activity hands the resultCode + Intent to this service via
 *      `EXTRA_RESULT_CODE` / `EXTRA_RESULT_INTENT` and starts it.
 *   3. Service spins up MediaProjection + a VirtualDisplay piped into an
 *      ImageReader. Each available image is encoded to JPEG, base64'd, and
 *      pushed to Flutter on the `eventSink` channel.
 *   4. Flutter calls `stopScreenCapture` → service tears down and self-stops.
 *
 * Privacy / safety:
 *   • No frames are stored on disk; everything stays in memory.
 *   • The foreground notification is mandatory and shows a "screen sharing"
 *     status the user can tap to stop instantly.
 *   • One-shot — once consent is revoked or service is killed, Flutter has
 *     to ask again.
 */
class ScreenCaptureService : Service() {

    companion object {
        private const val TAG = "BrutusScreenCapture"
        private const val NOTIF_CHANNEL_ID = "brutus_screen_capture"
        private const val NOTIF_ID = 4521

        const val EXTRA_RESULT_CODE = "extra_result_code"
        const val EXTRA_RESULT_INTENT = "extra_result_intent"
        const val EXTRA_INTERVAL_MS = "extra_interval_ms"
        const val EXTRA_JPEG_QUALITY = "extra_jpeg_quality"
        const val EXTRA_MAX_DIMENSION = "extra_max_dimension"

        const val ACTION_START = "com.adityapandey.brutus_app.SCREEN_CAPTURE_START"
        const val ACTION_STOP = "com.adityapandey.brutus_app.SCREEN_CAPTURE_STOP"

        private val instance = AtomicReference<ScreenCaptureService?>(null)
        fun current(): ScreenCaptureService? = instance.get()
        fun isRunning(): Boolean = instance.get() != null

        /** Flutter event sink — set by MainActivity once the engine is up. */
        @Volatile var eventSink: MethodChannel? = null
    }

    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var captureThread: HandlerThread? = null
    private var captureHandler: Handler? = null

    @Volatile private var intervalMs: Long = 2000L
    @Volatile private var jpegQuality: Int = 60
    @Volatile private var maxDimension: Int = 1280
    @Volatile private var lastEmittedAt: Long = 0L
    @Volatile private var emittingFrame: Boolean = false

    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopCapture()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START, null -> {
                // CRITICAL: when started via startForegroundService(), Android
                // gives us only 5 s to promote to foreground or it kills the
                // process with RemoteServiceException. Promote *first*,
                // validate consent intent second.
                try {
                    startForeground(NOTIF_ID, buildNotification(), foregroundType())
                } catch (t: Throwable) {
                    Log.e(TAG, "startForeground failed", t)
                    stopSelf()
                    return START_NOT_STICKY
                }
                startInternal(intent)
            }
        }
        return START_STICKY
    }

    private fun startInternal(intent: Intent?) {
        if (intent == null) {
            Log.w(TAG, "null intent — missing consent")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
        val resultData: Intent? = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(EXTRA_RESULT_INTENT, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<Intent>(EXTRA_RESULT_INTENT)
        }

        if (resultCode != Activity.RESULT_OK || resultData == null) {
            Log.w(TAG, "Missing or denied media projection consent")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }

        intervalMs = (intent.getLongExtra(EXTRA_INTERVAL_MS, 2000L)).coerceIn(500L, 10_000L)
        jpegQuality = intent.getIntExtra(EXTRA_JPEG_QUALITY, 60).coerceIn(10, 95)
        maxDimension = intent.getIntExtra(EXTRA_MAX_DIMENSION, 1280).coerceIn(360, 2560)

        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val proj = try {
            mpm.getMediaProjection(resultCode, resultData)
        } catch (t: Throwable) {
            Log.e(TAG, "getMediaProjection failed", t)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        if (proj == null) {
            Log.w(TAG, "Null MediaProjection")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }

        projection = proj
        instance.set(this)

        // Register a stop callback so if the user revokes consent from the
        // system overlay, we tear down cleanly.
        proj.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                Log.d(TAG, "MediaProjection.onStop")
                pushEvent("onScreenCaptureStopped", emptyMap<String, Any?>())
                stopCapture()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }, mainHandler)

        startCapture()
        pushEvent("onScreenCaptureStarted", mapOf(
            "intervalMs" to intervalMs,
            "jpegQuality" to jpegQuality,
            "maxDimension" to maxDimension,
        ))
    }

    @Suppress("DEPRECATION")
    private fun startCapture() {
        val proj = projection ?: return

        val (w, h, density) = computeCaptureSize()
        Log.d(TAG, "starting capture ${w}x${h} @ ${intervalMs}ms")

        captureThread = HandlerThread("BrutusScreenCapture").also { it.start() }
        captureHandler = Handler(captureThread!!.looper)

        val reader = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2)
        imageReader = reader

        // Drop frames faster than the requested interval. We still need to
        // acquire+close them so the buffer doesn't stall.
        reader.setOnImageAvailableListener({ r ->
            val now = System.currentTimeMillis()
            val image = try { r.acquireLatestImage() } catch (_: Throwable) { null }
            if (image == null) return@setOnImageAvailableListener
            try {
                if (emittingFrame) return@setOnImageAvailableListener
                if (now - lastEmittedAt < intervalMs) return@setOnImageAvailableListener
                emittingFrame = true
                lastEmittedAt = now
                processImage(image)
            } finally {
                try { image.close() } catch (_: Throwable) {}
                emittingFrame = false
            }
        }, captureHandler)

        try {
            virtualDisplay = proj.createVirtualDisplay(
                "BrutusScreenCapture",
                w, h, density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface,
                null,
                captureHandler,
            )
        } catch (t: Throwable) {
            Log.e(TAG, "createVirtualDisplay failed", t)
            stopCapture()
            stopSelf()
        }
    }

    /**
     * Read pixels from [image] (RGBA_8888 with row-stride padding), turn
     * them into a Bitmap, JPEG-encode, base64. Push to Flutter on the
     * main thread (MethodChannel rules).
     */
    private fun processImage(image: Image) {
        try {
            val plane = image.planes[0]
            val buffer: ByteBuffer = plane.buffer
            val pixelStride = plane.pixelStride
            val rowStride = plane.rowStride
            // Snapshot dimensions up-front. The posted main-thread lambda
            // below runs *after* this method's `finally { image.close() }`
            // (see startCapture), so reading image.width/height there throws
            // "Image is already closed" and crashes the process.
            val imgWidth = image.width
            val imgHeight = image.height
            val rowPadding = rowStride - pixelStride * imgWidth
            val bmp = Bitmap.createBitmap(
                imgWidth + rowPadding / pixelStride,
                imgHeight,
                Bitmap.Config.ARGB_8888,
            )
            try {
                bmp.copyPixelsFromBuffer(buffer)
                val cropped = if (rowPadding == 0) bmp else
                    Bitmap.createBitmap(bmp, 0, 0, imgWidth, imgHeight)
                try {
                    val out = ByteArrayOutputStream(64 * 1024)
                    cropped.compress(Bitmap.CompressFormat.JPEG, jpegQuality, out)
                    val jpegBytes = out.toByteArray()
                    val b64 = Base64.encodeToString(jpegBytes, Base64.NO_WRAP)

                    mainHandler.post {
                        pushEvent("onScreenCaptureFrame", mapOf(
                            "data" to b64,
                            "width" to imgWidth,
                            "height" to imgHeight,
                            "bytes" to jpegBytes.size,
                        ))
                    }
                } finally {
                    if (cropped !== bmp) cropped.recycle()
                }
            } finally {
                bmp.recycle()
            }
        } catch (t: Throwable) {
            Log.w(TAG, "processImage failed: ${t.message}")
        }
    }

    @Suppress("DEPRECATION")
    private fun computeCaptureSize(): Triple<Int, Int, Int> {
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        wm.defaultDisplay.getRealMetrics(metrics)
        val w = metrics.widthPixels
        val h = metrics.heightPixels
        val density = metrics.densityDpi
        // Downscale so the longer edge isn't bigger than maxDimension.
        // Aspect is preserved.
        val longer = maxOf(w, h)
        if (longer <= maxDimension) {
            return Triple(w, h, density)
        }
        val scale = maxDimension.toFloat() / longer
        val sw = (w * scale).toInt().coerceAtLeast(2) and 0xFFFFFFFE.toInt()
        val sh = (h * scale).toInt().coerceAtLeast(2) and 0xFFFFFFFE.toInt()
        return Triple(sw, sh, density)
    }

    private fun stopCapture() {
        try { virtualDisplay?.release() } catch (_: Throwable) {}
        virtualDisplay = null
        try { imageReader?.close() } catch (_: Throwable) {}
        imageReader = null
        try { projection?.stop() } catch (_: Throwable) {}
        projection = null
        try { captureThread?.quitSafely() } catch (_: Throwable) {}
        captureThread = null
        captureHandler = null
        instance.compareAndSet(this, null)
    }

    override fun onDestroy() {
        stopCapture()
        super.onDestroy()
    }

    private fun pushEvent(method: String, payload: Map<String, Any?>) {
        try {
            eventSink?.invokeMethod(method, payload)
        } catch (t: Throwable) {
            Log.w(TAG, "pushEvent($method) failed: ${t.message}")
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(NOTIF_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            NOTIF_CHANNEL_ID,
            "Brutus screen sharing",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Active while Brutus is sharing your screen."
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val stopIntent = Intent(this, ScreenCaptureService::class.java)
            .setAction(ACTION_STOP)
        val stopPi = android.app.PendingIntent.getService(
            this, 1, stopIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                android.app.PendingIntent.FLAG_IMMUTABLE,
        )
        // Use a guaranteed-present system icon. `ic_menu_view` and friends are
        // not present on every OEM build (Samsung removed several mdpi
        // assets), and a missing-icon notification crashes startForeground
        // with a NullPointerException inside Notification.Builder.
        val iconRes = applicationInfo.icon.takeIf { it != 0 }
            ?: android.R.drawable.stat_sys_data_bluetooth
        return NotificationCompat.Builder(this, NOTIF_CHANNEL_ID)
            .setSmallIcon(iconRes)
            .setContentTitle("Brutus is sharing your screen")
            .setContentText("Tap to stop")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(stopPi)
            .addAction(0, "Stop", stopPi)
            .build()
    }

    private fun foregroundType(): Int {
        return if (Build.VERSION.SDK_INT >= 29) {
            // mediaProjection | microphone — keeps the mic alive when the
            // user backgrounds the app to interact with other apps while
            // sharing their screen. Without the microphone bit, Android 14+
            // silences mic input as soon as our process loses foreground.
            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        } else {
            0
        }
    }
}
