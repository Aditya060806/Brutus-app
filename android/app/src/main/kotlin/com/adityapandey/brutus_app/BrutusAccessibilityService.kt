package com.adityapandey.brutus_app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.content.ClipData
import android.content.ClipboardManager
import android.graphics.Path
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.util.concurrent.atomic.AtomicReference

/**
 * Brutus accessibility service — the device-wide automation primitive.
 *
 * Mirrors the desktop `ghost-control.ts` capabilities on Android:
 *
 *   • Ghost-typing:  [ghostType] (ACTION_SET_TEXT) + [pasteText] (clipboard)
 *   • Gestures:      [tap], [swipe], [scroll]
 *   • Global:        BACK / HOME / RECENTS / NOTIFICATIONS / QUICK_SETTINGS
 *   • Smart click:   [clickByText] — finds a node whose text or content
 *                    description matches the voice command
 *   • WhatsApp auto-send (one-shot, post window-state-change)
 *
 * Privacy: this service does NOT read screen content unless the Flutter
 * side asks (via [readScreenText]). All other event handling is the
 * minimum required for the WhatsApp auto-send latch.
 */
class BrutusAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "BrutusAccessibility"

        private val instance = AtomicReference<BrutusAccessibilityService?>(null)
        fun current(): BrutusAccessibilityService? = instance.get()
        fun isRunning(): Boolean = instance.get() != null
    }

    @Volatile private var pendingWhatsAppSend: Boolean = false
    @Volatile private var pendingWhatsAppDeadline: Long = 0L

    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance.set(this)
        Log.d(TAG, "service connected")
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        Log.d(TAG, "service unbound")
        instance.compareAndSet(this, null)
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance.compareAndSet(this, null)
        super.onDestroy()
    }

    override fun onInterrupt() { /* no-op */ }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (!pendingWhatsAppSend) return

        // Bail if the deadline has elapsed (defence in depth — the timer
        // also disarms but a stale event could arrive in-between).
        if (System.currentTimeMillis() > pendingWhatsAppDeadline) {
            pendingWhatsAppSend = false
            return
        }

        val pkg = event.packageName?.toString() ?: return
        if (pkg != "com.whatsapp" && pkg != "com.whatsapp.w4b") return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event.eventType != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
        ) return

        val root = rootInActiveWindow ?: return
        val send = findSendButton(root) ?: return

        // The send button can briefly mount disabled while WhatsApp animates
        // the chat in. Skip until it's actually clickable to avoid eating
        // the click on a stub.
        if (!send.isEnabled || !send.isClickable) return

        Log.d(TAG, "WhatsApp send button ready — clicking")
        val ok = send.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        if (ok) {
            pendingWhatsAppSend = false
        }
    }

    private fun findSendButton(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val byId = root.findAccessibilityNodeInfosByViewId("com.whatsapp:id/send")
        if (byId.isNotEmpty()) return byId.first()
        val byIdBiz = root.findAccessibilityNodeInfosByViewId("com.whatsapp.w4b:id/send")
        if (byIdBiz.isNotEmpty()) return byIdBiz.first()
        return findByContentDescription(root, "Send")
    }

    private fun findByContentDescription(
        node: AccessibilityNodeInfo,
        desc: String,
    ): AccessibilityNodeInfo? {
        val cd = node.contentDescription?.toString() ?: ""
        if (cd.equals(desc, ignoreCase = true) && node.isClickable) return node
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val hit = findByContentDescription(child, desc)
            if (hit != null) return hit
        }
        return null
    }

    // ── Public API used by the method channel ──────────────────────────────

    /** Type [text] into the currently focused editable. Returns true on success. */
    fun ghostType(text: String): Boolean {
        val focus = findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        val args = Bundle().apply {
            putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                text,
            )
        }
        return focus.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    /**
     * Paste [text] via the system clipboard. Useful when [ghostType] won't
     * work (e.g. WebView fields that ignore ACTION_SET_TEXT). Always succeeds
     * because the heavy lifting is the clipboard write — the actual paste
     * has to be triggered by Ctrl+V, which we expose as a separate primitive.
     */
    fun pasteText(text: String): Boolean {
        return try {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            cm.setPrimaryClip(ClipData.newPlainText("brutus", text))
            // Try to actually paste into the focused field.
            val focus = findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            focus?.performAction(AccessibilityNodeInfo.ACTION_PASTE)
            true
        } catch (t: Throwable) {
            Log.w(TAG, "pasteText failed: ${t.message}")
            false
        }
    }

    /** Trigger one of [AccessibilityService.GLOBAL_ACTION_BACK] etc. */
    fun globalAction(action: Int): Boolean = performGlobalAction(action)

    /** Single-finger tap at absolute screen coords. */
    fun tap(x: Float, y: Float): Boolean {
        if (x < 0 || y < 0) return false
        val path = Path().apply { moveTo(x, y) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 60))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    /** Single-finger swipe from (x1,y1) → (x2,y2) over [durationMs] ms. */
    fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long): Boolean {
        val path = Path().apply {
            moveTo(x1, y1)
            lineTo(x2, y2)
        }
        val gesture = GestureDescription.Builder()
            .addStroke(
                GestureDescription.StrokeDescription(
                    path, 0, durationMs.coerceAtLeast(40).coerceAtMost(2000)
                )
            )
            .build()
        return dispatchGesture(gesture, null, null)
    }

    /**
     * Scroll the active window. Best-effort: tries ACTION_SCROLL_FORWARD or
     * BACKWARD on the first scrollable node it finds. Falls back to a swipe
     * gesture in the centre of the screen.
     */
    fun scroll(direction: String): Boolean {
        val root = rootInActiveWindow
        val target = root?.let { findScrollable(it) }
        val action = if (direction == "up") {
            AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
        } else {
            AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
        }
        if (target?.performAction(action) == true) return true

        // Fallback: gesture swipe.
        val dm = resources.displayMetrics
        val cx = dm.widthPixels / 2f
        val midY = dm.heightPixels / 2f
        val (y1, y2) = if (direction == "up") cx to (cx + midY * 0.7f)
            else (cx + midY * 0.7f) to cx
        return swipe(cx, y1, cx, y2, 300)
    }

    private fun findScrollable(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isScrollable) return node
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val hit = findScrollable(child)
            if (hit != null) return hit
        }
        return null
    }

    /**
     * Click the first node whose visible text or content description matches
     * [query] (case-insensitive substring). Used for "tap the send button"
     * style voice commands.
     */
    fun clickByText(query: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val q = query.trim().lowercase()
        val hit = findClickable(root, q) ?: return false
        return hit.performAction(AccessibilityNodeInfo.ACTION_CLICK)
    }

    private fun findClickable(
        node: AccessibilityNodeInfo,
        q: String,
    ): AccessibilityNodeInfo? {
        val txt = node.text?.toString()?.lowercase() ?: ""
        val cd = node.contentDescription?.toString()?.lowercase() ?: ""
        if ((txt.contains(q) || cd.contains(q)) && node.isClickable) return node
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val hit = findClickable(child, q)
            if (hit != null) return hit
        }
        // Try ancestor lookup if a non-clickable text matched but its parent
        // is clickable (common pattern for List rows).
        if (txt.contains(q) || cd.contains(q)) {
            var p: AccessibilityNodeInfo? = node.parent
            var depth = 0
            while (p != null && depth < 4) {
                if (p.isClickable) return p
                p = p.parent
                depth++
            }
        }
        return null
    }

    /**
     * Read every visible text node under the active window. Returns a
     * concatenated, trimmed string, with newlines between siblings.
     * For voice "what's on the screen" type questions.
     */
    fun readScreenText(): String {
        val root = rootInActiveWindow ?: return ""
        val sb = StringBuilder()
        collectText(root, sb)
        return sb.toString().trim()
    }

    private fun collectText(node: AccessibilityNodeInfo, sb: StringBuilder) {
        val t = node.text?.toString()?.trim()
        if (!t.isNullOrEmpty()) {
            sb.append(t).append('\n')
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            collectText(child, sb)
        }
    }

    fun armWhatsAppAutoSend() {
        pendingWhatsAppSend = true
        // 12s deadline — gives WhatsApp time even on cold start with slow
        // device, but disarms cleanly so a delayed window event doesn't
        // misfire later.
        pendingWhatsAppDeadline = System.currentTimeMillis() + 12_000L
        mainHandler.postDelayed({ pendingWhatsAppSend = false }, 12_000L)
    }
}
