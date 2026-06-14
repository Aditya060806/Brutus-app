package com.adityapandey.brutus_app

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicReference

/**
 * Brutus notification listener.
 *
 * Lets the user grant Brutus access to read posted notifications via
 * Settings → Notifications → Notification access. Once granted, this
 * service mirrors each posted notification across the [PhoneAutomationChannel]
 * stream so Flutter can display "what just buzzed" or speak it aloud.
 *
 * Edge case: this service can be killed and recreated by the OS at any
 * time. We re-bind the static reference on every onListenerConnected.
 */
class BrutusNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "BrutusNotifListener"
        // Method channel for Flutter to drive (read all, dismiss, etc.).
        // The channel sink is set by MainActivity once Flutter is up.
        @Volatile var eventSink: MethodChannel? = null
        private val instance = AtomicReference<BrutusNotificationListenerService?>(null)
        fun current(): BrutusNotificationListenerService? = instance.get()
        fun isConnected(): Boolean = instance.get() != null
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance.set(this)
        Log.d(TAG, "connected")
    }

    override fun onListenerDisconnected() {
        instance.compareAndSet(this, null)
        Log.d(TAG, "disconnected")
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        try {
            val map = sbnToMap(sbn)
            // Push to Flutter on the main thread so MethodChannel.invokeMethod
            // is safe to call.
            android.os.Handler(mainLooper).post {
                eventSink?.invokeMethod("onNotificationPosted", map)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "post failed: ${t.message}")
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        android.os.Handler(mainLooper).post {
            eventSink?.invokeMethod(
                "onNotificationRemoved",
                mapOf("key" to sbn.key, "packageName" to sbn.packageName),
            )
        }
    }

    /** Snapshot of all currently posted notifications, used by the "list" call. */
    fun snapshot(): List<Map<String, Any?>> {
        val all = activeNotifications ?: return emptyList()
        return all.map { sbnToMap(it) }
    }

    fun dismissByKey(key: String): Boolean {
        return try {
            cancelNotification(key)
            true
        } catch (t: Throwable) {
            Log.w(TAG, "dismiss failed: ${t.message}")
            false
        }
    }

    private fun sbnToMap(sbn: StatusBarNotification): Map<String, Any?> {
        val n = sbn.notification
        val extras = n.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
        return mapOf(
            "key" to sbn.key,
            "id" to sbn.id,
            "packageName" to sbn.packageName,
            "postTime" to sbn.postTime,
            "title" to title,
            "text" to text,
            "bigText" to bigText,
            "isOngoing" to (n.flags and Notification.FLAG_ONGOING_EVENT != 0),
            "category" to n.category,
        )
    }
}
