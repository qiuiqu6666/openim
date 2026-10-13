package io.openim.messaging

import org.json.JSONObject
import java.security.MessageDigest

/** Pure notification policy; SDK data, not an offline-push body, is authoritative. */
internal object NativeNotificationPolicy {
    fun objectValue(value: Any?): JSONObject = when (value) {
        is JSONObject -> value
        is String -> runCatching { JSONObject(value) }.getOrDefault(JSONObject())
        else -> JSONObject()
    }
    fun id(account: String, conversation: String): Int {
        val bytes = MessageDigest.getInstance("SHA-256").digest("$account|$conversation".toByteArray(Charsets.UTF_8))
        return ((bytes[0].toInt() and 127) shl 24) or ((bytes[1].toInt() and 255) shl 16) or
            ((bytes[2].toInt() and 255) shl 8) or (bytes[3].toInt() and 255)
    }
    fun eligible(m: JSONObject, c: JSONObject, account: String, globalOption: Int): Boolean {
        val type = m.optInt("contentType", -1)
        val session = m.optInt("sessionType")
        val flags = objectValue(m.opt("attachedInfo"))
        val extra = objectValue(m.opt("attachedInfoElem"))
        val source = if (session == 1) m.optString("sendID") else m.optString("groupID")
        return account.isNotBlank() && source.isNotBlank() && m.optString("sendID") != account &&
            (session != 1 || m.optString("recvID").isEmpty() || m.optString("recvID") == account) &&
            session in setOf(1, 2, 3) && type in 0..999 && type != 113 && globalOption != 2 &&
            !(type == 110 && objectValue(m.opt("customElem")).optString("description") == "assistantStream") &&
            c.optInt("recvMsgOpt") == 0 && c.optString("conversationID").isNotBlank() &&
            c.optInt("conversationType") == session &&
            (if (session == 1) c.optString("userID") == source else c.optString("groupID") == source) &&
            !flags.optBoolean("notSenderNotificationPush") && !extra.optBoolean("notSenderNotificationPush")
    }
    fun preview(prefs: JSONObject, foreground: Boolean, active: String, conversation: String): String? {
        if (!prefs.optBoolean(if (foreground) "notifyWhenOpen" else "notifyWhenClosed", true)) return null
        if (foreground && active == conversation) return null
        val value = prefs.optString(if (foreground) "openedPreview" else "closedPreview", "detail")
        return if (value == "hidden") null else value
    }
    fun privateMessage(m: JSONObject, c: JSONObject): Boolean = c.optBoolean("isPrivateChat") ||
        objectValue(m.opt("attachedInfo")).optBoolean("isPrivateChat") ||
        objectValue(m.opt("attachedInfoElem")).optBoolean("isPrivateChat")
    fun official(c: JSONObject): Boolean {
        if (c.optInt("conversationType") != 1) return false
        val ex = objectValue(c.opt("ex"))
        return c.optString("userID") in setOf("99Pay", "99Message") ||
            (ex.optString("accountType") == "official" && ex.optString("officialRole") in setOf("pay", "message"))
    }
    fun identity(m: JSONObject): String {
        val deposit = objectValue(m.opt("ex")).optString("depositNoticeID").trim()
        if (m.optInt("contentType") == 101 && m.optInt("sessionType") == 1 &&
            m.optString("sendID") == "99Pay" && deposit.isNotEmpty()) return "deposit:$deposit"
        return m.optString("clientMsgID").ifEmpty { m.optLong("seq").takeIf { it > 0 }?.toString() ?: "" }
    }
    fun line(value: String): String = value.replace(Regex("[\\x00-\\x1f\\x7f]"), " ").trim().take(2048)
}
