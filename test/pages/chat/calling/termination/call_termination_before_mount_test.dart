import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_live/src/live_client.dart';
import 'package:openim_live/src/pages/single/room.dart';

import 'support/call_termination_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TerminationNativeBoundary native;
  setUp(() {
    native = TerminationNativeBoundary()..install();
  });
  tearDown(() => native.uninstall());

  for (final initial in [CallState.call, CallState.beCalled]) {
    testWidgets(
        '$initial exit before first frame removes the real overlay without waiting for signaling',
        (tester) async {
      final fixture = TerminationFixture();
      final client = OpenIMLiveClient();
      final signalGate = Completer<void>();
      native.disableWakelock = Completer<void>();
      var signals = 0, closes = 0, credentials = 0, finished = false;
      bool start(String room) => client.start(
            fixture.navigatorKey.currentState!.overlay!.context,
            callEventSubject: fixture.events,
            roomID: room,
            initState: initial,
            callType: CallType.audio,
            inviterUserID: 'local-test-inviter',
            inviteeUserIDList: ['local-test-invitee'],
            onDialSingle: () async {
              credentials++;
              return TerminationView.localCertificate();
            },
            onTapCancel: () {
              signals++;
              return signalGate.future;
            },
            onTapReject: () {
              signals++;
              return signalGate.future;
            },
            onClose: () => closes++,
          );

      await tester.pumpWidget(fixture.host());
      try {
        expect(client.isBusy, isFalse);
        expect(start('before-mount-room'), isTrue);
        expect(client.hasConnection, isTrue);
        final ending = client.endActiveCall(reason: 'local-test-exit');
        unawaited(ending.then((_) => finished = true));
        expect(identical(ending, client.endActiveCall()), isTrue);
        expect(signals, 1);
        expect(start('must-be-rejected'), isFalse);
        await frames(tester);
        // Slow cancellation cannot let the inserted room mount on a later
        // frame, acquire media, or trap the user in an inert call surface.
        expect(find.byType(SingleRoomView), findsNothing);
        expect(find.text('conversation list'), findsOneWidget);
        expect(credentials, 0);
        expect(client.isBusy, isTrue);
        expect(client.currentRoomID, 'before-mount-room');
        expect(closes, 0);
        expect(finished, isFalse);

        signalGate.complete();
        await frames(tester);
        expect(signals, 1);
        expect(closes, 1);
        expect(native.wakelockChanges, [true, false]);
        expect(client.isBusy, isTrue,
            reason: 'Admission remains closed until native wakelock cleanup');
        expect(finished, isFalse);
        expect(start('still-cleaning'), isFalse);
        native.disableWakelock!.complete();
        await frames(tester);
        await ending;
        expect(finished, isTrue);
        expect(client.isBusy, isFalse);
        expect(client.currentRoomID, isNull);
        await client.endActiveCall();
        expect(signals, 1);
        expect(closes, 1);
        expect(find.byType(SingleRoomView), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        if (!signalGate.isCompleted) signalGate.complete();
        if (!native.disableWakelock!.isCompleted) {
          native.disableWakelock!.complete();
        }
        final ending = client.endActiveCall(notifyPeer: false);
        await frames(tester);
        await ending;
        await tester.pumpWidget(const SizedBox());
        await fixture.events.close();
        fixture.preferences.dispose();
      }
    });
  }
}
