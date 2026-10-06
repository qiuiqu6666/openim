import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/contacts/select_contacts/recent_conversations/recent_conversation_preview.dart';
import 'package:openim/pages/contacts/select_contacts/recent_conversations/recent_conversation_preview_controller.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController with IMCallback implements IMController {
  @override
  void onClose() {
    close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conversations extends GetxController implements ConversationLogic {
  final _accountID = OpenIM.iMManager.userID;
  final _token = DataSp.chatToken;

  @override
  final list = <ConversationInfo>[].obs;

  @override
  bool get isSessionActive =>
      !isClosed &&
      OpenIM.iMManager.userID == _accountID &&
      DataSp.chatToken == _token;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Message _message(String id, [String? text]) => Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.text,
      'sendID': 'peer',
      'senderNickname': 'Peer',
      'textElem': {'content': text ?? id},
    });

ConversationInfo _row(Message? message, {String id = 'si_peer'}) =>
    ConversationInfo(
      conversationID: id,
      conversationType: ConversationType.single,
      userID: 'peer',
      latestMsg: message,
    );

Future<void> _credentials(String token, {String userID = 'self'}) async {
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': userID,
    'chatToken': token,
    'imToken': 'im-token',
  }));
}

Future<void> _mount(WidgetTester tester,
        RecentConversationPreviewController logic, ConversationInfo snapshot,
        {VoidCallback? onBuild}) =>
    tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Obx(() {
        onBuild?.call();
        return Text(logic.text(snapshot), key: const ValueKey('preview'));
      }),
    ));

String _painted(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('preview'))).data!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late _IM im;
  late List<MethodCall> sdkCalls;

  setUp(() async {
    Get.testMode = true;
    Get.addTranslations(TranslationService().keys);
    Get.locale = const Locale('zh', 'CN');
    OpenIM.iMManager.userID = 'self';
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await _credentials('initial-token');
    ChatHistoryCache.clear();
    Get.put<AppController>(_App());
    im = _IM();
    Get.put<IMController>(im);
    sdkCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      sdkCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    expect(sdkCalls, isEmpty,
        reason:
            'Previewing must not load history, register SDK listeners, or mark read.');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    Get.reset();
    ChatHistoryCache.clear();
    OpenIM.iMManager.userID = 'self';
  });

  RecentConversationPreviewController createPreview() {
    final logic = RecentConversationPreviewController();
    addTearDown(logic.dispose);
    return logic;
  }

  testWidgets('reads live replacements and never falls back after removal',
      (tester) async {
    final snapshot = _row(_message('old', 'snapshot text'));
    final conversations = Get.put<ConversationLogic>(_Conversations());
    conversations.list.add(_row(_message('current', 'current text')));
    final logic = createPreview();
    await _mount(tester, logic, snapshot);
    expect(_painted(tester), 'current text');

    conversations.list[0] = _row(_message('new', 'replacement text'));
    await tester.pump();
    expect(_painted(tester), 'replacement text');
    conversations.list.clear();
    await tester.pump();
    expect(_painted(tester), '');
    expect(snapshot.latestMsg!.textElem!.content, 'snapshot text');
  });

  test('uses an existing snapshot only when there is no shared feed', () {
    final snapshot = _row(_message('old', 'snapshot text'))
      ..draftText = 'not sent';
    expect(createPreview().text(snapshot), '[${StrRes.draftText}]not sent');
  });

  testWidgets('existing revoke and delete events invalidate retained snapshots',
      (tester) async {
    final snapshot = _row(_message('first', 'first body'));
    final logic = createPreview();
    await _mount(tester, logic, snapshot);
    expect(_painted(tester), 'first body');
    im.recvMessageRevoked(RevokedInfo(clientMsgID: 'first'));
    await tester.pump();
    await tester.pump();
    expect(_painted(tester), '');

    snapshot.latestMsg = _message('second', 'second body');
    await _mount(tester, logic, snapshot);
    expect(_painted(tester), 'second body');
    im.messageDeleted(snapshot.latestMsg!);
    await tester.pump();
    await tester.pump();
    expect(_painted(tester), '');
  });

  for (final switchAccount in [false, true]) {
    testWidgets(
        'rejects ${switchAccount ? 'account' : 'same-account token'} changes and ignores later events',
        (tester) async {
      final snapshot = _row(_message('latest', 'old secret'));
      final logic = createPreview();
      var builds = 0;
      await _mount(tester, logic, snapshot, onBuild: () => builds++);
      expect(_painted(tester), 'old secret');
      if (switchAccount) OpenIM.iMManager.userID = 'new-account';
      await _credentials('new-token',
          userID: switchAccount ? 'new-account' : 'self');
      expect(logic.text(snapshot), '');
      final beforeEvents = builds;
      im.recvMessageRevoked(RevokedInfo(clientMsgID: 'unrelated'));
      im.messageDeleted(_message('unrelated'));
      await tester.pump();
      expect(builds, beforeEvents,
          reason: 'Old preview owners must stop publishing updates.');
      await _mount(tester, logic, snapshot);
      expect(_painted(tester), '');
    });
  }

  test('new preview rejects a retained feed from an earlier login', () async {
    final conversations = Get.put<ConversationLogic>(_Conversations());
    final snapshot = _row(_message('old', 'previous login body'));
    conversations.list.add(snapshot);
    await _credentials('new-token');
    expect(conversations.isSessionActive, isFalse);
    expect(createPreview().text(snapshot), '');
  });

  test('closed shared feed cannot expose a retained conversation', () {
    final conversations = Get.put<ConversationLogic>(_Conversations());
    final snapshot = _row(_message('old', 'retained body'));
    conversations.list.add(snapshot);
    final logic = createPreview();
    conversations.onDelete();
    expect(logic.text(snapshot), '');
  });

  testWidgets(
      'selection lazily owns and releases only its stream subscriptions',
      (tester) async {
    final selection = SelectContactsLogic();
    expect(im.revokedMessages.hasListener, isFalse);
    expect(im.deletedMessages.hasListener, isFalse);
    final logic = selection.recentPreviews;
    expect(selection.recentPreviews, same(logic));
    expect(im.revokedMessages.hasListener, isTrue);
    expect(im.deletedMessages.hasListener, isTrue);
    var otherRevokes = 0;
    var otherDeletes = 0;
    final revoke = im.revokedMessages.listen((_) => otherRevokes++);
    final delete = im.deletedMessages.listen((_) => otherDeletes++);
    final snapshot = _row(_message('latest'));
    var builds = 0;
    await _mount(tester, logic, snapshot, onBuild: () => builds++);
    selection.onClose();
    expect(logic.text(snapshot), '');
    final beforeEvents = builds;
    im.recvMessageRevoked(RevokedInfo(clientMsgID: 'latest'));
    im.messageDeleted(_message('latest'));
    await tester.pump();
    expect(builds, beforeEvents);
    expect(otherRevokes, 1);
    expect(otherDeletes, 1);
    expect(im.revokedMessages.isClosed, isFalse);
    expect(im.deletedMessages.isClosed, isFalse);
    revoke.cancel();
    delete.cancel();
    await tester.pump();
    expect(im.revokedMessages.hasListener, isFalse);
    expect(im.deletedMessages.hasListener, isFalse);
  });

  group('guarded preview formatting', () {
    test(
        'empty conversations and removed latest messages show no retained text',
        () {
      expect(recentConversationPreview(null), '');
      expect(recentConversationPreview(_row(null)..draftText = 'draft only'),
          '[${StrRes.draftText}]draft only');
      final snapshot = _row(_message('deleted', 'deleted secret'));
      ChatHistoryCache.removeMessage('other-account', 'deleted');
      expect(recentConversationPreview(snapshot), 'deleted secret');
      ChatHistoryCache.removeMessage('self', 'deleted');
      expect(recentConversationPreview(snapshot), '');
    });

    test('unread, draft and announcement prefixes follow the main feed order',
        () {
      final row = _row(_message('latest', 'sent text'))..unreadCount = 3;
      expect(recentConversationPreview(row), '[3条] sent text');
      row.groupAtType = GroupAtType.groupNotification;
      expect(
          recentConversationPreview(row), '[3条] [${StrRes.groupAc}]sent text');
      for (final draft in [
        'draft\nbody',
        jsonEncode({'text': 'draft\nbody'})
      ]) {
        row.draftText = draft;
        expect(recentConversationPreview(row),
            '[3条] [${StrRes.draftText}]draft body');
      }
      Get.locale = const Locale('en', 'US');
      expect(recentConversationPreview(row),
          '[3 pieces] [${StrRes.draftText}]draft body');
      expect(row.unreadCount, 3);
      expect(row.draftText, jsonEncode({'text': 'draft\nbody'}));
    });

    test('message tombstones preserve unread state and an independent draft',
        () {
      final row = _row(_message('deleted', 'deleted secret'))..unreadCount = 2;
      ChatHistoryCache.removeMessage('self', 'deleted');
      expect(recentConversationPreview(row), '[2条] ');
      row.draftText = 'my draft';
      expect(
          recentConversationPreview(row), '[2条] [${StrRes.draftText}]my draft');
      row.latestMsg = null;
      expect(
          recentConversationPreview(row), '[2条] [${StrRes.draftText}]my draft');
    });

    test(
        'draft in private parent is hidden but own ordinary-chat draft is safe',
        () {
      final row = _row(
          _message('private', 'secret')
            ..attachedInfoElem = AttachedInfoElem(isPrivateChat: true))
        ..draftText = 'my draft';
      expect(recentConversationPreview(row), '[${StrRes.draftText}]my draft');
      row.isPrivateChat = true;
      expect(recentConversationPreview(row),
          '[${StrRes.draftText}][${StrRes.burnAfterReading}]');
    });

    test('private conversation and retained private metadata use only a label',
        () {
      final message = _message('private', 'secret');
      final snapshot = _row(message)..isPrivateChat = true;
      final expected = '[${StrRes.burnAfterReading}]';
      expect(recentConversationPreview(snapshot), expected);
      snapshot.isPrivateChat = false;
      message.attachedInfoElem = AttachedInfoElem(isPrivateChat: true);
      expect(recentConversationPreview(snapshot), expected);
      message.attachedInfoElem = null;
      for (final metadata in [
        jsonEncode({'isPrivateChat': true}),
        jsonEncode({'burnDuration': 30}),
        '{malformed retained metadata',
      ]) {
        message.attachedInfo = metadata;
        expect(recentConversationPreview(snapshot), expected);
      }
    });

    test('quoted or merged private content does not reveal wrapper text', () {
      final private = _message('private', 'secret')
        ..attachedInfoElem = AttachedInfoElem(isPrivateChat: true);
      final quote = _message('quote')
        ..contentType = MessageType.quote
        ..quoteElem = QuoteElem(text: 'quoted secret', quoteMessage: private);
      final merge = _message('merge')
        ..contentType = MessageType.merger
        ..mergeElem = MergeElem(title: 'secret title', multiMessage: [quote]);
      for (final message in [quote, merge]) {
        expect(recentConversationPreview(_row(message)),
            '[${StrRes.burnAfterReading}]');
      }
    });

    for (final locale in [const Locale('zh', 'CN'), const Locale('en', 'US')]) {
      test('expired and already-revoked messages use safe labels in $locale',
          () {
        Get.locale = locale;
        final expired = _message('expired', 'expired secret')
          ..attachedInfoElem = AttachedInfoElem(
              isPrivateChat: true,
              burnDuration: 1,
              hasReadTime: DateTime.now()
                  .subtract(const Duration(minutes: 2))
                  .millisecondsSinceEpoch);
        expect(expired.hasExpired, isTrue);
        expect(recentConversationPreview(_row(expired)), 'sdkExpired'.tr);
        final revoked = _message('revoked', 'revoked secret')
          ..contentType = MessageType.revokeMessageNotification;
        expect(
            recentConversationPreview(_row(revoked)), '[${StrRes.revokeMsg}]');
      });
    }
  });
}
