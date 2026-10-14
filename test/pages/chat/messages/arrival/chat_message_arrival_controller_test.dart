import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/messages/arrival/chat_message_arrival_controller.dart';
import 'package:openim/pages/chat/messages/arrival/chat_message_arrival_tokens.dart';

Message _incoming(String? id, {String sender = 'peer', int? type}) => Message(
      clientMsgID: id,
      sendID: sender,
      contentType: type ?? MessageType.text,
    );

void main() {
  late ChatMessageArrivalController arrivals;
  late String currentUser;
  late int changes;
  late bool disposed;

  setUp(() {
    currentUser = 'self';
    changes = 0;
    disposed = false;
    arrivals = ChatMessageArrivalController(currentUserID: () => currentUser);
    arrivals.addListener(() => changes++);
  });

  tearDown(() {
    if (!disposed) arrivals.dispose();
  });

  test('only an eligible live arrival can request an entrance', () {
    arrivals.register(_incoming('covered-route'), enabled: false);
    arrivals.register(_incoming('live'), enabled: true);

    expect(arrivals.isEntering('covered-route'), isFalse);
    expect(arrivals.takePending({'covered-route', 'live'}), ['live']);
    expect(arrivals.isEntering('live'), isTrue);
    expect(changes, 1);
  });

  test('typing, notifications and malformed IDs never hide a visible row', () {
    final excluded = [
      _incoming('typing', type: MessageType.typing),
      _incoming('notification', type: 1000),
      _incoming('system', type: 2000),
      _incoming(null),
      _incoming(''),
      Message(clientMsgID: 'missing-type', sendID: 'peer'),
    ];
    for (final message in excluded) {
      arrivals.register(message, enabled: true);
    }

    expect(
        arrivals.takePending(
            {'typing', 'notification', 'system', '', 'missing-type'}),
        isEmpty);
    for (final id in ['typing', 'notification', 'system', '', 'missing-type']) {
      expect(arrivals.isEntering(id), isFalse, reason: id);
    }
    expect(changes, 0);
  });

  test('local sends and current-account echoes do not enter again', () {
    arrivals.register(_incoming('local', sender: 'self'), enabled: true);
    currentUser = 'another-self';
    arrivals.register(_incoming('echo', sender: 'another-self'), enabled: true);
    arrivals.register(_incoming('remote'), enabled: true);

    expect(arrivals.isEntering('local'), isFalse);
    expect(arrivals.isEntering('echo'), isFalse);
    expect(arrivals.takePending({'local', 'echo', 'remote'}), ['remote']);
    expect(changes, 1);
  });

  test('duplicate delivery and viewport rebuild claim one entrance only', () {
    arrivals.register(_incoming('live'), enabled: true);
    arrivals.register(_incoming('live'), enabled: true);

    expect(arrivals.takePending({'unrelated-history'}), isEmpty);
    expect(arrivals.takePending({'live'}), ['live']);
    expect(arrivals.isEntering('live'), isTrue);

    // A sliver remount or another SDK callback must reuse the view's motion.
    arrivals.register(_incoming('live'), enabled: true);
    expect(arrivals.takePending({'live'}), isEmpty);
    expect(arrivals.isEntering('live'), isTrue);
    expect(changes, 1);
  });

  test('history, receipt rebuilds and finished rows do not create entrances',
      () {
    arrivals.register(_incoming('live'), enabled: true);
    expect(arrivals.takePending({'live'}), ['live']);
    arrivals.finish('live');

    // Passing rendered IDs is a claim operation, not a list-difference trigger.
    for (var rebuild = 0; rebuild < 3; rebuild++) {
      expect(arrivals.takePending({'history', 'live', 'receipt-updated'}),
          isEmpty);
    }
    expect(arrivals.isEntering('live'), isFalse);
    expect(arrivals.isEntering('history'), isFalse);
    expect(arrivals.isEntering('receipt-updated'), isFalse);
    expect(changes, 1);
  });

  test('a same-frame burst displays every row without queued entrances', () {
    final burst = List.generate(24, (index) => 'burst-$index');
    for (final id in burst) {
      arrivals.register(_incoming(id), enabled: true);
    }

    expect(arrivals.takePending(burst.toSet()), isEmpty);
    for (final id in burst) {
      expect(arrivals.isEntering(id), isFalse, reason: id);
    }
    expect(arrivals.hasEntering, isFalse);
    expect(changes, 2,
        reason:
            'The first pending entrance is registered then cancelled once.');
  });

  testWidgets(
      'cancel drops unpainted pending rows but protects claimed rows until paint',
      (tester) async {
    arrivals.register(_incoming('active'), enabled: true);
    expect(arrivals.takePending({'active'}), ['active']);
    // Keep a claimed row as if its final paint is waiting behind a slow frame.
    await tester.pump(ChatMessageArrivalTokens.quietPeriod);
    arrivals.register(_incoming('pending'), enabled: true);
    final beforeCancel = changes;

    arrivals.cancel();

    expect(arrivals.takePending({'active', 'pending'}), isEmpty);
    expect(arrivals.isEntering('pending'), isFalse);
    expect(arrivals.isCancelled('pending'), isFalse);
    expect(arrivals.isEntering('active'), isTrue);
    expect(arrivals.isCancelled('active'), isTrue);
    expect(changes, beforeCancel + 1);

    // The view finishes only after the expanded row has really painted.
    arrivals.finish('active', notify: true);
    expect(arrivals.isEntering('active'), isFalse);
    expect(arrivals.isCancelled('active'), isFalse);
    expect(changes, beforeCancel + 2);
    await tester.pump(ChatMessageArrivalTokens.quietPeriod);
  });

  testWidgets(
      'cancel before the first paint leaves no receipt barrier or queued motion',
      (tester) async {
    arrivals.register(_incoming('not-mounted'), enabled: true);
    arrivals.cancel();

    expect(arrivals.takePending({'not-mounted'}), isEmpty);
    expect(arrivals.isEntering('not-mounted'), isFalse);
    expect(arrivals.isCancelled('not-mounted'), isFalse);

    await tester.pump(ChatMessageArrivalTokens.quietPeriod);
    arrivals.register(_incoming('next-live'), enabled: true);
    expect(arrivals.takePending({'not-mounted', 'next-live'}), ['next-live']);
    expect(arrivals.isCancelled('next-live'), isFalse);
    await tester.pump(ChatMessageArrivalTokens.quietPeriod);
  });

  test('finishing a row before claim also removes its pending entrance', () {
    arrivals.register(_incoming('deleted'), enabled: true);
    arrivals.finish('deleted');

    expect(arrivals.takePending({'deleted'}), isEmpty);
    expect(arrivals.isEntering('deleted'), isFalse);
    expect(arrivals.isCancelled('deleted'), isFalse);
  });

  testWidgets('deleted pending rows do not prevent later live entrances',
      (tester) async {
    for (var index = 0; index < 4; index++) {
      arrivals.register(_incoming('deleted-$index'), enabled: true);
    }
    arrivals.retain({});
    await tester.pump(ChatMessageArrivalTokens.quietPeriod);
    arrivals.register(_incoming('next-live'), enabled: true);
    expect(arrivals.takePending({'next-live'}), ['next-live']);
    expect(arrivals.isEntering('deleted-0'), isFalse);
    await tester.pump(ChatMessageArrivalTokens.quietPeriod);
  });

  test('disposing the route ignores late delivery and animation completion',
      () {
    arrivals.register(_incoming('active'), enabled: true);
    expect(arrivals.takePending({'active'}), ['active']);
    arrivals.register(_incoming('pending'), enabled: true);
    final beforeDispose = changes;

    arrivals.dispose();
    disposed = true;
    arrivals.register(_incoming('late'), enabled: true);
    arrivals.cancel();
    arrivals.finish('active', notify: true);

    expect(arrivals.takePending({'active', 'pending', 'late'}), isEmpty);
    for (final id in ['active', 'pending', 'late']) {
      expect(arrivals.isEntering(id), isFalse, reason: id);
      expect(arrivals.isCancelled(id), isFalse, reason: id);
    }
    expect(changes, beforeDispose);
  });

  testWidgets('continuous traffic cancels once and quiet traffic enters again',
      (tester) async {
    arrivals.register(_incoming('first'), enabled: true);
    expect(arrivals.takePending({'first'}), ['first']);
    await tester.pump(const Duration(milliseconds: 80));
    arrivals.register(_incoming('second'), enabled: true);
    expect(arrivals.isEntering('first'), isTrue);
    expect(arrivals.isCancelled('first'), isTrue);
    expect(arrivals.isEntering('second'), isFalse);
    final afterCancellation = changes;
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      arrivals.register(_incoming('burst-$i'), enabled: true);
      expect(arrivals.isEntering('burst-$i'), isFalse);
    }
    expect(changes, afterCancellation,
        reason:
            'Waiting for full paint must not publish repeated cancellation.');
    arrivals.finish('first', notify: true);
    expect(arrivals.hasEntering, isFalse);
    await tester.pump(ChatMessageArrivalTokens.quietPeriod);
    arrivals.register(_incoming('after-quiet'), enabled: true);
    expect(arrivals.takePending({'after-quiet'}), ['after-quiet']);
    await tester.pump(ChatMessageArrivalTokens.quietPeriod);
  });

  testWidgets('excluded traffic does not prolong the quiet interval',
      (tester) async {
    arrivals.register(_incoming('first'), enabled: true);
    expect(arrivals.takePending({'first'}), ['first']);
    arrivals.finish('first');
    await tester.pump(const Duration(milliseconds: 400));
    arrivals.register(_incoming('self', sender: 'self'), enabled: true);
    arrivals.register(_incoming('covered'), enabled: false);
    arrivals.register(_incoming('typing', type: MessageType.typing),
        enabled: true);
    await tester.pump(const Duration(milliseconds: 200));
    arrivals.register(_incoming('after-quiet'), enabled: true);
    expect(arrivals.takePending({'after-quiet'}), ['after-quiet']);
    await tester.pump(ChatMessageArrivalTokens.quietPeriod);
  });
}
