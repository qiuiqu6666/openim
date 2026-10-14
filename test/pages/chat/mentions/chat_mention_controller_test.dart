import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/mentions/chat_mention_controller.dart';

Message mention(int seq, List<String> targets, {String sender = 'peer'}) =>
    Message.fromJson({
      'clientMsgID': '$seq',
      'seq': seq,
      'sendTime': seq,
      'sendID': sender,
      'isRead': true,
      'atTextElem': {'atUserList': targets, 'text': 'hello'}
    });

void main() {
  test(
      'entry survives read reset; includes everyone and me, excludes old/self/other',
      () async {
    final controller = ChatMentionController(
        userID: () => 'me',
        isClosed: () => false,
        search: (_) async => [
              mention(100, ['atAllTag']),
              mention(99, ['me']),
              mention(98, ['other']),
              mention(97, ['me'], sender: 'me'),
              mention(90, ['me'])
            ],
        focus: (_) async => true);
    await controller.load(unreadCount: 10, latestSeq: 100, hasMention: true);
    expect(controller.pending.map((m) => m.seq), [99, 100]);
    expect(await controller.jump(), isTrue);
    controller.add(mention(99, ['me']));
    expect(controller.pending.map((m) => m.seq), [100]);
  });

  test('search pages past mentions of other members', () async {
    final pages = <int>[];
    final controller = ChatMentionController(
        userID: () => 'me',
        isClosed: () => false,
        search: (page) async {
          pages.add(page);
          return page == 1
              ? List.generate(50, (i) => mention(200 - i, ['other']))
              : [
                  mention(150, ['me'])
                ];
        },
        focus: (_) async => true);
    await controller.load(unreadCount: 100, latestSeq: 200, hasMention: true);
    expect(pages, [1, 2]);
    expect(controller.pending.single.seq, 150);
  });

  test('failed jump retains target and double tap does not start another jump',
      () async {
    final result = Completer<bool>();
    var calls = 0;
    final controller = ChatMentionController(
        userID: () => 'me',
        isClosed: () => false,
        search: (_) async => [],
        focus: (_) {
          calls++;
          return result.future;
        });
    controller.add(mention(1, ['me']));
    final jump = controller.jump();
    expect(await controller.jump(), isFalse);
    result.complete(false);
    expect(await jump, isFalse);
    expect(controller.pending.length, 1);
    expect(calls, 1);
    expect(controller.busy.value, isFalse);
  });

  test('closed route ignores late search and removed targets do not return',
      () async {
    var closed = false;
    final response = Completer<List<Message>>();
    final controller = ChatMentionController(
        userID: () => 'me',
        isClosed: () => closed,
        search: (_) => response.future,
        focus: (_) async => true);
    controller.remove('1');
    controller.add(mention(1, ['me']));
    expect(controller.pending, isEmpty);
    final load =
        controller.load(unreadCount: 1, latestSeq: 1, hasMention: true);
    closed = true;
    response.complete([
      mention(1, ['me'])
    ]);
    await load;
    expect(controller.pending, isEmpty);
  });
}
