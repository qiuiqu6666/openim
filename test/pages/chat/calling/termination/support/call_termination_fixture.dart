import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/src/models/call_types.dart';
import 'package:openim_live/src/models/incoming_call_preferences.dart';
import 'package:openim_live/src/pages/single/widgets/call_state.dart';
import 'package:openim_live/src/session/single_call_session.dart';
import 'package:rxdart/rxdart.dart';
// The plugin's generated wire codec decodes its real native toggle message.
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/messages.g.dart';

/// Gates the real session's native-media and terminal signaling boundaries.
/// No room connection, remote invitation, or production SDK replacement runs.
class TerminationProbe {
  final releaseGate = Completer<void>();
  final signalGate = Completer<void>();
  Completer<void>? connectionGate;
  bool failConnection = false;
  int credentials = 0, connects = 0, releases = 0, closes = 0;
  int starts = 0, underlyingTaps = 0;
  final signals = <String>[];
  final hangupDetails = <(int, bool)>[];

  Future<void> signal(String type) {
    signals.add(type);
    return signalGate.future;
  }

  void completeCleanup() {
    if (!releaseGate.isCompleted) releaseGate.complete();
    if (!signalGate.isCompleted) signalGate.complete();
    if (connectionGate?.isCompleted == false) connectionGate!.complete();
  }
}

class TerminationView extends SignalView {
  TerminationView({
    required GlobalKey<TerminationState> key,
    required this.probe,
    required PublishSubject<CallEvent> events,
    CallState initial = CallState.call,
    CallType type = CallType.audio,
    ValueNotifier<IncomingCallPreferences>? preferences,
  }) : super(
          key: key,
          callType: type,
          initState: initial,
          roomID: 'termination-test-room',
          userID: 'termination-test-peer',
          callEventSubject: events,
          autoPickup: false,
          incomingCallPreferences: preferences,
          ringingTimeout: const Duration(minutes: 5),
          onDial: () async {
            probe.credentials++;
            return localCertificate();
          },
          onTapPickup: () async {
            probe.credentials++;
            return localCertificate();
          },
          onTapCancel: () => probe.signal('cancel'),
          onTapReject: () => probe.signal('reject'),
          onTapHangup: (duration, positive) {
            probe.hangupDetails.add((duration, positive));
            return probe.signal('hangup');
          },
          onTimeout: () => probe.signal('timeout'),
          onError: (_, __) => probe.signal('error'),
          onClose: () => probe.closes++,
          onStartCalling: () => probe.starts++,
          onSyncUserInfo: (_) async =>
              UserInfo(userID: 'termination-test-peer', nickname: '通话联系人'),
        );

  final TerminationProbe probe;

  static SignalingCertificate localCertificate() =>
      SignalingCertificate.fromJson({
        'roomID': 'termination-test-room',
        'liveURL': 'https://unused.test',
        'token': 'local-test-token',
      });

  @override
  TerminationState createState() => TerminationState();
}

class TerminationState extends SignalState<TerminationView> {
  @override
  Future<void> connect(CallAttempt attempt) async {
    widget.probe.connects++;
    await widget.probe.connectionGate?.future;
    if (!attempt.isCurrent) return;
    if (widget.probe.failConnection) {
      throw StateError('Local test connection failed');
    }
  }

  @override
  Future<void> releaseMedia() {
    widget.probe.releases++;
    return widget.probe.releaseGate.future;
  }

  @override
  bool existParticipants() => false;
}

class TerminationFixture {
  TerminationFixture({
    this.initial = CallState.call,
    this.type = CallType.audio,
    bool quickAnswer = false,
  }) : preferences = ValueNotifier(
            IncomingCallPreferences(quickAnswerPopup: quickAnswer));

  final CallState initial;
  final CallType type;
  final probe = TerminationProbe();
  final callKey = GlobalKey<TerminationState>();
  final navigatorKey = GlobalKey<NavigatorState>();
  final events = PublishSubject<CallEvent>();
  final ValueNotifier<IncomingCallPreferences> preferences;
  TerminationState get state => callKey.currentState!;

  Widget host() => ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          navigatorKey: navigatorKey,
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: const Scaffold(body: Text('conversation list')),
        ),
      );

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    unawaited(navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('existing conversation')),
        body: Stack(fit: StackFit.expand, children: [
          Positioned.fill(
            child: Center(
              child: TextButton(
                key: const ValueKey('underlying-conversation-action'),
                onPressed: () => probe.underlyingTaps++,
                child: const Text('conversation action'),
              ),
            ),
          ),
          TerminationView(
            key: callKey,
            probe: probe,
            events: events,
            initial: initial,
            type: type,
            preferences: preferences,
          ),
        ]),
      ),
    )));
    await frames(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await frames(tester);
  }

  void remote(CallState outcome) {
    events.add(CallEvent(
      outcome,
      SignalingInfo(
        userID: 'termination-test-peer',
        invitation: InvitationInfo(roomID: 'termination-test-room'),
      ),
    ));
  }

  Future<void> dispose(WidgetTester tester, TerminationState owner) async {
    probe.completeCleanup();
    final ending = owner.endActive(notifyPeer: false);
    await frames(tester);
    await ending;
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
    await events.close();
    preferences.dispose();
  }
}

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

class TerminationNativeBoundary {
  static const pip = MethodChannel('openim_call_pip');
  static const permissions =
      MethodChannel('flutter.baseflow.com/permissions/methods');
  static const wakelock =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final wakelockChanges = <bool>[];
  String? pipSession;
  Completer<void>? disableWakelock;

  void install() {
    Get.testMode = true;
    messenger.setMockMethodCallHandler(permissions, (call) async {
      if (call.method == 'requestPermissions') {
        return {for (final permission in call.arguments as List) permission: 1};
      }
      if (call.method == 'checkPermissionStatus') return 1;
      return false;
    });
    messenger.setMockMethodCallHandler(pip, (call) async {
      if (call.method == 'configure') {
        pipSession = (call.arguments as Map)['session'] as String;
        return {'supported': true, 'ready': true};
      }
      return true;
    });
    messenger.setMockMessageHandler(wakelock, (data) async {
      final args =
          WakelockPlusApi.pigeonChannelCodec.decodeMessage(data) as List;
      final enabled = (args.first as ToggleMessage).enable!;
      wakelockChanges.add(enabled);
      if (!enabled) await disableWakelock?.future;
      return const StandardMessageCodec().encodeMessage([null]);
    });
  }

  Future<void> nativePipState(String phase) async {
    final reply = Completer<void>();
    messenger.handlePlatformMessage(
      pip.name,
      pip.codec.encodeMethodCall(MethodCall('state', {
        'session': pipSession,
        'phase': phase,
      })),
      (_) => reply.complete(),
    );
    await reply.future;
  }

  void uninstall() {
    messenger.setMockMethodCallHandler(permissions, null);
    messenger.setMockMethodCallHandler(pip, null);
    messenger.setMockMessageHandler(wakelock, null);
    Get.reset();
  }
}
