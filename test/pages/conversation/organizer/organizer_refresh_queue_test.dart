import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/organizer/organizer_refresh_queue.dart';

void main() {
  test('closed session discards pending manual refresh', () async {
    var current = true;
    final gate = Completer<void>();
    var calls = 0;
    final queue = OrganizerRefreshQueue(
      isCurrent: () => current,
      run: (_, __) async {
        calls++;
        await gate.future;
      },
    );
    final first = queue.request(userInitiated: false, source: 'resume');
    final manual = queue.request(userInitiated: true, source: 'manual');
    current = false;
    gate.complete();
    await Future.wait([first, manual]);
    expect(calls, 1);
  });

  test('automatic callbacks coalesce without inheriting manual feedback',
      () async {
    final firstDone = Completer<void>();
    final intents = <bool>[];
    final queue = OrganizerRefreshQueue(
      isCurrent: () => true,
      run: (manual, _) async {
        intents.add(manual);
        if (intents.length == 1) await firstDone.future;
      },
    );
    final first = queue.request(userInitiated: true, source: 'manual');
    final automatic = queue.request(userInitiated: false, source: 'resume');
    final reconnect = queue.request(userInitiated: false, source: 'reconnect');
    firstDone.complete();
    await Future.wait([first, automatic, reconnect]);
    expect(intents, [true, false]);
  });
}
