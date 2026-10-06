import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_setup/message_context_page.dart';
import 'package:openim/pages/chat/history_search/chat_history_category.dart';
import 'package:openim/pages/chat/history_search/chat_history_results_page.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';
import 'package:openim/pages/chat/history_search/navigation/chat_history_message_navigation.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_source.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NavigationProbe extends ChatHistoryMessageNavigation {
  final calls = <({String conversationID, Message message})>[];

  @override
  Future<bool> open(BuildContext context,
      {required String conversationID,
      required Message message,
      required bool Function() isEntryCurrent}) async {
    expect(isEntryCurrent(), isTrue);
    calls.add((conversationID: conversationID, message: message));
    return true;
  }
}

typedef _SearchCall = ({
  String conversationID,
  ChatHistorySearchQuery query,
  int pageIndex,
  int count,
});

class _SearchSource implements ChatHistorySearchSource {
  _SearchSource(this.respond);

  final Future<List<Message>> Function(_SearchCall) respond;
  final calls = <_SearchCall>[];

  @override
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  }) {
    final call = (
      conversationID: conversationID,
      query: query,
      pageIndex: pageIndex,
      count: count,
    );
    calls.add(call);
    return respond(call);
  }
}

const _conversationID = 'sender-search-conversation';
const _senderID = 'selected-member';
const _sender = ChatHistorySender(
  userID: _senderID,
  displayName: '群内名片',
  nickname: '秋12123',
);

Message _message(String id, {String sender = _senderID}) => Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.text,
      'sessionType': ConversationType.single,
      'sendID': sender,
      'recvID': 'self',
      'senderNickname': sender == _sender.userID ? '213123' : '另一个成员',
      'sendTime': DateTime.now().millisecondsSinceEpoch,
      'seq': 1,
      'status': MessageStatus.succeeded,
      'textElem': {'content': '消息 $id'},
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late _NavigationProbe messageNavigation;

  setUp(() async {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: 'Self');
    OpenIM.iMManager.token = 'sender-results-session';
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    messageNavigation = _NavigationProbe();
  });

  tearDown(() {
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> mount(WidgetTester tester, _SearchSource source,
      {Brightness brightness = Brightness.light,
      bool settle = true,
      double textScale = 1,
      Size viewport = const Size(390, 844)}) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        theme: ThemeData(brightness: brightness),
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ChatHistoryResultsPage(
          conversationID: _conversationID,
          category: ChatHistoryCategory.sender,
          sender: _sender,
          // A caller's main-search query must never silently restrict this page.
          initialQuery: 'unrelated inherited keyword',
          source: source,
          messageNavigation: messageNavigation,
        ),
      ),
    ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  void expectSenderScope(_SearchCall call, {required int pageIndex}) {
    expect(call.conversationID, _conversationID);
    expect(call.pageIndex, pageIndex);
    expect(call.count, 30);
    expect(call.query.keyword, isEmpty);
    expect(call.query.senderIDs, [_sender.userID]);
    expect(call.query.messageTypes, isEmpty);
    expect(call.query.sdkMessageTypes, isNotEmpty);
    expect(call.query.startDate, isNull);
    expect(call.query.endDate, isNull);
  }

  Future<void> unmount(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  final more = find.byKey(const ValueKey('chat-history-more'));
  final retry = find.byKey(const ValueKey('chat-history-retry'));

  for (final brightness in Brightness.values) {
    testWidgets(
        '${brightness.name}: selected sender title and mixed native results retain sender scope',
        (tester) async {
      final source = _SearchSource((_) async => [
            _message('included'),
            _message('wrong-sender', sender: 'another-member'),
          ]);

      await mount(tester, source, brightness: brightness);

      expect(source.calls, hasLength(1));
      expectSenderScope(source.calls.single, pageIndex: 1);
      expect(find.text(_sender.name), findsOneWidget,
          reason: 'The selected public name belongs in the navigation title.');
      expect(find.text('发送人'), findsNothing);
      expect(find.text(_sender.displayName), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(SearchBox), findsNothing);
      expect(find.text('213123'), findsOneWidget);
      expect(find.text('消息 included'), findsOneWidget);
      expect(find.text('消息 wrong-sender'), findsNothing,
          reason: 'The native SDK may ignore senderUserIDList.');
      expect(find.text('另一个成员'), findsNothing);
      expect(more, findsNothing);
      expect(retry, findsNothing);
      await unmount(tester);
    });

    testWidgets('${brightness.name}: pending sender search becomes empty',
        (tester) async {
      final response = Completer<List<Message>>();
      final source = _SearchSource((_) => response.future);
      await mount(tester, source, brightness: brightness, settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(more, findsNothing);
      expect(retry, findsNothing);

      response.complete([]);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('暂无数据'), findsOneWidget);
      expect(source.calls, hasLength(1));
      expectSenderScope(source.calls.single, pageIndex: 1);
      expect(more, findsNothing);
      expect(retry, findsNothing);
      await unmount(tester);
    });

    testWidgets('${brightness.name}: failed sender search retries its scope',
        (tester) async {
      var attempts = 0;
      final source = _SearchSource((_) async {
        if (++attempts == 1) throw StateError('Temporarily unavailable');
        return [_message('retry-match')];
      });
      await mount(tester, source, brightness: brightness);
      expect(retry, findsOneWidget);
      expect(find.text('暂无数据'), findsNothing);

      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(source.calls, hasLength(2));
      for (final call in source.calls) {
        expectSenderScope(call, pageIndex: 1);
      }
      expect(find.text('消息 retry-match'), findsOneWidget);
      expect(retry, findsNothing);
      expect(more, findsNothing);
      await unmount(tester);
    });

    testWidgets(
        '${brightness.name}: pagination failure preserves results and retries the same raw cursor',
        (tester) async {
      var pageTwoAttempts = 0;
      final source = _SearchSource((call) async {
        if (call.pageIndex == 1) {
          return List.generate(30, (index) => _message('first-$index'));
        }
        if (++pageTwoAttempts == 1) throw StateError('Connection interrupted');
        return [
          _message('last-match'),
          _message('last-other', sender: 'another-member'),
        ];
      });
      await mount(tester, source, brightness: brightness);
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(more, 500,
          scrollable: scrollable, maxScrolls: 20);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(retry, findsOneWidget);
      expect(find.text('消息 first-29'), findsOneWidget,
          reason: 'A failed next page must preserve the already loaded rows.');
      expect(source.calls.map((call) => call.pageIndex), [1, 2]);

      await tester.tap(retry);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('消息 last-match'), 200,
          scrollable: scrollable, maxScrolls: 5);

      expect(source.calls.map((call) => call.pageIndex), [1, 2, 2]);
      for (final call in source.calls) {
        expectSenderScope(call, pageIndex: call.pageIndex);
      }
      expect(find.text('消息 first-29'), findsOneWidget);
      expect(find.text('消息 last-match'), findsOneWidget);
      expect(find.text('消息 last-other'), findsNothing);
      expect(retry, findsNothing);
      expect(more, findsNothing);
      await unmount(tester);
    });
  }

  testWidgets('sender result requests the same original private message',
      (tester) async {
    final target = _message('private-match')
      ..attachedInfoElem = AttachedInfoElem(
        isPrivateChat: true,
        hasReadTime: DateTime.now().millisecondsSinceEpoch,
        burnDuration: 3600,
      );
    final source = _SearchSource((_) async => [target]);
    await mount(tester, source);
    expect(find.byType(ChatExpiringContent), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('chat-history-result-private-match')));
    await tester.pumpAndSettle();

    expect(messageNavigation.calls, hasLength(1));
    final call = messageNavigation.calls.single;
    expect(call.conversationID, _conversationID);
    expect(call.message.clientMsgID, target.clientMsgID);
    expect(call.message, same(target),
        reason:
            'Do not construct a summary message that drops private metadata.');
    expect(call.message.attachedInfoElem?.isPrivateChat, isTrue);
    expect(find.byType(MessageContextPage), findsNothing);
    expect(find.text('消息 private-match'), findsOneWidget);
    expect(source.calls, hasLength(1),
        reason: 'Requesting navigation must not repeat the sender search.');
    await unmount(tester);
  });

  for (final changeUser in [true, false]) {
    testWidgets(
        '${changeUser ? 'account' : 'token'} change blocks opening an old sender result',
        (tester) async {
      final source = _SearchSource((_) async => [_message('session-match')]);
      final sdkCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        sdkCalls.add(call);
        throw PlatformException(code: 'unexpected', message: call.method);
      });
      await mount(tester, source);
      if (changeUser) {
        OpenIM.iMManager.userID = 'new-account';
      } else {
        OpenIM.iMManager.token = 'new-session';
      }
      await tester
          .tap(find.byKey(const ValueKey('chat-history-result-session-match')));
      await tester.pumpAndSettle();
      expect(find.byType(MessageContextPage), findsNothing);
      expect(messageNavigation.calls, isEmpty);
      expect(sdkCalls, isEmpty);
      expect(source.calls, hasLength(1));
      await unmount(tester);
    });
  }

  testWidgets('a sender result expiring after rendering cannot be opened',
      (tester) async {
    final target = _message('expires-match')
      ..attachedInfoElem = AttachedInfoElem(
        isPrivateChat: true,
        hasReadTime: DateTime.now().millisecondsSinceEpoch,
        burnDuration: 3600,
      );
    final source = _SearchSource((_) async => [target]);
    final sdkCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      sdkCalls.add(call);
      throw PlatformException(code: 'unexpected', message: call.method);
    });
    await mount(tester, source);
    target.attachedInfoElem!.hasReadTime =
        DateTime(2020).millisecondsSinceEpoch;
    await tester.tap(find.text('消息 expires-match'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MessageContextPage), findsNothing);
    expect(messageNavigation.calls, isEmpty);
    expect(find.text('消息 expires-match'), findsNothing);
    expect(find.text('sdkExpired'.tr), findsOneWidget);
    expect(sdkCalls, isEmpty);
    await unmount(tester);
  });

  testWidgets('disposing a pending sender page ignores its late response',
      (tester) async {
    final response = Completer<List<Message>>();
    final source = _SearchSource((_) => response.future);
    await mount(tester, source, settle: false);
    await unmount(tester);
    response.complete([_message('late')]);
    await tester.pumpAndSettle();
    expect(find.text('消息 late'), findsNothing);
    expect(source.calls, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name}: narrow sender results support large text',
        (tester) async {
      final message = _message('large-text')
        ..senderNickname = '很长的发送人昵称保持时间和摘要可读'
        ..textElem = TextElem(content: '消息摘要包含很长的一段内容，用于窄屏大字体下的真实布局验证。');
      final source = _SearchSource((_) async => [message]);
      await mount(tester, source,
          brightness: brightness, textScale: 2, viewport: const Size(320, 844));
      expect(find.text(message.senderNickname!), findsOneWidget);
      expect(find.text(message.textElem!.content!), findsOneWidget);
      expect(find.text(_sender.name), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }
}
