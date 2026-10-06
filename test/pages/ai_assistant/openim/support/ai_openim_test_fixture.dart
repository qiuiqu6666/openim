import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/history/chat_history_prefetcher.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../support/chat/chat_entry_sdk.dart';

const aiOpenimConversationID = 'si_assistant_self';

class AiOpenimTestConversation extends EntryTestConversation {
  final _list = <ConversationInfo>[].obs;
  @override
  RxList<ConversationInfo> get list => _list;
  @override
  bool get isSessionActive => true;
}

class AiOpenimTestApp extends EntryTestApp {
  final notifications = <Message>[];

  @override
  Future<void> showNotification(Message message,
      {bool showNotification = true}) async {
    notifications.add(message);
  }
}

Message aiOpenimText(String id, String text,
        {bool outgoing = false, int time = 1}) =>
    Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.text,
      'sessionType': ConversationType.single,
      'sendID': outgoing ? 'self' : 'assistant',
      'recvID': outgoing ? 'assistant' : 'self',
      'senderNickname': outgoing ? '我' : 'AI助理',
      'seq': time,
      'sendTime': 1791178200000 + time * 1000,
      'status': MessageStatus.succeeded,
      'textElem': {'content': text},
    });

Message aiOpenimTyping(String id, {String tips = 'yes', String? sender}) =>
    Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.typing,
      'sessionType': ConversationType.single,
      'sendID': sender ?? 'assistant',
      'recvID': 'self',
      'typingElem': {'msgTips': tips},
    });

Message aiOpenimStreamFragment(String id,
        {required String streamID,
        required int index,
        required String text,
        bool end = false}) =>
    Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.custom,
      'sessionType': ConversationType.single,
      'sendID': 'assistant',
      'recvID': 'self',
      'customElem': {
        'description': 'assistantStream',
        'data': jsonEncode({
          'streamID': streamID,
          'index': index,
          'text': text,
          'end': end,
        }),
      },
    });

Message aiOpenimStreamFinal(String id, String text, String streamID) =>
    aiOpenimText(id, text)..ex = jsonEncode({'streamID': streamID});

Message aiOpenimPicture(String id) => Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.picture,
      'sessionType': ConversationType.single,
      'sendID': 'assistant',
      'recvID': 'self',
      'senderNickname': 'AI助理',
      'sendTime': 1791178209000,
      'status': MessageStatus.succeeded,
      'pictureElem': {
        for (final name in ['sourcePicture', 'bigPicture', 'snapshotPicture'])
          name: {'width': 300, 'height': 180, 'type': 'png', 'size': 4096},
      },
    });

/// A real ChatLogic and native SDK boundary, without an AI HTTP transport.
class AiOpenimTestFixture {
  static const sdkChannel = MethodChannel('flutter_openim_sdk');
  final histories = <EntryHistoryCall>[];
  final newerHistories = <EntryHistoryCall>[];
  final nativeCalls = <MethodCall>[];
  final controllers = <ChatLogic>[];
  late EntryTestIM im;
  late AiOpenimTestApp app;
  late AiOpenimTestConversation conversations;
  int _serial = 0;
  bool failNextSend = false;

  Future<void> initialize() async {
    Get.testMode = true;
    ChatHistoryPrefetcher.shared.clear();
    ChatHistoryCache.clear();
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'self',
      'chatToken': 'test-chat-session',
      'imToken': 'test-im-session',
    }));
    app = Get.put<AppController>(AiOpenimTestApp()) as AiOpenimTestApp;
    im = Get.put<IMController>(EntryTestIM()) as EntryTestIM;
    conversations = Get.put<ConversationLogic>(AiOpenimTestConversation())
        as AiOpenimTestConversation;
    Get.put<CacheController>(EntryTestCache());
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: '我');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdkChannel, _native);
  }

  ChatLogic open({String? draft}) {
    Get.routing.args = {
      'conversationInfo': ConversationInfo(
        conversationID: aiOpenimConversationID,
        userID: 'assistant',
        conversationType: ConversationType.single,
        showName: 'AI助理',
        unreadCount: 0,
        groupAtType: GroupAtType.atNormal,
        isPrivateChat: false,
        draftText: draft,
      ),
    };
    final logic = ChatLogic();
    controllers.add(logic);
    logic.onInit();
    return logic;
  }

  Future<Object?> _native(MethodCall call) async {
    nativeCalls.add(call);
    final args = Map<String, dynamic>.from(call.arguments as Map);
    if (call.method == 'getAdvancedHistoryMessageList') {
      final history = EntryHistoryCall(args);
      histories.add(history);
      return history.result.future;
    }
    if (call.method == 'getAdvancedHistoryMessageListReverse') {
      final history = EntryHistoryCall(args);
      newerHistories.add(history);
      return history.result.future;
    }
    if (call.method == 'getBlacklist') return '[]';
    if (call.method == 'createTextMessage') {
      return jsonEncode(aiOpenimText('sent-${++_serial}', args['text'],
              outgoing: true, time: 20 + _serial)
          .toJson());
    }
    if (call.method == 'createQuoteMessage') {
      return jsonEncode({
        ...aiOpenimText('sent-${++_serial}', '', outgoing: true).toJson(),
        'contentType': MessageType.quote,
        'quoteElem': {
          'text': args['quoteText'],
          'quoteMessage': args['quoteMessage'],
        },
      });
    }
    if (call.method == 'createCustomMessage') {
      return jsonEncode({
        ...aiOpenimText('sent-${++_serial}', '', outgoing: true).toJson(),
        'contentType': MessageType.custom,
        'customElem': {
          'data': args['data'],
          'description': args['description'],
          'extension': args['extension'],
        },
      });
    }
    if (call.method == 'createCardMessage') {
      return jsonEncode({
        ...aiOpenimText('sent-${++_serial}', '', outgoing: true).toJson(),
        'contentType': MessageType.card,
        'cardElem': args['cardMessage'],
      });
    }
    if (call.method == 'sendMessage') {
      if (failNextSend) {
        failNextSend = false;
        throw PlatformException(code: 'NETWORK');
      }
      return jsonEncode({
        ...Map<String, dynamic>.from(args['message'] as Map),
        'status': MessageStatus.succeeded,
        'seq': 100 + _serial,
      });
    }
    return null;
  }

  Future<void> dispose() async {
    for (final logic in controllers.reversed) {
      if (!logic.isClosed) logic.onDelete();
    }
    for (final history in [...histories, ...newerHistories]) {
      history.complete([]);
    }
    ChatHistoryPrefetcher.shared.clear();
    ChatHistoryCache.clear();
    await DataSp.removeLoginCertificate();
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdkChannel, null);
  }
}
