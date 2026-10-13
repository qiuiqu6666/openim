package io.openim.messaging

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput
import io.openim.MainActivity
import io.openim.flutter_openim_sdk.runtime.NativeIMRuntime
import open_im_sdk_callback.Base
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** One process-owned notification consumer. No Flutter or Activity reference is retained. */
class NativeMessageNotifications private constructor(private val context: Context) : NativeIMRuntime.EventSink {
    companion object {
        private var instance: NativeMessageNotifications? = null
        @JvmStatic @Synchronized fun get(context: Context): NativeMessageNotifications =
            instance ?: NativeMessageNotifications(context.applicationContext).also { instance = it }
        const val PAYLOAD = "99chat.native.notification.payload"
        const val ACTION = "99chat.native.notification.action"
        const val REPLY = "99chat.native.notification.reply"
        const val ID = "99chat.native.notification.id"
    }
    private val main = Handler(Looper.getMainLooper())
    private val core = NativeIMRuntime.get()
    private val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private val store = context.getSharedPreferences("native_im_notifications_v1", Context.MODE_PRIVATE)
    private var configuration = JSONObject()
    private var account = ""
    private var session = ""
    private var activeConversation = ""
    private var suppressed = false
    @Volatile private var epoch = 0L
    private var busy = false
    private var globalOption = 0
    private var metadataRevision = 0L
    private var conversationRevision = 0L
    private val conversations = linkedMapOf<String, Pair<Long, JSONObject>>()
    private var serial = 0L
    private val queue = linkedMapOf<String, JSONObject>()
    private val seen = linkedSetOf<String>()
    private val versions = linkedMapOf<Int, Long>()
    private var ringtone: Ringtone? = null
    private var lastAlert = 0L
    private val fallbackAvatar: Bitmap? by lazy {
        runCatching {
            context.assets.open("flutter_assets/assets/img/99chat_logo.png").use {
                BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = 4 })
            }
        }.getOrNull()
    }
    private val avatarCache = android.util.LruCache<String, Pair<Long, Bitmap>>(16)
    private val avatars = ThreadPoolExecutor(1, 1, 30, TimeUnit.SECONDS, ArrayBlockingQueue<Runnable>(16),
        ThreadPoolExecutor.DiscardPolicy()).apply { allowCoreThreadTimeOut(true) }
    init { core.attachApplication(context); core.addNativeSink(this) }

    fun configure(value: JSONObject) {
        val owner = value.optString("accountID")
        require(owner.isNotBlank() && owner == core.accountID()) { "Notification account does not own SDK" }
        val key = value.optString("sessionKey")
        require(key.isNotBlank()) { "Notification session is required" }
        val prefs = value.getJSONObject("preferences")
        // Clear stale preferences loaded by an older UI before accepting new policy.
        val changed = account != owner || session != key || configuration.toString() != prefs.toString()
        if (changed) { invalidate(); configuration = JSONObject(prefs.toString()) }
        account = owner; session = key
        activeConversation = value.optString("activeConversationID")
        suppressed = value.optBoolean("suppressSound")
        if (suppressed) ringtone?.stop()
        // Persist only display policy and localized labels, never login credentials.
        store.edit().putString(owner, configuration.toString()).apply()
        if (core.isForeground() && activeConversation.isNotEmpty()) cancel(NativeNotificationPolicy.id(owner, activeConversation))
    }
    fun clear(expectedSession: String?) {
        if (expectedSession != null && expectedSession != session) return
        invalidate(); seen.clear(); conversations.clear(); account = ""; session = ""; activeConversation = ""
        context.stopService(Intent(context, IMService::class.java))
    }
    fun cancel(id: Int) { versions.remove(id); manager.cancel(id) }
    private fun invalidate() {
        epoch++; queue.clear(); versions.clear(); ringtone?.stop()
        manager.activeNotifications.filter { it.notification.extras.getBoolean("99chat.native.message") }
            .forEach { manager.cancel(it.id) }
    }
    override fun onEvent(method: String, event: MutableMap<String, Any>?) {
        if (event == null) return
        val type = event["type"] as? String ?: return
        if (type == "onFlutterDetached") { activeConversation = ""; suppressed = false; return }
        if (type == "onSessionCleared") { clear(null); return }
        if (account.isEmpty() || account != core.accountID()) return
        if (method == "userListener" && type == "onSelfInfoUpdated") {
            metadataRevision++
            globalOption = NativeNotificationPolicy.objectValue(event["data"]).optInt("globalRecvMsgOpt")
            if (globalOption == 2) invalidate()
        }
        if (method == "conversationListener" && type in setOf("onConversationChanged", "onNewConversation")) {
            runCatching { org.json.JSONArray(event["data"].toString()) }.getOrNull()?.let { rows ->
                for (i in 0 until rows.length()) {
                    val row = rows.optJSONObject(i) ?: continue
                    conversations[row.optString("conversationID")] = (++conversationRevision) to row
                    if (conversations.size > 128) conversations.remove(conversations.keys.first())
                    if (row.optInt("recvMsgOpt") != 0 || row.optInt("unreadCount") == 0)
                        cancel(NativeNotificationPolicy.id(account, row.optString("conversationID")))
                }
            }
        }
        // Offline replay remains history compensation, not a burst of fresh alerts.
        if (method != "advancedMsgListener" || type != "onRecvNewMessage" || account.isEmpty() || account != core.accountID()) return
        val data = event["data"] as? Map<*, *> ?: return
        val raw = data["message"] as? String ?: return
        if (raw.length > 262144) { Log.w("NativeIMNotify", "Oversized notification preview omitted"); return }
        val message = runCatching { JSONObject(raw) }.getOrNull() ?: return
        val source = if (message.optInt("sessionType") == 1) message.optString("sendID") else message.optString("groupID")
        val identity = NativeNotificationPolicy.identity(message)
        if (source.isBlank() || identity.isBlank()) return
        val unique = "$session|$source|$identity"
        if (!seen.add(unique)) return
        if (seen.size > 512) seen.remove(seen.first())
        val key = "${message.optInt("sessionType")}|$source"
        if (queue.size >= 64 && !queue.containsKey(key)) {
            queue.remove(queue.keys.first()); Log.w("NativeIMNotify", "Notification queue coalesced at capacity")
        }
        queue[key] = message
        drain()
    }
    private fun drain() {
        if (busy || queue.isEmpty()) return
        val entry = queue.entries.first(); val message = entry.value; queue.remove(entry.key)
        val capturedEpoch = epoch
        val capturedMetadata = metadataRevision
        val capturedConversation = conversationRevision
        val owner = account
        if (owner.isEmpty() || owner != core.accountID()) return
        busy = true
        fun finish() { busy = false; drain() }
        core.readSelf(object : Base {
            override fun onError(code: Int, error: String?) { main.post { Log.w("NativeIMNotify", "Self lookup failed code=$code"); finish() } }
            override fun onSuccess(value: String?) { main.post {
                if (epoch != capturedEpoch || account != owner || core.accountID() != owner) { finish(); return@post }
                globalOption = NativeNotificationPolicy.objectValue(value).optInt("globalRecvMsgOpt")
                val type = message.optInt("sessionType")
                val source = if (type == 1) message.optString("sendID") else message.optString("groupID")
                core.readConversation(type, source, object : Base {
                    override fun onError(code: Int, error: String?) { main.post { Log.w("NativeIMNotify", "Conversation lookup failed code=$code"); finish() } }
                    override fun onSuccess(value: String?) { main.post {
                        try {
                            if (epoch == capturedEpoch && account == owner && core.accountID() == owner && capturedMetadata == metadataRevision) {
                                val queried = NativeNotificationPolicy.objectValue(value)
                                val update = conversations[queried.optString("conversationID")]
                                present(message, if (update != null && update.first > capturedConversation) update.second else queried)
                            }
                        } catch (error: RuntimeException) { Log.w("NativeIMNotify", "Notification unavailable: ${error.javaClass.simpleName}") }
                        finally { finish() }
                    } }
                })
            } }
        })
    }
    private fun present(message: JSONObject, conversation: JSONObject) {
        if (!NativeNotificationPolicy.eligible(message, conversation, account, globalOption)) return
        val foreground = core.isForeground() && core.hasFlutter()
        val prefs = NativeNotificationPolicy.objectValue(store.getString(account, configuration.toString()))
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val quiet = suppressed || audio.mode != AudioManager.MODE_NORMAL
        if (foreground && !quiet) foregroundAlert(prefs)
        val cid = conversation.optString("conversationID")
        val preview = NativeNotificationPolicy.preview(prefs, foreground, activeConversation, cid) ?: return
        val labels = prefs.optJSONObject("labels") ?: JSONObject()
        val generic = labels.optString("offlineMessage", "你收到了一条新消息")
        val group = message.optInt("sessionType") != 1 && preview != "none"
        val sender = if (preview == "none") "" else NativeNotificationPolicy.line(message.optString("senderNickname"))
        val title = if (preview == "none") generic else NativeNotificationPolicy.line(conversation.optString("showName"))
            .ifEmpty { if (group) labels.optString("groupChat", "群聊") else sender.ifEmpty { generic } }
        val body = if (preview == "detail" && !NativeNotificationPolicy.privateMessage(message, conversation))
            NativeMessagePreview.text(message, labels) else generic
        val id = NativeNotificationPolicy.id(account, cid)
        val version = ++serial
        versions[id] = version
        if (versions.size > 128) { val oldest = versions.keys.first(); cancel(oldest) }
        val target = JSONObject().put("version", 1).put("accountID", account).put("sessionKey", session)
            .put("conversationID", cid).put("sessionType", message.optInt("sessionType"))
            .put("sourceID", if (message.optInt("sessionType") == 1) message.optString("sendID") else message.optString("groupID"))
            .put("messageID", message.optString("clientMsgID").ifEmpty { message.optLong("seq").toString() })
        val sound = !foreground && !quiet
        val vibration = !foreground && !quiet
        val soundID = soundID(prefs)
        val channel = if (sound) "chat_messages_v2_${soundID}_v${if (vibration) 1 else 0}" else "chat_messages_v2_silent_v${if (vibration) 1 else 0}"
        val resource = context.resources.getIdentifier("chat_message_$soundID", "raw", context.packageName)
        val soundUri = Uri.parse("android.resource://${context.packageName}/$resource")
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(channel, "Chat messages", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "New chat messages and quick replies"
            enableVibration(vibration)
            setSound(if (sound) soundUri else null, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build())
        })
        fun intent(action: String): PendingIntent {
            val launch = Intent(context, MainActivity::class.java).setAction("99chat.message.$action")
                .setData(Uri.parse("chat99://message/$id/$version/$action"))
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(PAYLOAD, target.toString()).putExtra(ACTION, action).putExtra(ID, id)
            val mutable = if (action == "reply" && Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else if (action != "reply") PendingIntent.FLAG_IMMUTABLE else 0
            return PendingIntent.getActivity(context, id, launch, PendingIntent.FLAG_UPDATE_CURRENT or mutable)
        }
        val icon = context.applicationInfo.icon
        val builder = NotificationCompat.Builder(context, channel).setSmallIcon(icon).setContentTitle(title)
            .setContentText(NativeNotificationPolicy.line(body))
            .setCategory(NotificationCompat.CATEGORY_MESSAGE).setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).setAutoCancel(true).setContentIntent(intent("open"))
            .setSound(if (sound) soundUri else null).setVibrate(if (vibration) longArrayOf(0, 200) else longArrayOf(0))
            .addExtras(Bundle().apply { putBoolean("99chat.native.message", true) })
        if (prefs.optBoolean("quickReply", true) && !NativeNotificationPolicy.official(conversation)) {
            val reply = labels.optString("reply", "回复")
            builder.addAction(NotificationCompat.Action.Builder(0, reply, intent("reply"))
                .addRemoteInput(RemoteInput.Builder(REPLY).setLabel(reply).build()).setAllowGeneratedReplies(true).build())
        }
        val deliveryEpoch = epoch
        fun show(avatar: Bitmap?, alert: Boolean) {
            if (epoch != deliveryEpoch || versions[id] != version || target.optString("sessionKey") != session || account != core.accountID()) return
            val nowForeground = core.isForeground() && core.hasFlutter()
            if (NativeNotificationPolicy.preview(configuration, nowForeground, activeConversation, cid) != preview) return
            if (nowForeground && activeConversation == cid) return
            if (avatar != null) builder.setLargeIcon(avatar)
            // Standard title/content template avoids an extra sender header on OEM heads-up banners.
            builder.setOnlyAlertOnce(!alert).setSilent(!alert)
            manager.notify(id, builder.build())
        }
        show(fallbackAvatar, true)
        val avatarURL = if (preview == "none") "" else conversation.optString("faceURL").ifEmpty { if (group) "" else message.optString("senderFaceUrl") }
        if (avatarURL.startsWith("https://") || avatarURL.startsWith("http://")) avatars.execute {
            if (epoch != deliveryEpoch) return@execute
            val now = android.os.SystemClock.elapsedRealtime()
            val cached = avatarCache.get(avatarURL)
            val avatar = if (cached != null && now - cached.first < 300000) cached.second else
                fetchAvatar(avatarURL)?.also { avatarCache.put(avatarURL, now to it) } ?: return@execute
            main.post { runCatching { show(avatar, false) } }
        }
    }
    private fun soundID(prefs: JSONObject): String = prefs.optString("messageSound", "preview000").takeIf {
        it in setOf("preview000", "crisp", "soft", "chime", "preview", "preview1", "preview04") } ?: "preview000"
    private fun foregroundAlert(prefs: JSONObject) {
        val now = android.os.SystemClock.elapsedRealtime()
        if (now - lastAlert < 500) return
        lastAlert = now
        if (prefs.optBoolean("messageSoundEnabled", true)) {
            ringtone?.stop()
            val resource = context.resources.getIdentifier("chat_message_${soundID(prefs)}", "raw", context.packageName)
            ringtone = RingtoneManager.getRingtone(context, Uri.parse("android.resource://${context.packageName}/$resource"))
            ringtone?.audioAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build()
            ringtone?.play()
        }
        if (prefs.optBoolean("vibration", true)) {
            val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= 26) vibrator.vibrate(VibrationEffect.createOneShot(200, VibrationEffect.DEFAULT_AMPLITUDE)) else vibrator.vibrate(200)
        }
    }
    private fun fetchAvatar(url: String): Bitmap? = runCatching {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 4000; connection.readTimeout = 4000
            val bytes = connection.inputStream.use { it.readBytesBounded(4 * 1024 * 1024) }
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
            if (options.outWidth <= 0 || options.outHeight <= 0) return@runCatching null
            options.inSampleSize = 1
            while (maxOf(options.outWidth, options.outHeight) / options.inSampleSize > 128) options.inSampleSize *= 2
            options.inJustDecodeBounds = false
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        } finally { connection.disconnect() }
    }.getOrNull()
    private fun java.io.InputStream.readBytesBounded(limit: Int): ByteArray {
        val buffer = java.io.ByteArrayOutputStream(); val chunk = ByteArray(8192)
        val deadline = android.os.SystemClock.elapsedRealtime() + 10000
        while (true) {
            require(android.os.SystemClock.elapsedRealtime() < deadline)
            val count = read(chunk); if (count < 0) break
            require(buffer.size() + count <= limit); buffer.write(chunk, 0, count) }
        return buffer.toByteArray()
    }
}
