import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
// A disconnected remote stream has no public native fixture factory.
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:flutter_webrtc/src/native/media_stream_impl.dart';
// ignore: depend_on_referenced_packages
import 'package:livekit_client/livekit_client.dart';
// A disconnected local participant has no public SDK factory.
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:livekit_client/src/proto/livekit_models.pb.dart' as lk_models;
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/src/models/call_types.dart';
import 'package:openim_live/src/pages/single/widgets/call_state.dart';
import 'package:openim_live/src/pages/single/widgets/participant.dart';
import 'package:openim_live/src/session/single_call_session.dart';
import 'package:openim_live/src/widgets/call_surface/call_full_screen_surface.dart';
import 'package:rxdart/rxdart.dart';

const _permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
const _rtc = MethodChannel('FlutterWebRTC.Method');
const _rtcEvents = MethodChannel('FlutterWebRTC.Event');
const _pip = MethodChannel('openim_call_pip');
final _messenger =
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
final videoPreviewRtcMethods = <String>[];

class VideoPreviewProbe {
  int credentials = 0, connects = 0, releases = 0, closes = 0;
  int cancels = 0, hangups = 0, starts = 0;
}

class VideoPreviewFixture {
  VideoPreviewFixture(
      this.room, this.local, this.remote, this.localTrack, this.remoteTrack);
  final Room room;
  final LocalParticipant local;
  final RemoteParticipant remote;
  final LocalVideoTrack localTrack;
  final RemoteVideoTrack remoteTrack;

  static Future<VideoPreviewFixture> create() async {
    // Only MethodChannel is mocked. Renderer, both participants and both
    // tracks are the actual SDK objects used by SignalState in production.
    final localTrack = await LocalVideoTrack.createCameraTrack();
    final room = Room();
    // ignore: invalid_use_of_internal_member
    final local = LocalParticipant(
      room: room,
      info: lk_models.ParticipantInfo(
          sid: 'local-participant', identity: 'me', name: 'Me'),
    );
    // ignore: invalid_use_of_internal_member
    final remote = RemoteParticipant(
        room: room, sid: 'remote-participant', identity: 'dual', name: 'dual');
    final remoteStream = MediaStreamNative.fromMap({
      'streamId': 'mock-remote-stream',
      'ownerTag': 'mock-peer-connection',
      'audioTracks': <dynamic>[],
      'videoTracks': [
        {
          'id': 'mock-remote-camera',
          'label': 'Remote camera',
          'kind': 'video',
          'enabled': true,
        }
      ],
    });
    final remoteTrack = RemoteVideoTrack(
        TrackSource.camera, remoteStream, remoteStream.getVideoTracks().single);
    return VideoPreviewFixture(room, local, remote, localTrack, remoteTrack);
  }

  Future<void> dispose() async {
    await local.dispose();
    await remote.dispose();
    await localTrack.dispose();
    await remoteTrack.dispose();
    await room.dispose();
  }
}

class VideoPreviewSignalView extends SignalView {
  VideoPreviewSignalView({
    required GlobalKey<VideoPreviewSignalState> key,
    required PublishSubject<CallEvent> events,
    required this.probe,
    required this.video,
    this.withRemote = true,
  }) : super(
          key: key,
          initState: CallState.call,
          callType: CallType.video,
          roomID: 'video-preview-room',
          userID: 'dual',
          callEventSubject: events,
          autoPickup: false,
          ringingTimeout: const Duration(minutes: 5),
          onDial: () async {
            probe.credentials++;
            return SignalingCertificate.fromJson({
              'roomID': 'video-preview-room',
              'liveURL': 'https://unused.test',
              'token': 'unused-token',
            });
          },
          onTapCancel: () async => probe.cancels++,
          onTapHangup: (_, __) async => probe.hangups++,
          onClose: () => probe.closes++,
          onStartCalling: () => probe.starts++,
          onSyncUserInfo: (_) async =>
              UserInfo(userID: 'dual', nickname: 'dual'),
        );
  final VideoPreviewProbe probe;
  final VideoPreviewFixture video;
  final bool withRemote;

  @override
  VideoPreviewSignalState createState() => VideoPreviewSignalState();
}

class VideoPreviewSignalState extends SignalState<VideoPreviewSignalView> {
  void setMuted(bool muted) {
    // Actual SDK mute metadata, without sending signaling or altering capture.
    // ignore: invalid_use_of_internal_member
    widget.video.localTrack.updateMuted(muted, shouldNotify: false);
    // ignore: invalid_use_of_internal_member
    widget.video.remoteTrack.updateMuted(muted, shouldNotify: false);
    setState(() {});
  }

  void clearCameras() {
    setState(() {
      localParticipantTrack = null;
      remoteParticipantTrack = null;
    });
  }

  @override
  void initState() {
    super.initState();
    localParticipantTrack = ParticipantTrack(
        participant: widget.video.local,
        videoTrack: widget.video.localTrack,
        isScreenShare: false);
    if (widget.withRemote) {
      remoteParticipantTrack = ParticipantTrack(
          participant: widget.video.remote,
          videoTrack: widget.video.remoteTrack,
          isScreenShare: false);
    }
  }

  @override
  Future<void> connect(CallAttempt attempt) async {
    if (attempt.isCurrent) widget.probe.connects++;
  }

  @override
  Future<void> releaseMedia() async => widget.probe.releases++;

  @override
  bool existParticipants() => true;
}

Widget videoPreviewHost(VideoPreviewSignalView view,
        {Brightness brightness = Brightness.light}) =>
    ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        theme: ThemeData(brightness: brightness),
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(body: Stack(children: [view])),
      ),
    );

Future<void> pumpVideoPreviewFrames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<VideoPreviewSignalState> mountVideoPreview(WidgetTester tester,
    {required VideoPreviewProbe probe,
    bool connected = true,
    bool withRemote = true,
    Brightness brightness = Brightness.light,
    Size size = const Size(375, 812)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.reset);
  // Native stream startup must be outside testWidgets' fake clock.
  final fixture = (await tester.runAsync(VideoPreviewFixture.create))!;
  final key = GlobalKey<VideoPreviewSignalState>();
  await tester.pumpWidget(videoPreviewHost(
    VideoPreviewSignalView(
      key: key,
      events: PublishSubject<CallEvent>(),
      probe: probe,
      video: fixture,
      withRemote: withRemote,
    ),
    brightness: brightness,
  ));
  await pumpVideoPreviewFrames(tester);
  final state = key.currentState!;
  if (connected) {
    state.session.peerConnected();
    await pumpVideoPreviewFrames(tester);
  }
  expect(probe.credentials, 1);
  expect(probe.connects, 1);
  expect(state.session.connected, connected);
  expect(find.byType(CallFullScreenSurface), findsOneWidget);
  return state;
}

Future<void> disposeVideoPreview(
    WidgetTester tester, VideoPreviewSignalState state) async {
  final ending = state.endActive(notifyPeer: false);
  await pumpVideoPreviewFrames(tester);
  await ending;
  await tester.pumpWidget(const SizedBox());
  await pumpVideoPreviewFrames(tester);
  await state.widget.callEventSubject.close();
  await tester.runAsync(state.widget.video.dispose);
}

void expectVideoSessionUnchanged(VideoPreviewSignalState state,
    VideoPreviewProbe probe, SingleCallSession originalSession,
    {required bool connected}) {
  expect(state.session, same(originalSession));
  expect(state.session.active, isTrue);
  expect(state.session.connected, connected);
  expect(state.localParticipantTrack!.videoTrack,
      same(state.widget.video.localTrack));
  if (state.widget.withRemote) {
    expect(state.remoteParticipantTrack!.videoTrack,
        same(state.widget.video.remoteTrack));
  }
  expect(probe.credentials, 1);
  expect(probe.connects, 1);
  expect(probe.releases, 0);
  expect(probe.closes, 0);
  expect(probe.cancels, 0);
  expect(probe.hangups, 0);
  expect(probe.starts, connected ? 1 : 0);
}

void installVideoPreviewNativeMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var texture = 500;
  final textures = <MethodChannel>[];

  setUpAll(
      () => _messenger.setMockMethodCallHandler(_rtcEvents, (_) async => null));
  tearDownAll(() => _messenger.setMockMethodCallHandler(_rtcEvents, null));
  setUp(() {
    Get.testMode = true;
    videoPreviewRtcMethods.clear();
    _messenger.setMockMethodCallHandler(
        _permissions, (_) async => <int, int>{7: 1, 1: 1});
    _messenger.setMockMethodCallHandler(_pip, (_) async => true);
    _messenger.setMockMethodCallHandler(_rtc, (call) async {
      videoPreviewRtcMethods.add(call.method);
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
}
