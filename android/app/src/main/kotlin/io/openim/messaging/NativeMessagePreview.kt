package io.openim.messaging

import org.json.JSONObject

/** Mirrors supported Dart message elements; unknown/custom HTML is never rendered. */
internal object NativeMessagePreview {
    fun text(m: JSONObject, labels: JSONObject): String {
        fun label(key: String) = labels.optString(key, key)
        fun tag(key: String) = "[${label(key)}]"
        fun elem(key: String) = NativeNotificationPolicy.objectValue(m.opt(key))
        val result = when (m.optInt("contentType")) {
            101 -> elem("textElem").optString("content")
            102 -> tag("picture")
            103 -> tag("voice") + elem("soundElem").optInt("duration").let { if (it > 0) " $it″" else "" }
            104 -> tag("video")
            105 -> tag("file") + elem("fileElem").optString("fileName").let { if (it.isEmpty()) "" else " $it" }
            106 -> {
                val at = elem("atTextElem")
                var text = at.optString("text")
                val users = at.optJSONArray("atUsersInfo")
                (0 until (users?.length() ?: 0)).mapNotNull { users?.optJSONObject(it) }
                    .sortedByDescending { it.optString("atUserID").length }.forEach {
                        val id = it.optString("atUserID")
                        if (id.isNotEmpty() && it.has("groupNickname")) text = text.replace("@$id", "@${if (id == "atAllTag") label("everyone") else it.optString("groupNickname")}")
                    }
                text.replace("@atAllTag", "@${label("everyone")}")
            }
            107 -> "${tag("chatRecord")} ${elem("mergeElem").optString("title") }"
            108 -> tag("carte") + elem("cardElem").optString("nickname")
            109 -> "${tag("toolboxLocation")} ${elem("locationElem").optString("description") }"
            114 -> elem("quoteElem").optString("text")
            115 -> tag("emoji")
            117 -> elem("advancedTextElem").optString("text")
            110 -> custom(NativeNotificationPolicy.objectValue(elem("customElem").opt("data")), labels)
            else -> tag("unsupportedMessage")
        }
        return NativeNotificationPolicy.line(result).ifEmpty { tag("unsupportedMessage") }
    }
    private fun custom(c: JSONObject, labels: JSONObject): String {
        fun label(key: String) = labels.optString(key, key)
        fun tag(key: String) = "[${label(key)}]"
        val biz = c.optString("biz")
        val currency = c.optString("currency")
        val amount = c.optString("amount")
        val scale = if (currency == "BI99") 2 else 6
        if (c.opt("orderID") is String && c.optString("orderID").isNotBlank() &&
            biz in setOf("transfer", "group_transfer", "packet_exclusive", "packet_normal", "packet_lucky") &&
            currency in setOf("USDT", "TRX", "BI99") && c.opt("amount") is String &&
            amount.matches(Regex("[0-9]+(?:\\.[0-9]+)?")) && amount.any { it in '1'..'9' } &&
            amount.substringAfter('.', "").length <= scale && c.optString("status") in setOf("open", "done", "refunded")) {
            val type = when (biz) { "packet_exclusive" -> "fundExclusivePacket"; "packet_lucky" -> "fundLuckyPacket"
                "packet_normal" -> "fundPacket"; "group_transfer" -> "fundGroupTransfer"; else -> "fundTransfer" }
            return tag(type) + if (biz.startsWith("packet_")) "" else " $amount ${if (currency == "BI99") "元" else currency}"
        }
        val data = NativeNotificationPolicy.objectValue(c.opt("data"))
        return when (c.optInt("customType")) {
            902 -> tag("emoji")
            906 -> tag("diceLabel") + if (data.optInt("version") == 1 && data.optInt("value") in 1..6)
                " " + label("dicePoint").replace("%s", data.optInt("value").toString()) else ""
            901 -> {
                val type = when (data.optString("type")) { "audio" -> "callVoice"; "video" -> "callVideo"; else -> "audioAndVideoCall" }
                val state = when(data.optString("state")) { "cancel" -> "cancelled"; "beCanceled" -> "cancelledByCaller";
                    "reject" -> "rejected"; "beRejected" -> "rejectedByCaller"; "timeout" -> "callTimeout"; "networkError" -> "networkAnomaly"; "otherAccepted" -> "otherAccepted"; else -> "" }
                if (data.optString("state") in setOf("hangup", "beHangup")) {
                    val seconds = data.optInt("duration").coerceAtLeast(0)
                    val duration = if (seconds <= 3600) "%02d:%02d".format(seconds / 60, seconds % 60)
                        else "%02d:%02d:%02d".format(seconds / 3600, seconds / 60 % 60, seconds % 60)
                    tag(type) + " " + label("callDuration").replace("%s", duration)
                } else tag(type) + if (state.isEmpty()) "" else " ${label(state)}"
            }
            910 -> label("blockedByFriendHint")
            911 -> label("deletedByFriendHint").replace("%s", "")
            912 -> label("removedFromGroupHint")
            913 -> label("groupDisbanded")
            else -> tag("unsupportedMessage")
        }
    }
}
