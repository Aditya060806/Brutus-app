package com.adityapandey.brutus_app

import android.accessibilityservice.AccessibilityService
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import androidx.core.net.toUri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Brutus — Phone Automation method channel.
 *
 * Wires the Flutter `PhoneAutomationService` (Dart) to native Android APIs.
 *
 *   Permissions / UI deep-links:
 *     isAccessibilityEnabled, isNotificationListenerEnabled, canWriteSettings,
 *     openAccessibilitySettings, openNotificationListenerSettings,
 *     openWriteSettings, openAppSettings, openSettingsPanel
 *
 *   Hardware-ish:
 *     setTorch, setRingerMode, setMediaVolume, setBrightness
 *
 *   Apps:
 *     launchApp, playSpotifySong, playMusicSearch
 *
 *   Accessibility primitives (require BrutusAccessibilityService running):
 *     ghostType, pasteText, clickByText, globalAction, ghostTap, ghostSwipe,
 *     ghostScroll, ghostSequence, readScreenText, armWhatsAppAutoSend
 *
 *   Notification listener:
 *     listNotifications, dismissNotification
 *
 * Channel name: `com.adityapandey.brutus_app/phone_automation`.
 */
class PhoneAutomationChannel(
    private val activity: Activity,
    @Suppress("unused") private val channel: MethodChannel,
) {
    companion object {
        private const val TAG = "BrutusAutomation"
        private const val SPOTIFY_PKG = "com.spotify.music"
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {

                // ── Permission status ─────────────────────────────────────
                "isAccessibilityEnabled" -> result.success(isAccessibilityEnabled())
                "isNotificationListenerEnabled" -> result.success(isNotifListenerEnabled())
                "canWriteSettings" -> result.success(Settings.System.canWrite(activity))

                "openAccessibilitySettings" -> {
                    activity.startActivity(
                        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                }
                "openNotificationListenerSettings" -> {
                    activity.startActivity(
                        Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                }
                "openWriteSettings" -> {
                    activity.startActivity(
                        Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
                            .setData("package:${activity.packageName}".toUri())
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                }

                // ── Settings panels (modern WiFi/BT/Data toggles) ─────────
                "openSettingsPanel" -> {
                    val panel = call.argument<String>("panel") ?: ""
                    val action = when (panel) {
                        "wifi" -> if (Build.VERSION.SDK_INT >= 29)
                            Settings.Panel.ACTION_WIFI else Settings.ACTION_WIFI_SETTINGS
                        "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
                        "data" -> if (Build.VERSION.SDK_INT >= 29)
                            Settings.Panel.ACTION_INTERNET_CONNECTIVITY else Settings.ACTION_WIRELESS_SETTINGS
                        "internet" -> if (Build.VERSION.SDK_INT >= 29)
                            Settings.Panel.ACTION_INTERNET_CONNECTIVITY else Settings.ACTION_WIRELESS_SETTINGS
                        "volume" -> if (Build.VERSION.SDK_INT >= 29)
                            Settings.Panel.ACTION_VOLUME else Settings.ACTION_SOUND_SETTINGS
                        "nfc" -> "android.settings.NFC_SETTINGS"
                        "location" -> Settings.ACTION_LOCATION_SOURCE_SETTINGS
                        "airplane" -> Settings.ACTION_AIRPLANE_MODE_SETTINGS
                        else -> Settings.ACTION_SETTINGS
                    }
                    activity.startActivity(
                        Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                }

                // ── Flashlight ───────────────────────────────────────────
                "setTorch" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    result.success(setTorch(on))
                }

                // ── Ringer mode ──────────────────────────────────────────
                "setRingerMode" -> {
                    val mode = call.argument<String>("mode") ?: "normal"
                    val am = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    am.ringerMode = when (mode) {
                        "silent" -> AudioManager.RINGER_MODE_SILENT
                        "vibrate" -> AudioManager.RINGER_MODE_VIBRATE
                        else -> AudioManager.RINGER_MODE_NORMAL
                    }
                    result.success(true)
                }

                // ── Bluetooth audio detection ───────────────────────────
                "isBluetoothAudioConnected" -> {
                    val am = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    @Suppress("DEPRECATION")
                    val scoOn = am.isBluetoothScoOn
                    @Suppress("DEPRECATION")
                    val a2dpOn = am.isBluetoothA2dpOn
                    result.success(scoOn || a2dpOn)
                }

                // ── Volume ───────────────────────────────────────────────
                "setMediaVolume" -> {
                    val value = (call.argument<Number>("value")?.toFloat() ?: 0.5f)
                        .coerceIn(0f, 1f)
                    val am = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    val target = (value * max).toInt()
                    am.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
                    result.success(true)
                }

                // ── Screen brightness (requires WRITE_SETTINGS) ──────────
                "setBrightness" -> {
                    if (!Settings.System.canWrite(activity)) {
                        result.error("NO_PERMISSION",
                            "Grant 'Modify system settings' for Brutus first.", null)
                        return
                    }
                    val value = (call.argument<Number>("value")?.toFloat() ?: 0.5f)
                        .coerceIn(0f, 1f)
                    val brightness = (value * 255).toInt().coerceIn(0, 255)
                    Settings.System.putInt(
                        activity.contentResolver,
                        Settings.System.SCREEN_BRIGHTNESS_MODE,
                        Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL,
                    )
                    Settings.System.putInt(
                        activity.contentResolver,
                        Settings.System.SCREEN_BRIGHTNESS,
                        brightness,
                    )
                    result.success(true)
                }

                // ── Apps ─────────────────────────────────────────────────
                "launchApp" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    if (pkg.isEmpty()) {
                        result.error("BAD_ARGS", "packageName required", null)
                        return
                    }
                    val intent = activity.packageManager.getLaunchIntentForPackage(pkg)
                    if (intent == null) {
                        result.error("NOT_FOUND", "App not installed: $pkg", null)
                        return
                    }
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    activity.startActivity(intent)
                    result.success(true)
                }

                "openAppSettings" -> {
                    val pkg = call.argument<String>("packageName") ?: activity.packageName
                    activity.startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                            .setData("package:$pkg".toUri())
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                }

                /**
                 * Direct-play a song on Spotify using the system "play from
                 * search" intent. This is the same intent that powers Google
                 * Assistant's "play X on Spotify" — Spotify handles it
                 * natively, no UI fiddling, no SDK registration required.
                 *
                 * If Spotify isn't installed, falls through to the deep link
                 * handler in Dart (which opens the web player).
                 */
                "playSpotifySong" -> {
                    val query = call.argument<String>("query") ?: ""
                    if (query.isEmpty()) {
                        result.error("BAD_ARGS", "query required", null)
                        return
                    }
                    val ok = playMusicViaSearch(query, SPOTIFY_PKG)
                    result.success(ok)
                }

                /**
                 * Same as [playSpotifySong] but doesn't pin the package — the
                 * system music chooser picks the user's default. Useful for
                 * "play X" when the user hasn't said where.
                 */
                "playMusicSearch" -> {
                    val query = call.argument<String>("query") ?: ""
                    if (query.isEmpty()) {
                        result.error("BAD_ARGS", "query required", null)
                        return
                    }
                    val ok = playMusicViaSearch(query, null)
                    result.success(ok)
                }

                // ── Accessibility-driven actions ─────────────────────────
                "ghostType" -> {
                    val text = call.argument<String>("text") ?: ""
                    val svc = BrutusAccessibilityService.current() ?: run {
                        result.error("NO_SERVICE",
                            "Enable Brutus accessibility service first.", null)
                        return
                    }
                    result.success(svc.ghostType(text))
                }
                "pasteText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val svc = BrutusAccessibilityService.current() ?: run {
                        result.error("NO_SERVICE",
                            "Enable Brutus accessibility service first.", null)
                        return
                    }
                    result.success(svc.pasteText(text))
                }
                "clickByText" -> {
                    val q = call.argument<String>("query") ?: ""
                    val svc = BrutusAccessibilityService.current() ?: run {
                        result.error("NO_SERVICE",
                            "Enable Brutus accessibility service first.", null)
                        return
                    }
                    result.success(svc.clickByText(q))
                }
                "ghostTap" -> {
                    val x = (call.argument<Number>("x") ?: 0f).toFloat()
                    val y = (call.argument<Number>("y") ?: 0f).toFloat()
                    val svc = BrutusAccessibilityService.current() ?: run {
                        result.error("NO_SERVICE",
                            "Enable Brutus accessibility service first.", null)
                        return
                    }
                    result.success(svc.tap(x, y))
                }
                "ghostSwipe" -> {
                    val x1 = (call.argument<Number>("x1") ?: 0f).toFloat()
                    val y1 = (call.argument<Number>("y1") ?: 0f).toFloat()
                    val x2 = (call.argument<Number>("x2") ?: 0f).toFloat()
                    val y2 = (call.argument<Number>("y2") ?: 0f).toFloat()
                    val ms = (call.argument<Number>("durationMs") ?: 300).toLong()
                    val svc = BrutusAccessibilityService.current() ?: run {
                        result.error("NO_SERVICE",
                            "Enable Brutus accessibility service first.", null)
                        return
                    }
                    result.success(svc.swipe(x1, y1, x2, y2, ms))
                }
                "ghostScroll" -> {
                    val direction = call.argument<String>("direction") ?: "down"
                    val svc = BrutusAccessibilityService.current() ?: run {
                        result.error("NO_SERVICE",
                            "Enable Brutus accessibility service first.", null)
                        return
                    }
                    result.success(svc.scroll(direction))
                }
                "readScreenText" -> {
                    val svc = BrutusAccessibilityService.current() ?: run {
                        result.error("NO_SERVICE",
                            "Enable Brutus accessibility service first.", null)
                        return
                    }
                    result.success(svc.readScreenText())
                }
                "ghostSequence" -> {
                    val actions = call.argument<List<Map<String, Any?>>>("actions")
                        ?: emptyList()
                    val svc = BrutusAccessibilityService.current() ?: run {
                        result.error("NO_SERVICE",
                            "Enable Brutus accessibility service first.", null)
                        return
                    }
                    runSequence(svc, actions, result)
                }
                "globalAction" -> {
                    val name = call.argument<String>("action") ?: ""
                    val code = when (name) {
                        "back" -> AccessibilityService.GLOBAL_ACTION_BACK
                        "home" -> AccessibilityService.GLOBAL_ACTION_HOME
                        "recents" -> AccessibilityService.GLOBAL_ACTION_RECENTS
                        "notifications" -> AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS
                        "quickSettings" -> AccessibilityService.GLOBAL_ACTION_QUICK_SETTINGS
                        "powerDialog" -> AccessibilityService.GLOBAL_ACTION_POWER_DIALOG
                        else -> -1
                    }
                    if (code < 0) {
                        result.error("BAD_ARGS", "Unknown action: $name", null)
                        return
                    }
                    val svc = BrutusAccessibilityService.current() ?: run {
                        result.error("NO_SERVICE",
                            "Enable Brutus accessibility service first.", null)
                        return
                    }
                    result.success(svc.globalAction(code))
                }
                "armWhatsAppAutoSend" -> {
                    val svc = BrutusAccessibilityService.current() ?: run {
                        result.error("NO_SERVICE",
                            "Enable Brutus accessibility service first.", null)
                        return
                    }
                    svc.armWhatsAppAutoSend()
                    result.success(true)
                }

                // ── Direct call (CALL_PHONE) ──────────────────────────────
                "placeCall" -> {
                    val phone = call.argument<String>("phone") ?: ""
                    if (phone.isEmpty()) {
                        result.error("BAD_ARGS", "phone required", null)
                        return
                    }
                    val ok = placeCall(phone)
                    result.success(ok)
                }

                // ── Notification listener queries ────────────────────────
                "listNotifications" -> {
                    val svc = BrutusNotificationListenerService.current()
                    if (svc == null) {
                        result.success(emptyList<Map<String, Any?>>())
                    } else {
                        result.success(svc.snapshot())
                    }
                }
                "dismissNotification" -> {
                    val key = call.argument<String>("key") ?: ""
                    val svc = BrutusNotificationListenerService.current() ?: run {
                        result.error("NO_SERVICE",
                            "Enable notification access for Brutus first.", null)
                        return
                    }
                    result.success(svc.dismissByKey(key))
                }

                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            Log.e(TAG, "channel call '${call.method}' failed", t)
            result.error("EXCEPTION", t.message ?: t.javaClass.simpleName, null)
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private fun isAccessibilityEnabled(): Boolean {
        val expectedComponent = ComponentName(activity, BrutusAccessibilityService::class.java)
        val flat = Settings.Secure.getString(
            activity.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        if (flat.isEmpty()) return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(flat)
        for (item in splitter) {
            val cn = ComponentName.unflattenFromString(item)
            if (cn != null && cn == expectedComponent) return true
        }
        return false
    }

    private fun isNotifListenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(
            activity.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        if (flat.isEmpty()) return false
        val pkg = activity.packageName
        return flat.split(":").any { it.startsWith("$pkg/") }
    }

    private fun setTorch(on: Boolean): Boolean {
        return try {
            val cm = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val rearId = cm.cameraIdList.firstOrNull { id ->
                cm.getCameraCharacteristics(id)
                    .get(android.hardware.camera2.CameraCharacteristics.FLASH_INFO_AVAILABLE) == true &&
                    cm.getCameraCharacteristics(id)
                    .get(android.hardware.camera2.CameraCharacteristics.LENS_FACING) ==
                        android.hardware.camera2.CameraCharacteristics.LENS_FACING_BACK
            } ?: cm.cameraIdList.firstOrNull() ?: return false
            cm.setTorchMode(rearId, on)
            true
        } catch (t: Throwable) {
            Log.w(TAG, "torch failed: ${t.message}")
            false
        }
    }

    /**
     * Place a direct call. Requires CALL_PHONE runtime permission. Returns
     * false if the permission isn't granted; the Dart side falls back to
     * the dialer in that case.
     */
    private fun placeCall(phone: String): Boolean {
        val granted = activity.checkSelfPermission(
            android.Manifest.permission.CALL_PHONE
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!granted) {
            Log.w(TAG, "CALL_PHONE not granted")
            return false
        }
        return try {
            val intent = Intent(Intent.ACTION_CALL).apply {
                data = "tel:$phone".toUri()
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
            true
        } catch (t: Throwable) {
            Log.w(TAG, "placeCall failed: ${t.message}")
            false
        }
    }

    /**
     * Use the system "play from search" intent. Spotify, YouTube Music,
     * and Google Play Music all handle this. The intent contract is part
     * of the public Android contract (`MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH`).
     *
     * Strategy:
     *   1. Fire MEDIA_PLAY_FROM_SEARCH pinned to Spotify. Some Spotify
     *      builds register this on a non-launcher activity, so we also
     *      pre-launch the package to ensure the process is alive.
     *   2. If pinning fails (no resolver / OEM weirdness), fire the same
     *      intent unpinned and let the system music picker route it.
     *   3. As a last resort, just open Spotify's launcher activity.
     */
    private fun playMusicViaSearch(query: String, pinPackage: String?): Boolean {
        return try {
            // 1. Prime the Spotify process so the intent receiver is awake.
            //    This avoids a known Spotify cold-start bug where the first
            //    MEDIA_PLAY_FROM_SEARCH while the app is killed silently
            //    drops on the floor instead of starting playback.
            if (pinPackage != null) {
                val launch = activity.packageManager.getLaunchIntentForPackage(pinPackage)
                if (launch != null) {
                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    activity.startActivity(launch)
                }
            }

            val intent = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH).apply {
                putExtra(MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/*")
                putExtra(android.app.SearchManager.QUERY, query)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (pinPackage != null) setPackage(pinPackage)
            }
            val resolved = activity.packageManager.resolveActivity(intent, 0)
            if (resolved != null) {
                // 2. Slight delay so Spotify's intent receiver registers
                //    after the launcher intent above. ~700ms is a reliable
                //    minimum on real Android 14 devices.
                mainHandler.postDelayed({
                    try {
                        activity.startActivity(intent)
                    } catch (t: Throwable) {
                        Log.w(TAG, "delayed playMusicViaSearch failed: ${t.message}")
                    }
                }, 700L)
                return true
            }

            // 3. Nothing pinned resolved — try unpinned (system picker).
            intent.setPackage(null)
            val unpinned = activity.packageManager.resolveActivity(intent, 0)
            if (unpinned != null) {
                activity.startActivity(intent)
                return true
            }

            // 4. Absolute fallback — Spotify is launched (already done above)
            //    but there's no play handler. Reach the Dart side's deep-link
            //    path for the search URL.
            false
        } catch (t: Throwable) {
            Log.w(TAG, "playMusicViaSearch failed: ${t.message}")
            false
        }
    }

    /**
     * Run a list of accessibility actions sequentially. Each action is a map
     * with `type` plus type-specific params. Mirrors the desktop
     * `ghost-sequence` handler:
     *   { type: "wait", ms: 800 }
     *   { type: "type", text: "..." }
     *   { type: "paste", text: "..." }
     *   { type: "tap", x: 500, y: 1200 }
     *   { type: "swipe", x1, y1, x2, y2, durationMs }
     *   { type: "scroll", direction: "up" | "down" }
     *   { type: "click", query: "Send" }
     *   { type: "global", action: "back" | "home" | ... }
     */
    private fun runSequence(
        svc: BrutusAccessibilityService,
        actions: List<Map<String, Any?>>,
        result: MethodChannel.Result,
    ) {
        // Run on the main looper, posting waits as delayed callbacks so we
        // don't block the channel thread.
        val executed = mutableListOf<Boolean>()
        val total = actions.size

        fun finish() {
            val ok = executed.all { it }
            mainHandler.post {
                result.success(mapOf("success" to ok, "completed" to executed.size, "total" to total))
            }
        }

        fun runAt(i: Int) {
            if (i >= total) {
                finish(); return
            }
            val action = actions[i]
            val type = (action["type"] as? String)?.lowercase() ?: ""
            try {
                when (type) {
                    "wait" -> {
                        val ms = (action["ms"] as? Number)?.toLong() ?: 250L
                        executed.add(true)
                        mainHandler.postDelayed({ runAt(i + 1) }, ms.coerceIn(0, 5000))
                        return
                    }
                    "type" -> {
                        val text = action["text"] as? String ?: ""
                        executed.add(svc.ghostType(text))
                    }
                    "paste" -> {
                        val text = action["text"] as? String ?: ""
                        executed.add(svc.pasteText(text))
                    }
                    "tap" -> {
                        val x = (action["x"] as? Number)?.toFloat() ?: 0f
                        val y = (action["y"] as? Number)?.toFloat() ?: 0f
                        executed.add(svc.tap(x, y))
                    }
                    "swipe" -> {
                        val x1 = (action["x1"] as? Number)?.toFloat() ?: 0f
                        val y1 = (action["y1"] as? Number)?.toFloat() ?: 0f
                        val x2 = (action["x2"] as? Number)?.toFloat() ?: 0f
                        val y2 = (action["y2"] as? Number)?.toFloat() ?: 0f
                        val ms = (action["durationMs"] as? Number)?.toLong() ?: 300L
                        executed.add(svc.swipe(x1, y1, x2, y2, ms))
                    }
                    "scroll" -> {
                        val dir = action["direction"] as? String ?: "down"
                        executed.add(svc.scroll(dir))
                    }
                    "click" -> {
                        val q = action["query"] as? String ?: ""
                        executed.add(svc.clickByText(q))
                    }
                    "global" -> {
                        val name = action["action"] as? String ?: ""
                        val code = when (name) {
                            "back" -> AccessibilityService.GLOBAL_ACTION_BACK
                            "home" -> AccessibilityService.GLOBAL_ACTION_HOME
                            "recents" -> AccessibilityService.GLOBAL_ACTION_RECENTS
                            "notifications" -> AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS
                            "quickSettings" -> AccessibilityService.GLOBAL_ACTION_QUICK_SETTINGS
                            "powerDialog" -> AccessibilityService.GLOBAL_ACTION_POWER_DIALOG
                            else -> -1
                        }
                        executed.add(if (code >= 0) svc.globalAction(code) else false)
                    }
                    else -> executed.add(false)
                }
            } catch (t: Throwable) {
                Log.w(TAG, "sequence step '$type' failed", t)
                executed.add(false)
            }
            // Default 80ms gap between actions to give the UI thread a beat.
            mainHandler.postDelayed({ runAt(i + 1) }, 80)
        }

        runAt(0)
    }
}
