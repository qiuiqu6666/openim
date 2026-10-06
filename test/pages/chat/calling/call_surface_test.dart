import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/src/models/call_types.dart';
import 'package:openim_live/src/pages/single/widgets/call_state.dart';
import 'package:openim_live/src/pages/single/widgets/controls.dart';
import 'package:openim_live/src/session/single_call_session.dart';
import 'package:openim_live/src/widgets/call_compact_surface.dart';
import 'package:openim_live/src/widgets/live_button.dart';
import 'package:rxdart/rxdart.dart';

const _name = '这是需要正确展示的真实联系人备注名称以及很长的联系人昵称';
const _preview = bool.fromEnvironment('CALL_SURFACE_PREVIEW');

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
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          fontFamily: _preview ? 'CallPreviewFont' : null,
        ),
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: page!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('call-surface-preview'),
          child: Scaffold(body: child),
        ),
      ),
    );

Finder _button(String text) => find
    .byWidgetPredicate((widget) => widget is LiveButton && widget.text == text);

class _SignalProbe {
  int credentials = 0, connects = 0, releases = 0, closes = 0;
  final cameraUpdates = <bool>[];
}

class _TestSignalView extends SignalView {
  _TestSignalView({
    required GlobalKey<_TestSignalState> key,
    required PublishSubject<CallEvent> events,
    required Future<SignalingCertificate> Function() pickup,
    required this.probe,
    CallType callType = CallType.audio,
  }) : super(
          key: key,
          callType: callType,
          initState: CallState.beCalled,
          roomID: 'surface-room',
          userID: 'real-peer',
          callEventSubject: events,
          autoPickup: false,
          onTapPickup: pickup,
          onClose: () => probe.closes++,
          onSyncUserInfo: (_) async =>
              UserInfo(userID: 'real-peer', nickname: _name),
        );

  final _SignalProbe probe;

  @override
  _TestSignalState createState() => _TestSignalState();
}

class _TestSignalState extends SignalState<_TestSignalView> {
  @override
  Future<void> connect(CallAttempt attempt) async {
    if (attempt.isCurrent) widget.probe.connects++;
  }

  @override
  Future<void> releaseMedia() async => widget.probe.releases++;
  @override
  Future<void> setBackgroundCamera(bool enabled) async =>
      widget.probe.cameraUpdates.add(enabled);
  @override
  bool existParticipants() => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  const pip = MethodChannel('openim_call_pip');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(() async {
    if (!_preview) return;
    final bytes = ByteData.sublistView(
        await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
    for (final family in [
      'CallPreviewFont',
      'Roboto',
      'CupertinoSystemText',
      'CupertinoSystemDisplay'
    ]) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  setUp(() => Get.testMode = true);
  tearDown(() {
    messenger.setMockMethodCallHandler(permissions, null);
    messenger.setMockMethodCallHandler(pip, null);
    debugDefaultTargetPlatformOverride = null;
    Get.reset();
  });

  for (final dark in [false, true]) {
    testWidgets('actual controls fit 320px / 2x text / safe area / dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      final cases = [
        (state: CallState.beCalled, video: false, connected: false),
        (state: CallState.connecting, video: false, connected: false),
        (state: CallState.call, video: true, connected: false),
        (state: CallState.calling, video: true, connected: true),
      ];
      for (final scenario in cases) {
        await tester.pumpWidget(_host(
            ControlsView(
              key: ValueKey(scenario),
              initState: scenario.state,
              callType: scenario.video ? CallType.video : CallType.audio,
              connected: scenario.connected,
              callStateStream: const Stream<CallState>.empty(),
              roomDidUpdateStream: const Stream<Room>.empty(),
              userInfo: UserInfo(userID: 'real-peer', nickname: _name),
              duration: 73,
              onPickUp: () {},
              onReject: () {},
              onCancel: () {},
              onHangUp: (_) {},
              onMinimize: () {},
              onPictureInPicture: () {},
            ),
            dark: dark,
            scale: 2));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(ControlsView), findsOneWidget);
        if (!scenario.connected) {
          expect(find.text(_name), findsOneWidget);
          expect(find.byType(AvatarView), findsOneWidget);
        }
        for (final element in find.byType(LiveButton).evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(320));
          expect(rect.bottom, lessThanOrEqualTo(616));
        }
        expect(tester.takeException(), isNull);
        if (scenario.state == CallState.beCalled && _preview) {
          // This state has no periodic animation: settle real avatar/button
          // asset decoding before writing a reviewable preview.
          final imageContext = tester.element(find.byType(ControlsView));
          final images = tester.widgetList<Image>(find.byType(Image)).toList();
          await tester.runAsync(() async {
            await Future.wait(images
                .map((image) => precacheImage(image.image, imageContext)));
            await Future<void>.delayed(const Duration(milliseconds: 150));
          });
          await tester.pumpAndSettle();
          expect(
              tester
                  .widgetList<RawImage>(find.byType(RawImage))
                  .every((image) => image.image != null),
              isTrue);
          final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('call-surface-preview')));
          boundary.markNeedsPaint();
          await tester.pump();
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            try {
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              final file =
                  File('docs/previews/call-${dark ? 'dark' : 'light'}.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
    });

    testWidgets('compact audio and real video child fit long name / dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final video in [false, true]) {
        final suppliedVideo = Container(
            key: const ValueKey('live-video-child'), color: Colors.blue);
        await tester.pumpWidget(_host(
            Center(
                child: SizedBox(
              width: video ? 110 : 84,
              height: video ? 196 : 96,
              child: CallCompactSurface(
                userInfo: UserInfo(userID: 'real-peer', nickname: _name),
                state: CallState.calling,
                duration: 73,
                systemPip: true,
                video: video ? suppliedVideo : null,
              ),
            )),
            dark: dark,
            scale: 2));
        await tester.pump();
        expect(tester.takeException(), isNull);
        if (video) {
          expect(find.byWidget(suppliedVideo), findsOneWidget);
          expect(tester.getSize(find.byWidget(suppliedVideo)),
              const Size(110, 196));
        } else {
          expect(find.text(_name), findsOneWidget);
        }
      }
    });
  }

  testWidgets('connecting incoming call disables another pickup',
      (tester) async {
    final states = StreamController<CallState>.broadcast();
    addTearDown(states.close);
    var pickups = 0;
    await tester.pumpWidget(_host(ControlsView(
      initState: CallState.beCalled,
      callType: CallType.audio,
      callStateStream: states.stream,
      roomDidUpdateStream: const Stream<Room>.empty(),
      userInfo: UserInfo(userID: 'peer', nickname: _name),
      onPickUp: () {
        pickups++;
        states.add(CallState.connecting);
      },
      onReject: () {},
    )));
    await tester.pump();
    await tester.tap(_button(StrRes.pickUp));
    await tester.pump();
    expect(pickups, 1);
    expect(tester.widget<LiveButton>(_button(StrRes.pickUp)).onTap, isNull);
    await tester.tap(_button(StrRes.pickUp));
    await tester.pump();
    expect(pickups, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('inactive controls disable every action and media callback',
      (tester) async {
    var invocations = 0;
    for (final incoming in [false, true]) {
      await tester.pumpWidget(_host(ControlsView(
        key: ValueKey(incoming),
        initState: incoming ? CallState.beCalled : CallState.calling,
        callType: CallType.video,
        connected: !incoming,
        active: false,
        callStateStream: const Stream<CallState>.empty(),
        roomDidUpdateStream: const Stream<Room>.empty(),
        onPickUp: () => invocations++,
        onReject: () => invocations++,
        onCancel: () => invocations++,
        onHangUp: (_) => invocations++,
        onMinimize: () => invocations++,
        onPictureInPicture: () => invocations++,
        onSetMicrophone: (_) async => invocations++,
        onSetSpeaker: (_) async => invocations++,
        onSetCamera: (_) async => invocations++,
        onSwitchCamera: () async => invocations++,
      )));
      await tester.pump();
      for (final button
          in tester.widgetList<LiveButton>(find.byType(LiveButton))) {
        expect(button.onTap, isNull);
        await tester.tap(find.byWidget(button));
      }
      for (final button
          in tester.widgetList<IconButton>(find.byType(IconButton))) {
        expect(button.onPressed, isNull);
        await tester.tap(find.byWidget(button));
      }
      await tester.pump();
      expect(invocations, 0);
      expect(tester.takeException(), isNull);
    }
  });

  for (final timesOut in [false, true]) {
    testWidgets(
        'failed PiP ${timesOut ? 'timeout' : 'native refusal'} pauses background camera and permits restore',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(
          permissions, (_) async => {7: 1, 1: 1});
      String? nativeSession;
      messenger.setMockMethodCallHandler(pip, (call) async {
        if (call.method == 'configure') {
          nativeSession = (call.arguments as Map)['session'] as String;
          return {
            'supported': true,
            'ready': true,
            'backgroundCameraSupported': true,
          };
        }
        return true;
      });
      final events = PublishSubject<CallEvent>();
      addTearDown(events.close);
      final probe = _SignalProbe();
      final key = GlobalKey<_TestSignalState>();
      await tester.pumpWidget(_host(Stack(children: [
        _TestSignalView(
          key: key,
          events: events,
          probe: probe,
          callType: CallType.video,
          pickup: () async => SignalingCertificate.fromJson({
            'roomID': 'surface-room',
            'liveURL': 'https://unused.test',
            'token': 'unused',
          }),
        ),
      ])));
      final state = key.currentState!;
      if (!timesOut) {
        // Leaving while still connecting must also pause the camera when
        // the peer subsequently joins in the background.
        state.didChangeAppLifecycleState(AppLifecycleState.paused);
      }
      await state.onTapPickup();
      state.session.peerConnected();
      await tester.pump();
      expect(state.session.connected, isTrue);
      expect(state.pictureInPicture.backgroundCameraSupported, isTrue);
      if (timesOut) {
        state.didChangeAppLifecycleState(AppLifecycleState.paused);
      }
      expect(probe.cameraUpdates, [false]);
      expect(await state.pictureInPicture.enter(), isTrue);
      expect(probe.cameraUpdates, [false, true]);
      if (timesOut) {
        await tester.pump(const Duration(seconds: 3));
      } else {
        final responded = Completer<void>();
        messenger.handlePlatformMessage(
          pip.name,
          pip.codec.encodeMethodCall(MethodCall('state', {
            'session': nativeSession,
            'phase': 'failed',
          })),
          (_) => responded.complete(),
        );
        await responded.future;
      }
      expect(state.pictureInPicture.entering, isFalse);
      expect(probe.cameraUpdates, [false, true, false]);
      expect(state.session.active, isTrue);
      expect(probe.closes, 0);
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(probe.cameraUpdates, [false, true, false, true]);
      await state.endActive();
      await tester.pumpWidget(const SizedBox());
      expect(probe.releases, 1);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final pendingPermission in [true, false]) {
    testWidgets(
        'cancel ignores late ${pendingPermission ? 'permission' : 'certificate'} in actual SignalState',
        (tester) async {
      final permissionGate = Completer<Map<int, int>>();
      final certificateGate = Completer<SignalingCertificate>();
      final events = PublishSubject<CallEvent>();
      addTearDown(events.close);
      final probe = _SignalProbe();
      final key = GlobalKey<_TestSignalState>();
      messenger.setMockMethodCallHandler(permissions, (call) async {
        expect(call.method, 'requestPermissions');
        return pendingPermission ? permissionGate.future : <int, int>{7: 1};
      });
      await tester.pumpWidget(_host(Stack(children: [
        _TestSignalView(
          key: key,
          events: events,
          probe: probe,
          pickup: () {
            probe.credentials++;
            return certificateGate.future;
          },
        )
      ])));
      await tester.pump();
      await tester.tap(_button(StrRes.pickUp));
      await tester.pump();
      expect(key.currentState!.callState, CallState.connecting);
      final ending = key.currentState!.endActive();
      await tester.pump();
      await ending;
      expect(probe.releases, 1);
      expect(probe.closes, 1);
      await tester.pumpWidget(const SizedBox());
      if (pendingPermission) {
        permissionGate.complete({7: 1});
      } else {
        certificateGate.complete(SignalingCertificate.fromJson({
          'roomID': 'surface-room',
          'liveURL': 'https://unused.test',
          'token': 'unused',
        }));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(probe.credentials, pendingPermission ? 0 : 1);
      expect(probe.connects, 0);
      expect(probe.releases, 1);
      expect(probe.closes, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
