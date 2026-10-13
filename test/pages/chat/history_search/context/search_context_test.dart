import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/chat/history/chat_history_loader.dart';
import 'package:openim/pages/chat/history_search/context/search_chat_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history_search/cloud/chat_keyword_search_api.dart';
import 'package:openim/pages/chat/history_search/context/search_context_api.dart';
import 'package:openim/pages/chat/history_search/context/search_context_controller.dart';
import 'package:openim/pages/chat/history_search/context/search_context_page.dart';
import 'package:openim/pages/chat/history_search/navigation/chat_history_message_navigation.dart';

const session = (user: 'self', token: 'im-token', server: 'https://im.example');
Map<String, dynamic> msg(int seq) => {
      'clientMsgID': 'm$seq',
      'serverMsgID': 's$seq',
      'seq': seq,
      'sendID': 'sender',
      'senderNickname': 'Alice',
      'contentType': 101,
      'textElem': {'content': '<b>message $seq</b>'}
    };
CloudKeywordMessage hit() => CloudKeywordMessage({
      ...msg(120),
      'conversationID': 'sg_test',
      'sendTime': 123456,
      'summary': 'message 120'
    });
Map<String, dynamic> around() => {
      'conversationID': 'sg_test',
      'anchorSeq': 120,
      'direction': 'around',
      'anchorMessage': msg(120),
      'messages': [msg(119), msg(120), msg(121)],
      'beforeCursor': 'b1',
      'afterCursor': 'a1',
      'beforeEnd': false,
      'afterEnd': false
    };
Map<String, dynamic> more(String direction, List<int> seqs,
        {String next = '', bool end = true}) =>
    {
      'conversationID': 'sg_test',
      'anchorSeq': 120,
      'direction': direction,
      'anchorMessage': msg(120),
      'messages': seqs.map(msg).toList(),
      'nextCursor': next,
      'isEnd': end
    };
SearchContextApi api(Future<dynamic> Function(Map<String, dynamic>) post) =>
    SearchContextApi(
        client: SearchHttpClient(
            session: () => session,
            post: (url, body, options) {
              expect(url, 'https://im.example/msg/search_message_context');
              expect(options.headers!['token'], 'im-token');
              expect(body.containsKey('userID'), isFalse);
              return post(body);
            }));
Map<String, dynamic> ok(Map<String, dynamic> data) =>
    {'errCode': 0, 'data': data};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'cloud hit opens real chat with validated context without local lookup',
      (tester) async {
    var lookups = 0;
    var chats = 0;
    final navigation = ChatHistoryMessageNavigation(
      currentSession: () => 'owner',
      currentChat: (_) => null,
      findConversation: (id) async => ConversationInfo(conversationID: id),
      contextApi: api((_) async => ok(around())),
      findMessage: (_, __) async {
        lookups++;
        return null;
      },
      startChat: (_, target, ___) async {
        expect(target, isA<SearchChatTarget>());
        expect(target.textElem?.content, '<b>message 120</b>');
        chats++;
      },
    );
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => navigation.open(context,
                        conversationID: 'sg_test',
                        message: hit(),
                        isEntryCurrent: () => true),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchContextPageView), findsNothing);
    expect(lookups, 0);
    expect(chats, 1);
    expect(find.text('Open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('chat window uses HTTP bidirectional cursors then returns to SDK latest',
      () async {
    final service = api((body) async => ok(body['cursor'] == null
        ? around()
        : more(body['cursor'] == 'b1' ? 'before' : 'after',
            body['cursor'] == 'b1' ? [118] : [122])));
    final window = SearchChatWindow(hit(), service, await service.fetch(hit()));
    var rows = <Message>[];
    var sdkCalls = 0;
    Future<AdvancedMessage> read(
        {required int count, Message? startMsg}) async {
      sdkCalls++;
      return AdvancedMessage(
          messageList: [Message.fromJson(msg(200))], isEnd: true);
    }

    final loader = ChatHistoryLoader(
        fetch: read,
        fetchNewer: read,
        messages: () => rows,
        replace: (next, _, __) => rows = next,
        removedIDs: {},
        onStateChanged: () {});
    expect(await loader.jumpTo(SearchChatTarget(window)), isTrue);
    expect(rows.map((m) => m.seq), [119, 120, 121]);
    await loader.loadOlder();
    await loader.loadNewer();
    expect(rows.map((m) => m.seq), [118, 119, 120, 121, 122]);
    expect(sdkCalls, 0);
    await loader.returnToLatest();
    expect(rows.map((m) => m.seq), [200]);
    expect(sdkCalls, 1);
  });
  test(
      'around and both directions keep anchor and ascending order through empty gaps',
      () async {
    final requests = <Map<String, dynamic>>[];
    final controller = SearchContextController(hit(), api: api((body) async {
      requests.add(body);
      switch (body['cursor']) {
        case null:
          return ok(around());
        case 'b1':
          return ok(more('before', [], next: 'b2', end: false));
        case 'b2':
          return ok(more('before', [117, 118, 119]));
        case 'a1':
          return ok(more('after', [121, 122, 123]));
        default:
          throw StateError('unexpected cursor');
      }
    }));
    await controller.reload();
    expect(requests.first, {
      'conversationID': 'sg_test',
      'seq': 120,
      'serverMsgID': 's120',
      'before': 20,
      'after': 20
    });
    await controller.more(true);
    await controller.more(false);
    expect(controller.messages.map((m) => m.seq),
        [117, 118, 119, 120, 121, 122, 123]);
    expect(controller.beforeEnd && controller.afterEnd, isTrue);
    expect(requests[1],
        {'conversationID': 'sg_test', 'cursor': 'b1', 'limit': 20});
    await controller.more(true);
    expect(requests.length, 4);
    controller.dispose();
  });
  for (final code in [1001, 1002, 404, 409, 410, 1501]) {
    test('error $code removes previous context and stops pagination', () async {
      var calls = 0;
      final controller = SearchContextController(hit(),
          api: api(
              (_) async => calls++ == 0 ? ok(around()) : {'errCode': code}));
      await controller.reload();
      await controller.more(true);
      expect(controller.errorCode, code);
      expect(controller.messages, isEmpty);
      expect(controller.initialized, isFalse);
      await controller.more(false);
      expect(calls, 2);
      controller.dispose();
    });
  }
  test('429 retains context and retries original cursor', () async {
    var limited = true;
    final controller = SearchContextController(hit(), api: api((body) async {
      if (body['cursor'] == null) return ok(around());
      expect(body['cursor'], 'b1');
      return limited ? {'errCode': 429} : ok(more('before', [118]));
    }));
    await controller.reload();
    await controller.more(true);
    expect(controller.messages.length, 3);
    expect(controller.errorCode, 429);
    limited = false;
    await controller.more(true);
    expect(controller.messages.first.seq, 118);
    expect(controller.errorCode, isNull);
    controller.dispose();
  });
  test('late request cannot restore context after account invalidation',
      () async {
    final pending = Completer<dynamic>();
    final controller =
        SearchContextController(hit(), api: api((_) => pending.future));
    final work = controller.reload();
    controller.invalidateSession();
    pending.complete(ok(around()));
    await work;
    expect(controller.messages, isEmpty);
    expect(controller.errorCode, 1501);
    controller.dispose();
  });
  test('wrong anchor and direction are rejected', () async {
    final wrong = around()..['anchorMessage'] = msg(121);
    await expectLater(api((_) async => ok(wrong)).fetch(hit()),
        throwsA(isA<SearchApiException>()));
    final direction = around()..['direction'] = 'after';
    await expectLater(
        api((_) async => ok(direction)).fetch(hit()), throwsFormatException);
  });
  for (final brightness in Brightness.values) {
    testWidgets('read-only context renders full plain text in $brightness',
        (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('flutter_openim_sdk'), (call) async {
        calls.add(call);
        throw StateError('No SDK calls allowed');
      });
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: SearchContextPageView(
              hit: hit(), api: api((_) async => ok(around())))));
      await tester.pumpAndSettle();
      expect(find.text('<b>message 120</b>'), findsOneWidget);
      expect(find.text('Search match'), findsOneWidget);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('flutter_openim_sdk'), null);
    });
  }
}
