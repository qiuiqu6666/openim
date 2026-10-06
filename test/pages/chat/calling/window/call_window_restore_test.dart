import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
// SignalState's public participant/track API exposes openim_live's LiveKit
// dependency. The native-boundary fixture uses those same real SDK types.
// ignore: depend_on_referenced_packages
import 'package:livekit_client/livekit_client.dart';
// No public SDK factory exists for a disconnected local participant. Test
// data uses the SDK's protobuf model without starting a room connection.
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:livekit_client/src/proto/livekit_models.pb.dart' as lk_models;
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/src/models/call_types.dart';
import 'package:openim_live/src/pages/single/widgets/call_state.dart';
import 'package:openim_live/src/pages/single/widgets/participant.dart';
import 'package:openim_live/src/session/single_call_session.dart';
import 'package:openim_live/src/widgets/call_compact_surface.dart';
import 'package:openim_live/src/widgets/call_surface/call_full_screen_surface.dart';
import 'package:rxdart/rxdart.dart';

const _permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
const _rtc = MethodChannel('FlutterWebRTC.Method');
const _rtcEvents = MethodChannel('FlutterWebRTC.Event');
const _pip = MethodChannel('openim_call_pip');
final _messenger =
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

class _CallProbe {
  int credentials = 0, connects = 0, releases = 0, closes = 0;
  int cancels = 0, hangups = 0, starts = 0, underlyingTaps = 0;
}

class _VideoFixture {
  _VideoFixture(this.room, this.participant, this.track);
  final Room room;
  final LocalParticipant participant;
  final LocalVideoTrack track;

  static Future<_VideoFixture> create() async {
    // Only the native boundary is mocked. Both the track and participant are
    // actual LiveKit objects and ParticipantWidget creates the real renderer.
    final track = await LocalVideoTrack.createCameraTrack();
    final room = Room();
    // ignore: invalid_use_of_internal_member
    final participant = LocalParticipant(
      room: room,
      info: lk_models.ParticipantInfo(
        sid: 'local-test-participant',
        identity: 'local-test-user',
        name: 'Me',
      ),
    );
    return _VideoFixture(room, participant, track);
  }

  Future<void> dispose() async {
    await participant.dispose();
    await track.dispose();
    await room.dispose();
  }
}

class _WindowSignalView extends SignalView {
  _WindowSignalView({
    required GlobalKey<_WindowSignalState> key,
    required PublishSubject<CallEvent> events,
    required this.probe,
    required super.callType,
    this.video,
  }) : super(
          key: key,
          initState: CallState.call,
          roomID: 'window-test-room',
          userID: 'window-test-peer',
          callEventSubject: events,
          autoPickup: false,
          ringingTimeout: const Duration(minutes: 5),
          onDial: () async {
            probe.credentials++;
            return SignalingCertificate.fromJson({
              'roomID': 'window-test-room',
              'liveURL': 'https://unused.test',
              'token': 'unused-test-token',
            });
          },
          onTapCancel: () async => probe.cancels++,
          onTapHangup: (_, __) async => probe.hangups++,
          onClose: () => probe.closes++,
          onStartCalling: () => probe.starts++,
          onSyncUserInfo: (_) async =>
              UserInfo(userID: 'window-test-peer', nickname: 'dual'),
        );
  final _CallProbe probe;
  final _VideoFixture? video;

  @override
  _WindowSignalState createState() => _WindowSignalState();
}

class _WindowSignalState extends SignalState<_WindowSignalView> {
  @override
  void initState() {
    super.initState();
    final video = widget.video;
    if (video != null) {
      localParticipantTrack = ParticipantTrack(
        participant: video.participant,
        videoTrack: video.track,
        isScreenShare: false,
      );
    }
  }

  @override
  Future<void> connect(CallAttempt attempt) async {
    if (attempt.isCurrent) widget.probe.connects++;
  }

  @override
  Future<void> releaseMedia() async => widget.probe.releases++;

  @override
  bool existParticipants() => widget.video != null;
}

Widget _host(_WindowSignalView view) => ScreenUtilInit(
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
        home: Scaffold(
          body: Stack(children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => view.probe.underlyingTaps++,
                child: const ColoredBox(color: Colors.white),
              ),
            ),
            view,
          ]),
        ),
      ),
    );

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<_WindowSignalState> _mount(
  WidgetTester tester, {
  required bool video,
  required bool connected,
  required _CallProbe probe,
}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Native media initialization begins before the first widget frame. Keep
  // its channel/stream startup outside the widget test's virtual clock.
  final fixture = video ? await tester.runAsync(_VideoFixture.create) : null;
  final key = GlobalKey<_WindowSignalState>();
  final events = PublishSubject<CallEvent>();
  await tester.pumpWidget(_host(_WindowSignalView(
    key: key,
    events: events,
    probe: probe,
    callType: video ? CallType.video : CallType.audio,
    video: fixture,
  )));
  final state = key.currentState!;
  await _frames(tester);
  expect(probe.credentials, 1);
  expect(probe.connects, 1);
  expect(state.callState, CallState.call);
  if (connected) {
    state.session.peerConnected();
    await _frames(tester);
    expect(state.callState, CallState.calling);
  }
  expect(state.session.connected, connected);
  expect(find.byType(CallFullScreenSurface), findsOneWidget);
  if (video) {
    expect(find.byType(LocalParticipantWidget), findsOneWidget);
    expect(find.byType(VideoTrackRenderer), findsOneWidget);
    expect(find.byType(Texture), findsOneWidget);
  }
  return state;
}

Future<void> _disposeFixture(
    WidgetTester tester, _WindowSignalState state) async {
  // Execute asynchronous session and native mock cleanup while still inside
  // testWidgets' fake clock. addTearDown runs after automatic unmount and can
  // otherwise wait on a release Future whose fake clock has already exited.
  final ending = state.endActive(notifyPeer: false);
  await _frames(tester);
  await ending;
  await tester.pumpWidget(const SizedBox());
  await _frames(tester);
  await state.widget.callEventSubject.close();
  final video = state.widget.video;
  if (video != null) await tester.runAsync(video.dispose);
}

Future<void> _minimize(WidgetTester tester, _WindowSignalState state) async {
  await tester.tap(find.byTooltip('最小化'));
  await _frames(tester);
  expect(state.minimize, isTrue);
  expect(find.byType(CallFullScreenSurface), findsNothing);
  expect(find.byType(CallCompactSurface), findsOneWidget);
}

void _expectNoCallMutation(_CallProbe probe, {required bool connected}) {
  expect(probe.credentials, 1);
  expect(probe.connects, 1);
  expect(probe.releases, 0);
  expect(probe.closes, 0);
  expect(probe.cancels, 0);
  expect(probe.hangups, 0);
  expect(probe.starts, connected ? 1 : 0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var texture = 100;
  final textures = <MethodChannel>[];
  final rtcMethods = <String>[];

  setUpAll(() {
    _messenger.setMockMethodCallHandler(_rtcEvents, (_) async => null);
  });
  tearDownAll(() {
    _messenger.setMockMethodCallHandler(_rtcEvents, null);
  });
  setUp(() {
    Get.testMode = true;
    rtcMethods.clear();
    _messenger.setMockMethodCallHandler(
        _permissions, (_) async => <int, int>{7: 1, 1: 1});
    _messenger.setMockMethodCallHandler(_pip, (_) async => true);
    _messenger.setMockMethodCallHandler(_rtc, (call) async {
      rtcMethods.add(call.method);
      switch (call.method) {
        case 'initialize':
        case 'videoRendererSetSrcObject':
        case 'videoRendererDispose':
        case 'mediaStreamTrackStop':
        case 'trackDispose':
        case 'streamDispose':
          return null;
        case 'getSources':
          return <String, dynamic>{'sources': <dynamic>[]};
        case 'getUserMedia':
          return <String, dynamic>{
            'streamId': 'mock-native-local-stream',
            'audioTracks': <dynamic>[],
            'videoTracks': [
              {
                'id': 'mock-native-local-camera',
                'label': 'Mock camera',
                'kind': 'video',
                'enabled': true,
                'settings': {'facingMode': 'user'},
              }
            ],
          };
        case 'createVideoRenderer':
          final id = texture++;
          final channel = MethodChannel('FlutterWebRTC/Texture$id');
          textures.add(channel);
          _messenger.setMockMethodCallHandler(channel, (_) async => null);
          return <String, dynamic>{'textureId': id};
        default:
          throw StateError('Unexpected WebRTC boundary call: ${call.method}');
      }
    });
  });
  tearDown(() {
    _messenger.setMockMethodCallHandler(_permissions, null);
    _messenger.setMockMethodCallHandler(_pip, null);
    _messenger.setMockMethodCallHandler(_rtc, null);
    for (final channel in textures) {
      _messenger.setMockMethodCallHandler(channel, null);
    }
    textures.clear();
    Get.reset();
  });

  for (final video in [false, true]) {
    for (final connected in [false, true]) {
      testWidgets(
          'actual SignalState ${video ? 'video' : 'audio'} ${connected ? 'connected' : 'waiting'} restores from body, label and edge',
          (tester) async {
        final probe = _CallProbe();
        final state = await _mount(tester,
            video: video, connected: connected, probe: probe);
        try {
          final originalSession = state.session;
          final originalTrack = state.localParticipantTrack?.videoTrack;
          for (final region in ['body', 'label', 'edge', 'body']) {
            await _minimize(tester, state);
            final surface = find.byType(CallCompactSurface);
            if (video) {
              final renderer = find.descendant(
                  of: surface, matching: find.byType(VideoTrackRenderer));
              expect(renderer, findsOneWidget);
              expect(
                  find.descendant(of: surface, matching: find.byType(Texture)),
                  findsOneWidget);
              final ignoredVideo = find.descendant(
                  of: surface,
                  matching: find.byWidgetPredicate(
                      (widget) => widget is IgnorePointer && widget.ignoring));
              expect(ignoredVideo, findsOneWidget);
              expect(find.descendant(of: ignoredVideo, matching: renderer),
                  findsOneWidget);
            }
            final rect = tester.getRect(surface);
            final label =
                find.descendant(of: surface, matching: find.byType(Text));
            final point = switch (region) {
              'label' => tester.getCenter(label),
              // This point is inside the window rectangle but outside the
              // rounded video/background clip: outer opaque routing is needed.
              'edge' => rect.topLeft + const Offset(1, 1),
              _ => rect.center,
            };
            await tester.tapAt(point);
            await _frames(tester);

            expect(state.minimize, isFalse, reason: region);
            expect(find.byType(CallFullScreenSurface), findsOneWidget,
                reason: region);
            expect(find.byType(CallCompactSurface), findsNothing);
            expect(state.session, same(originalSession));
            expect(
                state.localParticipantTrack?.videoTrack, same(originalTrack));
            expect(state.session.active, isTrue);
            expect(state.session.connected, connected);
            expect(probe.underlyingTaps, 0);
            _expectNoCallMutation(probe, connected: connected);
            expect(tester.takeException(), isNull);
          }
          expect(rtcMethods.where((method) => method == 'getUserMedia').length,
              video ? 1 : 0);
          expect(
              rtcMethods.where((method) => method == 'trackDispose'), isEmpty);
        } finally {
          await _disposeFixture(tester, state);
        }
      });
    }

    testWidgets(
        'actual ${video ? 'video' : 'audio'} float drag only moves; outside taps reach the conversation',
        (tester) async {
      final probe = _CallProbe();
      final state =
          await _mount(tester, video: video, connected: true, probe: probe);
      try {
        await _minimize(tester, state);
        final surface = find.byType(CallCompactSurface);
        final before = tester.getRect(surface);
        await tester.dragFrom(before.center, const Offset(-100, 80));
        await _frames(tester);
        final after = tester.getRect(surface);
        expect(after.left, lessThan(before.left));
        expect(after.top, greaterThan(before.top));
        expect(state.minimize, isTrue);
        expect(find.byType(CallFullScreenSurface), findsNothing);
        expect(probe.underlyingTaps, 0);

        await tester.tapAt(const Offset(20, 700));
        await _frames(tester);
        expect(probe.underlyingTaps, 1);
        expect(state.minimize, isTrue);
        expect(state.session.active, isTrue);
        _expectNoCallMutation(probe, connected: true);

        // Releasing a drag must not restore. A distinct subsequent tap does.
        await tester.tapAt(after.center);
        await _frames(tester);
        expect(state.minimize, isFalse);
        expect(find.byType(CallFullScreenSurface), findsOneWidget);
        _expectNoCallMutation(probe, connected: true);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeFixture(tester, state);
      }
    });

    testWidgets(
        'disposing active ${video ? 'video' : 'audio'} float detaches UI listeners before releasing the session',
        (tester) async {
      final probe = _CallProbe();
      final state =
          await _mount(tester, video: video, connected: false, probe: probe);
      try {
        await _minimize(tester, state);
        // Do not end first: this explicitly exercises SignalState.dispose's
        // active-session path and any synchronous PiP listener notification.
        await tester.pumpWidget(const SizedBox());
        await _frames(tester);
        expect(state.session.active, isFalse);
        expect(probe.releases, 1);
        expect(probe.closes, 1);
        expect(probe.credentials, 1);
        expect(probe.connects, 1);
        expect(probe.cancels, 0);
        expect(probe.hangups, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeFixture(tester, state);
      }
    });
  }
}
