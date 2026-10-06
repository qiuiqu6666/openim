import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history_search/navigation/chat_history_message_navigation.dart';

const _conversationID = 'searched-conversation';

Message _message(String id, {int seq = 1}) => Message(
    clientMsgID: id,
    contentType: MessageType.text,
    status: MessageStatus.succeeded,
    sendTime: DateTime(2026, 10, 1, 12).millisecondsSinceEpoch,
    seq: seq,
    textElem: TextElem(content: 'result $id'));

Message _expire(Message message) => message
  ..attachedInfoElem = AttachedInfoElem(
      isPrivateChat: true,
      burnDuration: 1,
      hasReadTime: DateTime.now()
          .subtract(const Duration(seconds: 10))
          .millisecondsSinceEpoch);

class _Fixture {
  final navigator = GlobalKey<NavigatorState>();
  final snapshot = _message('target');
  final fresh = _message('target', seq: 99);
  final feedback = <ChatHistoryNavigationFailure>[];
  final finds = <(String, String)>[];
  final conversations = <String>[];
  final focused = <Message>[];
  final opened = <(ConversationInfo, Message)>[];
  Object? owner = ('self', 'token');
  bool entryCurrent = true;
  bool chatCurrent = true;
  bool focusResult = true;
  ChatHistoryActiveChat? chat;
  Future<Message?> Function()? lookup;
  Future<ConversationInfo?> Function()? conversationLookup;
  Future<bool> Function(Message)? position;
  bool Function()? startupGuard;
  late BuildContext entryContext;
  late Route<dynamic> chatRoute;
  late Route<dynamic> entryRoute;
  late ChatHistoryMessageNavigation navigation;

  void initialize({bool productionSource = false}) {
    navigation = ChatHistoryMessageNavigation(
      currentSession: () => owner,
      currentChat: (_) => chat,
      showFeedback: feedback.add,
      findMessage: productionSource
          ? null
          : (conversationID, id) {
              finds.add((conversationID, id));
              return lookup?.call() ?? Future.value(fresh);
            },
      findConversation: productionSource
          ? null
          : (id) {
              conversations.add(id);
              return conversationLookup?.call() ??
                  Future.value(ConversationInfo(conversationID: id));
            },
      startChat: (conversation, message, isCurrent) async {
        startupGuard = isCurrent;
        if (isCurrent()) opened.add((conversation, message));
      },
    );
  }

  Future<void> mount(WidgetTester tester, {bool existingChat = true}) async {
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator, home: const Scaffold(body: Text('Home'))));
    await tester.pumpAndSettle();
    chatRoute = MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'chat'),
        builder: (_) => const Scaffold(body: Text('Real chat')));
    if (existingChat) {
      unawaited(navigator.currentState!.push(chatRoute));
      await tester.pumpAndSettle();
      chat = ChatHistoryActiveChat(
          conversationID: _conversationID,
          route: chatRoute,
          isCurrent: () => chatCurrent,
          focusMessage: (message) {
            focused.add(message);
            return position?.call(message) ?? Future.value(focusResult);
          });
    }
    entryRoute = MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'search'),
        builder: (context) {
          entryContext = context;
          return const Scaffold(body: Text('Search results'));
        });
    unawaited(navigator.currentState!.push(entryRoute));
    await tester.pumpAndSettle();
  }

  Future<bool> open() => navigation.open(entryContext,
      conversationID: _conversationID,
      message: snapshot,
      isEntryCurrent: () => entryCurrent);

  Future<void> cover(WidgetTester tester) async {
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Another page')))));
    await tester.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  testWidgets('reuses the concrete chat route and its fresh SDK target',
      (tester) async {
    final f = _Fixture()..initialize();
    await f.mount(tester);
    final focus = Completer<bool>();
    f.position = (_) => focus.future;
    final action = f.open();
    await tester.pumpAndSettle();
    expect(f.chatRoute.isCurrent, isTrue);
    expect(f.entryContext.mounted, isFalse);
    expect(f.focused.single, same(f.fresh));
    expect(f.focused.single.seq, 99);
    expect(f.finds, [(_conversationID, 'target')]);
    expect(f.conversations, isEmpty);
    expect(f.opened, isEmpty);
    // Removing the search entry is the intended route transition, not a reason
    // to cancel the focus that has already been handed to the chat owner.
    focus.complete(true);
    expect(await action, isTrue);
    expect(f.feedback, isEmpty);
  });

  testWidgets('opens another chat through the existing startup adapter',
      (tester) async {
    final f = _Fixture()..initialize();
    await f.mount(tester, existingChat: false);
    expect(await f.open(), isTrue);
    expect(f.entryRoute.isCurrent, isTrue);
    expect(f.opened.single.$1.conversationID, _conversationID);
    expect(f.opened.single.$2, same(f.fresh));
    expect(f.conversations, [_conversationID]);
    expect(f.focused, isEmpty);
    expect(f.startupGuard!(), isTrue);
    await f.cover(tester);
    expect(f.startupGuard!(), isFalse);
  });

  testWidgets('a different conversation never causes a pop to that chat',
      (tester) async {
    final f = _Fixture()..initialize();
    await f.mount(tester);
    f.chat = ChatHistoryActiveChat(
        conversationID: 'other-conversation',
        route: f.chatRoute,
        isCurrent: () => true,
        focusMessage: (_) async => throw StateError('wrong chat'));
    expect(await f.open(), isTrue);
    expect(f.entryRoute.isCurrent, isTrue);
    expect(f.chatRoute.isActive, isTrue);
    expect(f.opened, hasLength(1));
    expect(f.feedback, isEmpty);
  });

  testWidgets('an unmounted chat route cannot be used as a pop target',
      (tester) async {
    final f = _Fixture()..initialize();
    await f.mount(tester, existingChat: false);
    f.chat = ChatHistoryActiveChat(
        conversationID: _conversationID,
        route: f.chatRoute,
        isCurrent: () => true,
        focusMessage: (_) async => throw StateError('inactive chat'));
    expect(await f.open(), isTrue);
    expect(f.entryRoute.isCurrent, isTrue);
    expect(f.opened, hasLength(1));
    expect(f.feedback, isEmpty);
  });

  testWidgets('a chat with an invalid owner cannot be used as a pop target',
      (tester) async {
    final f = _Fixture()..initialize();
    await f.mount(tester);
    f.chatCurrent = false;
    expect(await f.open(), isTrue);
    expect(f.entryRoute.isCurrent, isTrue);
    expect(f.focused, isEmpty);
    expect(f.opened, hasLength(1));
    expect(f.feedback, isEmpty);
  });

  testWidgets('a chat owned by a nested navigator never clears the entry stack',
      (tester) async {
    final f = _Fixture()..initialize();
    final nested = GlobalKey<NavigatorState>();
    late Route<dynamic> nestedRoute;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: f.navigator,
      home: Navigator(
        key: nested,
        onGenerateRoute: (_) => nestedRoute = MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Nested chat'))),
      ),
    ));
    await tester.pumpAndSettle();
    f.entryRoute = MaterialPageRoute<void>(builder: (context) {
      f.entryContext = context;
      return const Scaffold(body: Text('Search results'));
    });
    unawaited(f.navigator.currentState!.push(f.entryRoute));
    await tester.pumpAndSettle();
    f.chat = ChatHistoryActiveChat(
        conversationID: _conversationID,
        route: nestedRoute,
        isCurrent: () => true,
        focusMessage: (_) async => throw StateError('nested chat'));
    expect(await f.open(), isTrue);
    expect(f.entryRoute.isCurrent, isTrue);
    expect(nestedRoute.isActive, isTrue);
    expect(f.opened, hasLength(1));
    expect(f.feedback, isEmpty);
  });

  testWidgets('an already invalid entry does not request or navigate',
      (tester) async {
    final f = _Fixture()..initialize();
    await f.mount(tester);
    f.entryCurrent = false;
    expect(await f.open(), isFalse);
    expect(f.finds, isEmpty);
    expect(f.entryRoute.isCurrent, isTrue);
    expect(f.feedback, isEmpty);
  });

  testWidgets('a covered entry drops a pending SDK lookup silently',
      (tester) async {
    final f = _Fixture()..initialize();
    await f.mount(tester);
    final lookup = Completer<Message?>();
    f.lookup = () => lookup.future;
    final action = f.open();
    await f.cover(tester);
    lookup.complete(f.fresh);
    expect(await action, isFalse);
    expect(f.focused, isEmpty);
    expect(f.chatRoute.isCurrent, isFalse);
    expect(f.feedback, isEmpty);
  });

  testWidgets('a removed entry never uses its disposed context after lookup',
      (tester) async {
    final f = _Fixture()..initialize();
    await f.mount(tester);
    final lookup = Completer<Message?>();
    f.lookup = () => lookup.future;
    final action = f.open();
    f.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    lookup.complete(f.fresh);
    expect(await action, isFalse);
    expect(f.focused, isEmpty);
    expect(f.feedback, isEmpty);
    expect(await f.open(), isFalse);
  });

  testWidgets('account or token changes invalidate both SDK await boundaries',
      (tester) async {
    final f = _Fixture()..initialize();
    await f.mount(tester, existingChat: false);
    final lookup = Completer<Message?>();
    f.lookup = () => lookup.future;
    final first = f.open();
    f.owner = ('self', 'replacement-token');
    lookup.complete(f.fresh);
    expect(await first, isFalse);
    expect(f.conversations, isEmpty);
    expect(f.opened, isEmpty);
    f.owner = ('self', 'token');
    f.lookup = null;
    final conversation = Completer<ConversationInfo?>();
    f.conversationLookup = () => conversation.future;
    final second = f.open();
    await tester.pump();
    f.owner = ('other', 'token');
    conversation.complete(ConversationInfo(conversationID: _conversationID));
    expect(await second, isFalse);
    expect(f.opened, isEmpty);
    expect(f.feedback, isEmpty);
  });

  testWidgets('missing or mismatched SDK identity cannot revive the snapshot',
      (tester) async {
    final f = _Fixture()..initialize();
    await f.mount(tester);
    f.lookup = () async => null;
    expect(await f.open(), isFalse);
    f.lookup = () async => _message('another-target');
    expect(await f.open(), isFalse);
    expect(f.focused, isEmpty);
    expect(f.opened, isEmpty);
    expect(f.entryRoute.isCurrent, isTrue);
    expect(f.feedback, [
      ChatHistoryNavigationFailure.unavailable,
      ChatHistoryNavigationFailure.unavailable,
    ]);
  });

  testWidgets('expiry before and during lookup blocks navigation',
      (tester) async {
    final f = _Fixture()..initialize();
    await f.mount(tester);
    _expire(f.fresh);
    expect(await f.open(), isFalse);
    _expire(f.snapshot);
    expect(await f.open(), isFalse);
    expect(f.finds, hasLength(1));
    expect(f.focused, isEmpty);
    expect(f.feedback, [
      ChatHistoryNavigationFailure.expired,
      ChatHistoryNavigationFailure.expired,
    ]);
  });

  testWidgets('expiry while resolving the destination blocks a new chat',
      (tester) async {
    final f = _Fixture()..initialize();
    await f.mount(tester, existingChat: false);
    final conversation = Completer<ConversationInfo?>();
    f.conversationLookup = () => conversation.future;
    final action = f.open();
    await tester.pump();
    _expire(f.snapshot);
    conversation.complete(ConversationInfo(conversationID: _conversationID));
    expect(await action, isFalse);
    expect(f.opened, isEmpty);
    expect(f.feedback, [ChatHistoryNavigationFailure.expired]);
  });

  testWidgets('wrong SDK conversation cannot open another message owner',
      (tester) async {
    final f = _Fixture()..initialize();
    await f.mount(tester, existingChat: false);
    f.conversationLookup =
        () async => ConversationInfo(conversationID: 'other-conversation');
    expect(await f.open(), isFalse);
    expect(f.opened, isEmpty);
    expect(f.feedback, [ChatHistoryNavigationFailure.unavailable]);
  });

  testWidgets('double taps share a single pending request', (tester) async {
    final f = _Fixture()..initialize();
    await f.mount(tester);
    final lookup = Completer<Message?>();
    f.lookup = () => lookup.future;
    final action = f.open();
    expect(await f.open(), isFalse);
    expect(f.finds, hasLength(1));
    lookup.complete(f.fresh);
    await tester.pumpAndSettle();
    expect(await action, isTrue);
    expect(f.focused, hasLength(1));
  });

  testWidgets('lookup failure is contained and leaves a retryable entry',
      (tester) async {
    final f = _Fixture()..initialize();
    await f.mount(tester);
    f.lookup = () async => throw StateError('SDK failure');
    expect(await f.open(), isFalse);
    expect(f.entryRoute.isCurrent, isTrue);
    expect(f.feedback, [ChatHistoryNavigationFailure.failed]);
    f.lookup = null;
    final retry = f.open();
    await tester.pumpAndSettle();
    expect(await retry, isTrue);
    expect(f.focused, hasLength(1));
  });

  testWidgets('positioning failure is reported on the restored chat route',
      (tester) async {
    final f = _Fixture()..initialize();
    await f.mount(tester);
    f.focusResult = false;
    final action = f.open();
    await tester.pumpAndSettle();
    expect(await action, isFalse);
    expect(f.chatRoute.isCurrent, isTrue);
    expect(f.feedback, [ChatHistoryNavigationFailure.failed]);
  });

  testWidgets('owner changes after the intended pop cancel pending feedback',
      (tester) async {
    final f = _Fixture()..initialize();
    await f.mount(tester);
    final focus = Completer<bool>();
    f.position = (_) => focus.future;
    final action = f.open();
    await tester.pumpAndSettle();
    f.owner = ('other', 'token');
    focus.complete(false);
    expect(await action, isFalse);
    expect(f.feedback, isEmpty);
  });

  testWidgets('covering the restored chat cancels delayed positioning feedback',
      (tester) async {
    final f = _Fixture()..initialize();
    await f.mount(tester);
    final focus = Completer<bool>();
    f.position = (_) => focus.future;
    final action = f.open();
    await tester.pumpAndSettle();
    await f.cover(tester);
    focus.complete(false);
    expect(await action, isFalse);
    expect(f.feedback, isEmpty);
  });

  testWidgets('production source looks up exactly one conversation and message',
      (tester) async {
    final f = _Fixture()..initialize(productionSource: true);
    await f.mount(tester, existingChat: false);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'findMessageList' => jsonEncode({
            'findResultItems': [
              {
                'conversationID': 'wrong-conversation',
                'messageList': [_message('target', seq: 7).toJson()]
              },
              {
                'conversationID': _conversationID,
                'messageList': [f.fresh.toJson()]
              },
            ]
          }),
        'getMultipleConversation' => jsonEncode([
            ConversationInfo(conversationID: 'wrong-conversation').toJson(),
            ConversationInfo(conversationID: _conversationID).toJson(),
          ]),
        _ => throw StateError('Unexpected SDK request ${call.method}'),
      };
    });
    expect(await f.open(), isTrue);
    expect(calls.map((call) => call.method),
        ['findMessageList', 'getMultipleConversation']);
    expect((calls.first.arguments as Map)['searchParams'], [
      {
        'conversationID': _conversationID,
        'clientMsgIDList': ['target']
      }
    ]);
    expect(
        (calls.last.arguments as Map)['conversationIDList'], [_conversationID]);
    expect(f.opened.single.$1.conversationID, _conversationID);
    expect(f.opened.single.$2.seq, 99);
    expect(f.feedback, isEmpty);
  });
}
