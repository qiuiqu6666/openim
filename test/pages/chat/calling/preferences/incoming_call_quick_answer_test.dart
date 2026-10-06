import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';
import 'package:openim_live/src/pages/single/widgets/call_state.dart';
import 'package:openim_live/src/pages/single/widgets/controls.dart';
import 'package:openim_live/src/session/single_call_session.dart';
import 'package:openim_live/src/widgets/incoming_call/incoming_call_quick_answer_sheet.dart';
import 'package:rxdart/rxdart.dart';

class _Probe {
  int credentials = 0, connections = 0, rejects = 0, timeouts = 0, closes = 0;
}

class _IncomingView extends SignalView {
  _IncomingView({
    required GlobalKey<_IncomingState> key,
    required PublishSubject<CallEvent> events,
    required ValueNotifier<IncomingCallPreferences> preferences,
    required this.probe,
    CallType callType = CallType.audio,
    Duration deadline = const Duration(seconds: 30),
  }) : super(
          key: key,
          callType: callType,
          initState: CallState.beCalled,
          roomID: 'quick-answer-room',
          userID: 'peer',
          callEventSubject: events,
          autoPickup: false,
          incomingCallPreferences: preferences,
          ringingTimeout: deadline,
          onTapPickup: () async {
            probe.credentials++;
            return SignalingCertificate.fromJson({
              'roomID': 'quick-answer-room',
              'token': 'local-test-token',
              'liveURL': 'https://unused.test',
            });
          },
          onTapReject: () async => probe.rejects++,
          onTimeout: () async => probe.timeouts++,
          onClose: () => probe.closes++,
          onSyncUserInfo: (_) async => UserInfo(
            userID: 'peer',
            nickname: '真实来电联系人以及需要正确换行的超长联系人名称',
          ),
        );
  final _Probe probe;

  @override
  _IncomingState createState() => _IncomingState();
}

class _IncomingState extends SignalState<_IncomingView> {
  @override
  Future<void> connect(CallAttempt attempt) async {
    if (attempt.isCurrent) {
      widget.probe.connections++;
      session.peerConnected();
    }
  }

  @override
  Future<void> releaseMedia() async {}

  @override
  bool existParticipants() => false;
}

Widget _host(Widget child, {bool dark = false, double scale = 1}) =>
    ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: page!,
        ),
        home: Scaffold(
          body: Stack(children: [const Text('existing conversation'), child]),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  const pip = MethodChannel('openim_call_pip');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late PublishSubject<CallEvent> events;
  late ValueNotifier<IncomingCallPreferences> preferences;
  late GlobalKey<_IncomingState> callKey;
  late _Probe probe;

  setUp(() {
    Get.testMode = true;
    events = PublishSubject<CallEvent>();
    preferences = ValueNotifier(const IncomingCallPreferences());
    callKey = GlobalKey<_IncomingState>();
    probe = _Probe();
    messenger.setMockMethodCallHandler(pip, (call) async {
      if (call.method == 'configure') {
        return {'supported': false, 'ready': false};
      }
      return true;
    });
    messenger.setMockMethodCallHandler(permissions, (call) async {
      if (call.method == 'requestPermissions') {
        return {
          for (final permission in call.arguments as List)
            permission:
                1, // Granted, without displaying a device permission UI.
        };
      }
      if (call.method == 'checkPermissionStatus') return 1;
      return false;
    });
  });

  tearDown(() async {
    await events.close();
    preferences.dispose();
    messenger.setMockMethodCallHandler(permissions, null);
    messenger.setMockMethodCallHandler(pip, null);
    Get.reset();
  });

  Widget view({CallType type = CallType.audio, Duration? deadline}) =>
      _IncomingView(
        key: callKey,
        events: events,
        preferences: preferences,
        probe: probe,
        callType: type,
        deadline: deadline ?? const Duration(seconds: 30),
      );

  for (final dark in [false, true]) {
    testWidgets('quick answer fits narrow safe area and large text, dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(view(), dark: dark, scale: 2));
      await tester.pump();
      expect(find.byType(IncomingCallQuickAnswerSheet), findsOneWidget);
      expect(find.byType(ControlsView), findsNothing);
      for (final text in [StrRes.pickUp, StrRes.reject, '打开通话']) {
        final action = find.text(text);
        expect(action, findsOneWidget);
        final rect = tester.getRect(action);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.bottom, lessThanOrEqualTo(616));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'preference changes preserve the current call and its answer path',
      (tester) async {
    preferences.value = const IncomingCallPreferences(quickAnswerPopup: false);
    await tester.pumpWidget(_host(view()));
    await tester.pump();
    final session = callKey.currentState!.session;
    expect(find.byType(ControlsView), findsOneWidget);
    expect(find.byType(IncomingCallQuickAnswerSheet), findsNothing);
    preferences.value = const IncomingCallPreferences();
    await tester.pump();
    expect(find.byType(IncomingCallQuickAnswerSheet), findsOneWidget);
    expect(identical(callKey.currentState!.session, session), isTrue);
    await tester.tap(find.text('打开通话'));
    await tester.pump();
    expect(find.byType(ControlsView), findsOneWidget);
    expect(identical(callKey.currentState!.session, session), isTrue);
    expect(probe.credentials, 0);
    await tester.pumpWidget(const SizedBox());
    preferences.value = const IncomingCallPreferences(quickAnswerPopup: false);
    expect(tester.takeException(), isNull,
        reason: 'The closed view has detached its preference listener');
  });

  for (final type in [CallType.audio, CallType.video]) {
    testWidgets('$type quick answer enters the existing session exactly once',
        (tester) async {
      await tester.pumpWidget(_host(view(type: type)));
      await tester.pump();
      final session = callKey.currentState!.session;
      await tester.tap(find.text(StrRes.pickUp));
      await tester.tap(find.text(StrRes.pickUp));
      await tester.pump();
      await tester.pump();
      expect(probe.credentials, 1);
      expect(probe.connections, 1);
      expect(identical(callKey.currentState!.session, session), isTrue);
      expect(find.byType(IncomingCallQuickAnswerSheet), findsNothing);
      expect(find.byType(ControlsView), findsOneWidget);
      expect(session.connected, isTrue);
      final ending = session.end(CallState.hangup, notifyPeer: false);
      await tester.pump();
      await ending;
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('quick reject produces one terminal operation', (tester) async {
    await tester.pumpWidget(_host(view()));
    await tester.pump();
    await tester.tap(find.text(StrRes.reject));
    await tester.tap(find.text(StrRes.reject));
    await tester.pump();
    expect(probe.rejects, 1);
    expect(probe.closes, 1);
    expect(probe.credentials, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('expanding quick answer keeps the original ringing deadline',
      (tester) async {
    await tester.pumpWidget(_host(view(deadline: const Duration(seconds: 2))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('打开通话'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(probe.timeouts, 1);
    expect(probe.closes, 1);
    expect(probe.credentials, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
