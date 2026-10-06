import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/src/models/call_types.dart';
import 'package:openim_live/src/pages/single/widgets/controls.dart';
import 'package:openim_live/src/widgets/call_compact_surface.dart';
import 'package:openim_live/src/widgets/call_surface/call_full_screen_surface.dart';
import 'package:openim_live/src/widgets/incoming_call/incoming_call_quick_answer_sheet.dart';

import 'support/call_termination_fixture.dart';

void expectNoCallSurface() {
  expect(find.byType(CallFullScreenSurface), findsNothing);
  expect(find.byType(CallCompactSurface), findsNothing);
  expect(find.byType(IncomingCallQuickAnswerSheet), findsNothing);
  expect(find.byType(ControlsView), findsNothing);
  expect(find.byWidgetPredicate((widget) => widget is PopScope), findsNothing);
}

Future<void> expectUsableConversation(WidgetTester tester,
    TerminationFixture fixture, TerminationState owner) async {
  expectNoCallSurface();
  expect(owner.session.active, isFalse);
  expect(fixture.probe.closes, 0,
      reason: 'Resource and signaling gates are still pending');
  await tester
      .tap(find.byKey(const ValueKey('underlying-conversation-action')));
  await frames(tester);
  expect(fixture.probe.underlyingTaps, 1);
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(find.text('conversation list'), findsOneWidget);
  expect(find.text('existing conversation'), findsNothing);
  expect(fixture.probe.closes, 0,
      reason: 'Back navigation must not prematurely release call admission');
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TerminationNativeBoundary native;
  setUp(() {
    native = TerminationNativeBoundary()..install();
  });
  tearDown(() => native.uninstall());

  for (final type in CallType.values) {
    for (final connected in [false, true]) {
      testWidgets(
          '$type ${connected ? 'connected hangup' : 'outgoing cancel'} removes fullscreen before slow cleanup',
          (tester) async {
        final fixture = TerminationFixture(type: type);
        await fixture.mount(tester);
        final owner = fixture.state;
        try {
          if (connected) {
            owner.session.peerConnected();
            await frames(tester);
          }
          expect(find.byType(CallFullScreenSurface), findsOneWidget);
          expect(owner.session.connected, connected);
          await tester
              .tap(find.text(connected ? StrRes.hangUp : StrRes.cancel));
          await frames(tester);
          final ending = owner.endActive();
          var finished = false;
          unawaited(ending.then((_) => finished = true));
          expect(fixture.probe.releases, 1);
          expect(fixture.probe.signals, [connected ? 'hangup' : 'cancel']);
          expect(finished, isFalse);
          expect(fixture.probe.releaseGate.isCompleted, isFalse);
          expect(fixture.probe.signalGate.isCompleted, isFalse);
          expect(identical(ending, owner.endActive()), isTrue);
          owner.session.peerAccepted();
          owner.session.peerConnected();
          owner.onTapMaximize();
          fixture.remote(CallState.beAccepted);
          await frames(tester);
          await expectUsableConversation(tester, fixture, owner);

          // Settling either boundary alone cannot close or release admission.
          fixture.probe.releaseGate.complete();
          await frames(tester);
          expect(finished, isFalse);
          expect(fixture.probe.closes, 0);
          fixture.probe.signalGate.complete();
          await frames(tester);
          await ending;
          expect(finished, isTrue);
          expect(fixture.probe.closes, 1);
          expect(fixture.probe.releases, 1);
          expect(fixture.probe.signals, [connected ? 'hangup' : 'cancel']);
          expect(fixture.probe.starts, connected ? 1 : 0);
          if (connected) {
            expect(fixture.probe.hangupDetails.single.$2, isTrue);
          }
        } finally {
          await fixture.dispose(tester, owner);
        }
      });
    }
  }

  for (final surface in [
    'compact',
    'entering PiP',
    'active PiP',
    'quick answer'
  ]) {
    testWidgets('$surface disappears on termination without an inert overlay',
        (tester) async {
      final incoming = surface == 'quick answer';
      final fixture = TerminationFixture(
          initial: incoming ? CallState.beCalled : CallState.call,
          quickAnswer: incoming);
      await fixture.mount(tester);
      final owner = fixture.state;
      try {
        if (incoming) {
          expect(find.byType(IncomingCallQuickAnswerSheet), findsOneWidget);
          await tester.tap(find.text(StrRes.reject));
        } else {
          owner.session.peerConnected();
          await frames(tester);
          if (surface == 'compact') {
            await tester.tap(find.byTooltip('最小化'));
          } else {
            await tester.tap(find.byTooltip('桌面画中画'));
          }
          await frames(tester);
          if (surface == 'active PiP') {
            await native.nativePipState('active');
            await frames(tester);
            expect(owner.pictureInPicture.active, isTrue);
          }
          expect(find.byType(CallCompactSurface), findsOneWidget);
          unawaited(owner.endActive());
        }
        await frames(tester);
        expect(fixture.probe.releases, 1);
        expect(fixture.probe.signals, [incoming ? 'reject' : 'hangup']);
        await native.nativePipState('active');
        await native.nativePipState('restored');
        owner.onTapMaximize();
        await frames(tester);
        await expectUsableConversation(tester, fixture, owner);
        fixture.probe.completeCleanup();
        await frames(tester);
        expect(fixture.probe.closes, 1);
        expect(fixture.probe.releases, 1);
      } finally {
        await fixture.dispose(tester, owner);
      }
    });
  }

  for (final outcome in [
    CallState.beHangup,
    CallState.beRejected,
    CallState.beCanceled,
    CallState.timeout,
  ]) {
    testWidgets(
        'remote $outcome removes the surface and ignores late acceptance',
        (tester) async {
      final fixture = TerminationFixture();
      await fixture.mount(tester);
      final owner = fixture.state;
      try {
        if (outcome == CallState.beHangup) {
          owner.session.peerConnected();
          await frames(tester);
        }
        fixture.remote(outcome);
        await frames(tester);
        expect(owner.callState, outcome);
        expect(fixture.probe.releases, 1);
        fixture.remote(outcome);
        fixture.remote(CallState.beAccepted);
        owner.session.peerConnected();
        await frames(tester);
        expect(owner.callState, outcome);
        await expectUsableConversation(tester, fixture, owner);
        fixture.probe.completeCleanup();
        await frames(tester);
        expect(fixture.probe.closes, 1);
        expect(fixture.probe.releases, 1);
        if (outcome == CallState.beHangup) {
          expect(fixture.probe.signals, ['hangup']);
          expect(fixture.probe.hangupDetails.single.$2, isFalse);
        } else if (outcome == CallState.timeout) {
          expect(fixture.probe.signals, ['timeout']);
        } else {
          expect(fixture.probe.signals, isEmpty);
        }
      } finally {
        await fixture.dispose(tester, owner);
      }
    });
  }

  testWidgets('a failed connection exits immediately while error cleanup waits',
      (tester) async {
    final fixture = TerminationFixture();
    fixture.probe.failConnection = true;
    await fixture.mount(tester);
    final owner = fixture.state;
    try {
      expect(owner.callState, CallState.networkError);
      expect(fixture.probe.signals, ['error']);
      fixture.remote(CallState.beAccepted);
      owner.session.peerConnected();
      await frames(tester);
      await expectUsableConversation(tester, fixture, owner);
      fixture.probe.completeCleanup();
      await frames(tester);
      expect(fixture.probe.closes, 1);
      expect(fixture.probe.releases, 1);
      expect(fixture.probe.starts, 0);
    } finally {
      await fixture.dispose(tester, owner);
    }
  });

  testWidgets('cancel during connection cannot revive when connection finishes',
      (tester) async {
    final fixture = TerminationFixture();
    fixture.probe.connectionGate = Completer<void>();
    await fixture.mount(tester);
    final owner = fixture.state;
    try {
      expect(owner.callState, CallState.connecting);
      final ending = owner.endActive();
      await frames(tester);
      fixture.probe.connectionGate!.complete();
      fixture.remote(CallState.beAccepted);
      owner.session.peerConnected();
      await frames(tester);
      expect(owner.callState, CallState.cancel);
      expect(fixture.probe.starts, 0);
      await expectUsableConversation(tester, fixture, owner);
      fixture.probe.completeCleanup();
      await frames(tester);
      await ending;
      expect(fixture.probe.releases, 1);
      expect(fixture.probe.signals, ['cancel']);
      expect(fixture.probe.closes, 1);
    } finally {
      await fixture.dispose(tester, owner);
    }
  });
}
