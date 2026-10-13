package io.openim.messaging

import android.content.Intent
import androidx.core.app.RemoteInput
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.openim.MainActivity
import org.json.JSONObject

/** Activity-local UI/settings bridge. It does not own the SDK or notification receiver. */
class NativeNotificationBridge(private val activity: MainActivity, engine: FlutterEngine) {
    private val notifications = NativeMessageNotifications.get(activity)
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "openim_native_im")
    private val pending = ArrayDeque<Map<String, Any?>>()
    private var listening = false
    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "initialize" -> { result.success(true) }
                    "readyForActions" -> { listening = true; result.success(null); drain() }
                    "configure" -> {
                        notifications.configure(JSONObject(call.arguments as Map<*, *>))
                        IMService.startIfAllowed(activity)
                        result.success(null)
                    }
                    "clear" -> { notifications.clear(call.argument<String>("sessionKey")); result.success(null) }
                    "cancel" -> { notifications.cancel(call.argument<Int>("id")!!); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("native_notification_error", error.javaClass.simpleName, null)
            }
        }
        onIntent(activity.intent)
    }
    fun onIntent(intent: Intent?) {
        val payload = intent?.getStringExtra(NativeMessageNotifications.PAYLOAD) ?: return
        if (payload.length > 8192) return
        if (pending.size >= 32) pending.removeFirst()
        pending.addLast(mapOf("payload" to payload,
            "actionId" to intent.getStringExtra(NativeMessageNotifications.ACTION),
            "input" to RemoteInput.getResultsFromIntent(intent)?.getCharSequence(NativeMessageNotifications.REPLY)?.toString(),
            "id" to intent.getIntExtra(NativeMessageNotifications.ID, 0)))
        intent.removeExtra(NativeMessageNotifications.PAYLOAD)
        drain()
    }
    private fun drain() { while (listening && pending.isNotEmpty()) channel.invokeMethod("notificationAction", pending.removeFirst()) }
    fun dispose() { listening = false; channel.setMethodCallHandler(null) }
}
