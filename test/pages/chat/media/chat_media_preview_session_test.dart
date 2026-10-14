import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/chat_media_preview_session.dart';

void main() {
  test(
      'repeated taps across bubbles cannot queue viewers while opening or open',
      () async {
    final session = ChatMediaPreviewSession();
    final prepared = Completer<void>();
    final dismissed = Completer<void>();
    var opened = 0;
    final first = session.run(() async {
      await prepared.future;
      opened++;
      await dismissed.future;
    });
    for (var tap = 0; tap < 10; tap++) {
      await session.run(() async => opened++);
    }
    expect(opened, 0);
    prepared.complete();
    await Future<void>.delayed(Duration.zero);
    await session.run(() async => opened++);
    expect(opened, 1);
    dismissed.complete();
    await first;
    await session.run(() async => opened++);
    expect(opened, 2);
  });

  test('slow SDK stops pagination and late completion cannot open again',
      () async {
    final session = ChatMediaPreviewSession();
    final sdk = Completer<List<Message>>();
    late bool Function() continueLoading;
    final history = await session.loadHistory((current) {
      continueLoading = current;
      return sdk.future;
    }, wait: const Duration(milliseconds: 1));
    expect(history, isEmpty);
    expect(continueLoading(), isFalse);
    sdk.complete([Message()]);
    await Future<void>.delayed(Duration.zero);
    expect(history, isEmpty);
  });

  test('fast history remains available and SDK failures fall back', () async {
    final session = ChatMediaPreviewSession();
    final message = Message();
    expect(await session.loadHistory((_) async => [message]), [message]);
    expect(await session.loadHistory((_) async => throw StateError('SDK')),
        isEmpty);
  });

  test('SDK error arriving after timeout is contained', () async {
    final session = ChatMediaPreviewSession();
    final sdk = Completer<List<Message>>();
    expect(
        await session.loadHistory((_) => sdk.future,
            wait: const Duration(milliseconds: 1)),
        isEmpty);
    sdk.completeError(StateError('late SDK failure'));
    await Future<void>.delayed(Duration.zero);
  });

  test('opening failure releases session for retry', () async {
    final session = ChatMediaPreviewSession();
    await expectLater(
        session.run(() async => throw StateError('open')), throwsStateError);
    var opened = false;
    await session.run(() async => opened = true);
    expect(opened, isTrue);
  });
}
