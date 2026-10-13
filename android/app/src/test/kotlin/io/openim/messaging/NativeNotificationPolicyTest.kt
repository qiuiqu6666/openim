package io.openim.messaging

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import io.openim.flutter_openim_sdk.runtime.RuntimeConfiguration

class NativeNotificationPolicyTest {
    private fun message() = JSONObject("""{"contentType":101,"sessionType":1,"sendID":"alice","recvID":"bob","clientMsgID":"m1","textElem":{"content":"hello"}}""")
    private fun conversation() = JSONObject("""{"conversationID":"si_alice_bob","conversationType":1,"userID":"alice","recvMsgOpt":0}""")
    @Test fun messageFromOtherAccountCannotSelectWrongConversation() {
        assertTrue(NativeNotificationPolicy.eligible(message(), conversation(), "bob", 0))
        assertFalse(NativeNotificationPolicy.eligible(message(), conversation().put("userID", "mallory"), "bob", 0))
        assertFalse(NativeNotificationPolicy.eligible(message(), conversation(), "alice", 0))
        assertFalse(NativeNotificationPolicy.eligible(message().put("recvID", "previous-account"), conversation(), "bob", 0))
    }
    @Test fun serverPrivacyAndMuteOptionsOverrideLocalPreferences() {
        assertFalse(NativeNotificationPolicy.eligible(message(), conversation(), "bob", 2))
        for (mute in 1..2) assertFalse(NativeNotificationPolicy.eligible(message(), conversation().put("recvMsgOpt", mute), "bob", 0))
        for (field in listOf("attachedInfo", "attachedInfoElem"))
            assertFalse(NativeNotificationPolicy.eligible(message().put(field, """{"notSenderNotificationPush":true}"""), conversation(), "bob", 0))
    }
    @Test fun typingAndSystemEventsNeverBecomeMessageBanners() {
        for (type in listOf(113, 1000, 1500)) assertFalse(NativeNotificationPolicy.eligible(message().put("contentType", type), conversation(), "bob", 0))
    }
    @Test fun activeConversationOnlySuppressesVisibleUi() {
        val settings = JSONObject().put("openedPreview", "detail").put("closedPreview", "sender")
        assertNull(NativeNotificationPolicy.preview(settings, true, "c1", "c1"))
        assertEquals("sender", NativeNotificationPolicy.preview(settings, false, "c1", "c1"))
        assertNull(NativeNotificationPolicy.preview(settings.put("notifyWhenClosed", false), false, "", "c1"))
        assertNull(NativeNotificationPolicy.preview(settings.put("openedPreview", "hidden"), true, "", "c1"))
    }
    @Test fun assistantStreamingChunksAreNotNotifications() {
        val chunk = message().put("contentType", 110).put("customElem", JSONObject().put("description", "assistantStream"))
        assertFalse(NativeNotificationPolicy.eligible(chunk, conversation(), "bob", 0))
    }
    @Test fun privateMessageNeverUsesTextPreview() {
        assertTrue(NativeNotificationPolicy.privateMessage(message(), conversation().put("isPrivateChat", true)))
        assertTrue(NativeNotificationPolicy.privateMessage(message().put("attachedInfo", """{"isPrivateChat":true}"""), conversation()))
    }
    @Test fun stableNotificationIdMatchesExistingDartAlgorithm() {
        assertEquals(388258061, NativeNotificationPolicy.id("bob", "si_alice_bob"))
        assertNotEquals(NativeNotificationPolicy.id("bob", "si_alice_bob"), NativeNotificationPolicy.id("alice", "si_alice_bob"))
    }
    @Test fun paymentNoticeDeduplicatesDifferentSdkMessageIds() {
        val first = message().put("sendID", "99Pay").put("ex", """{"depositNoticeID":"deposit-1"}""")
        val next = JSONObject(first.toString()).put("clientMsgID", "m2")
        assertEquals(NativeNotificationPolicy.identity(first), NativeNotificationPolicy.identity(next))
        assertNotEquals(NativeNotificationPolicy.identity(first.put("sendID", "alice")), NativeNotificationPolicy.identity(next))
    }
    @Test fun officialAccountsCannotOfferQuickReply() {
        assertTrue(NativeNotificationPolicy.official(conversation().put("userID", "99Pay")))
        assertTrue(NativeNotificationPolicy.official(conversation().put("ex", """{"accountType":"official","officialRole":"message"}""")))
        assertFalse(NativeNotificationPolicy.official(conversation()))
    }
    @Test fun previewsOnlyUseSupportedSdkElements() {
        val labels = JSONObject().put("unsupportedMessage", "unsupported").put("picture", "photo").put("file", "file")
        assertEquals("hello", NativeMessagePreview.text(message(), labels))
        assertEquals("[photo]", NativeMessagePreview.text(message().put("contentType", 102), labels))
        assertEquals("[file] report.pdf", NativeMessagePreview.text(message().put("contentType", 105).put("fileElem", JSONObject().put("fileName", "report.pdf")), labels))
        assertEquals("[unsupported]", NativeMessagePreview.text(message().put("contentType", 110).put("customElem", JSONObject().put("data", "<script>bad</script>")), labels))
    }
    @Test fun runtimeRejectsImplicitServerDatabaseOrPlatformSwitch() {
        val config = JSONObject().put("platformID", 2).put("dataDir", "/app_flutter/").put("apiAddr", "https://api.example")
            .put("wsAddr", "wss://ws.example").put("operationID", "first")
        assertTrue(RuntimeConfiguration.matches(config.toString(), JSONObject(config.toString()).put("operationID", "second").toString()))
        for (field in listOf("dataDir", "wsAddr", "apiAddr", "platformID", "isCompression", "isNeedEncryption"))
            assertFalse(RuntimeConfiguration.matches(config.toString(), JSONObject(config.toString()).put(field, "different").toString()))
        assertFalse(RuntimeConfiguration.matches(config.toString(), "invalid"))
    }
}
