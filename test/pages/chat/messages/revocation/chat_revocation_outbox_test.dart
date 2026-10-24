import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:openim/pages/chat/media/upload/chat_media_outbox.dart';
import 'package:openim/pages/chat/media/upload/chat_media_outbox_binding.dart';
import 'package:openim/pages/chat/messages/chat_delivery_controller.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim/services/chat_revocation_notice.dart';
import 'package:openim/services/favorite_send_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
    await Config.init(() {});
  });
  setUp(() {
    ChatHistoryCache.clear();
    OpenIM.iMManager.userID = 'owner';
  });
  tearDown(ChatHistoryCache.clear);

  for (final source in [
    'known_recall',
    'persisted_notice',
    'late_receipt',
    'empty_pending',
    'direct_receipt'
  ]) {
    test('outbox cannot restore recalled picture from $source', () async {
      final outbox = ChatMediaOutbox();
      final task = outbox.accept(const FavoriteTarget(
          conversationID: 'chat', userID: 'peer', sessionType: 1));
      final picture = Message(
          clientMsgID: 'image',
          sendID: 'owner',
          contentType: MessageType.picture,
          status: source == 'empty_pending'
              ? MessageStatus.sending
              : MessageStatus.succeeded,
          pictureElem: PictureElem(sourcePath: '/test/image.jpg'));
      task.stage(picture);
      final info = RevokedInfo(clientMsgID: 'image', revokerID: 'owner');
      if (source != 'persisted_notice') {
        ChatHistoryCache.revokeMessage('owner', info);
      }
      final messages = <Message>[
        if (source != 'empty_pending')
          ChatRevocationNotice.replace(picture, info)
      ].obs;
      final delivery = ChatDeliveryController(
          messageList: messages,
          conversation: () => ConversationInfo(conversationID: 'chat'),
          isClosed: () => false,
          groupStatus: () => null,
          scrollBottom: () {},
          resetInput: (_) {});
      final subscription = source == 'direct_receipt'
          ? null
          : bindMediaOutbox(
              conversationID: 'chat',
              messages: messages,
              isClosed: () => false,
              removedIDs: {},
              delivery: delivery,
              outbox: outbox);
      addTearDown(() async {
        await subscription?.cancel();
        delivery.close();
        outbox.clear();
      });
      if (source == 'late_receipt') task.stage(picture);
      if (source == 'direct_receipt') {
        delivery.updateMessage(messages.single, picture);
      }
      // Assert synchronously, before any history read can repair the first frame.
      expect(
          messages.single.contentType, MessageType.revokeMessageNotification);
      expect(messages.single.pictureElem, isNull);
    });
  }
}
