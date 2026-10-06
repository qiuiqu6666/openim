import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/voice/chat_voice_panel_view.dart';
import 'package:voice_note_kit/voice_note_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pressing the microphone immediately opens the recording overlay',
      (tester) async {
    final harness = await _VoiceGestureHarness.mount(tester);
    final gesture = await harness.pressMicrophone();
    await tester.pump();
    expect(find.byType(ChatVoiceRecordingOverlay), findsOneWidget);
    expect(harness.native.startCalls, 1);
    expect(find.text('松开发送'), findsWidgets);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('转文字'), findsOneWidget);

    await harness.cancel(gesture);
    expect(find.byType(ChatVoiceRecordingOverlay), findsNothing);
    expect(find.text('按住说话'), findsOneWidget);
    harness.expectNoDelivery();
  });

  testWidgets('empty panel space does not start the microphone',
      (tester) async {
    final harness = await _VoiceGestureHarness.mount(tester);
    await tester.tapAt(harness.microphoneCenter - const Offset(100, 0));
    await tester.pump();
    expect(find.byType(ChatVoiceRecordingOverlay), findsNothing);
    expect(harness.native.startCalls, 0);
    expect(harness.delivered, 0);
  });

  testWidgets('native levels and elapsed seconds reach the recording surface',
      (tester) async {
    final harness = await _VoiceGestureHarness.mount(tester);
    final gesture = await harness.pressMicrophone();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1150)));
    await tester.pump();
    var overlay = tester.widget<ChatVoiceRecordingOverlay>(
        find.byType(ChatVoiceRecordingOverlay));
    expect(overlay.seconds, greaterThanOrEqualTo(1));
    expect(overlay.levels, contains(closeTo(.5, .001)));
    harness.native.currentDb = -60;
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 350)));
    await tester.pump();
    overlay = tester.widget<ChatVoiceRecordingOverlay>(
        find.byType(ChatVoiceRecordingOverlay));
    expect(overlay.levels.last, 0);
    await harness.cancel(gesture);
    harness.expectNoDelivery();
  });

  testWidgets('permission error stays visible in the panel and retry clears it',
      (tester) async {
    final harness = await _VoiceGestureHarness.mount(tester);
    harness.native.permissionGranted = false;
    final first = await tester
        .runAsync(() => tester.startGesture(harness.microphoneCenter));
    await harness.waitForNative(() =>
        tester
            .widget<ChatVoiceIdlePanel>(find.byType(ChatVoiceIdlePanel))
            .errorText !=
        null);
    expect(find.byType(ChatVoiceRecordingOverlay), findsNothing);
    expect(
        tester
            .widget<ChatVoiceIdlePanel>(find.byType(ChatVoiceIdlePanel))
            .errorText,
        '请允许使用麦克风');
    expect(harness.native.startCalls, 0);
    await tester.runAsync(first!.up);
    harness.native.permissionGranted = true;
    final retry = await harness.pressMicrophone();
    expect(
        tester
            .widget<ChatVoiceIdlePanel>(find.byType(ChatVoiceIdlePanel))
            .errorText,
        isNull);
    await harness.cancel(retry);
    harness.expectNoDelivery();
  });

  for (final convert in [false, true]) {
    testWidgets(
        'final release delivers ${convert ? 'text conversion' : 'voice'} once',
        (tester) async {
      final harness = await _VoiceGestureHarness.mount(tester);
      harness.native.audioDuration = const Duration(milliseconds: 1500);
      harness.callbackGate =
          await tester.runAsync(() async => Completer<void>());
      final mic = harness.microphoneCenter;
      final gesture = await harness.pressMicrophone(pointer: 29);
      final convertCenter = tester.getCenter(
          find.byKey(const ValueKey('chat-voice-control-convertText')));
      final cancelCenter = tester
          .getCenter(find.byKey(const ValueKey('chat-voice-control-cancel')));
      await tester.runAsync(
          () => gesture.moveTo(convert ? cancelCenter : convertCenter));
      await tester.pump();
      await tester.runAsync(() => tester.sendEventToBinding(PointerUpEvent(
            pointer: 29,
            position: convert ? convertCenter : mic,
          )));
      await harness
          .waitForNative(() => harness.delivered + harness.converted == 1);
      expect(harness.delivered, convert ? 0 : 1);
      expect(harness.converted, convert ? 1 : 0);
      expect(harness.receivedSeconds, [2]);
      expect(harness.native.audioInitCalls, 1);
      expect(harness.native.audioLoadCalls, 1);
      expect(harness.native.stopCalls, 1);
      expect(find.byType(ChatVoiceRecordingOverlay), findsNothing);
      expect(
          tester
              .widget<ChatVoiceIdlePanel>(find.byType(ChatVoiceIdlePanel))
              .busy,
          isTrue);
      final owned = harness.deliveredFiles.single;
      expect(await tester.runAsync(() => owned.exists()), isTrue);
      expect(await tester.runAsync(() => owned.readAsBytes()), [0, 1, 2, 3]);
      expect(owned.path, contains('outgoing_media'));
      expect(harness.native.audioLoadUris,
          contains(Uri.file(harness.native.files.single.path).toString()));

      // Further taps while the callback owns the pending send/review cannot
      // start a second recorder or deliver the same audio a second time.
      await tester.tapAt(mic);
      await tester.pump();
      expect(harness.native.startCalls, 1);
      expect(harness.delivered + harness.converted, 1);
      await tester.runAsync(() async => harness.releaseCallback());
      await harness.waitForDiscard();
      await harness.waitForRecordingFinished();
      expect(harness.delivered + harness.converted, 1);
      expect(await tester.runAsync(() => owned.exists()), isTrue,
          reason: 'A delivered copy belongs to the send/review consumer');
      expect(harness.native.audioDisposeCalls, 1);
    });
  }

  testWidgets('a short recording explains the error and delivers no file',
      (tester) async {
    final harness = await _VoiceGestureHarness.mount(tester);
    harness.native.audioDuration = const Duration(milliseconds: 500);
    final gesture = await harness.pressMicrophone();
    await tester.runAsync(gesture.up);
    await harness.waitForDiscard();
    await harness.waitForRecordingFinished();
    expect(harness.delivered, 0);
    expect(harness.converted, 0);
    expect(harness.deliveredFiles, isEmpty);
    expect(await tester.runAsync(harness.native.outgoingFiles), isEmpty);
    expect(harness.native.audioLoadCalls, 1);
    expect(harness.native.audioDisposeCalls, 1);
    expect(
        tester
            .widget<ChatVoiceIdlePanel>(find.byType(ChatVoiceIdlePanel))
            .errorText,
        '录音时间太短，请按住后说话');
    expect(find.byType(ChatVoiceRecordingOverlay), findsNothing);
  });

  testWidgets(
      'switching input while duration loads invalidates the pending send',
      (tester) async {
    final harness = await _VoiceGestureHarness.mount(tester);
    harness.native.audioDuration = const Duration(milliseconds: 1500);
    await tester.runAsync(() async {
      harness.native.audioLoadGate = Completer<void>();
    });
    final gesture = await harness.pressMicrophone();
    await tester.runAsync(gesture.up);
    await harness
        .waitForNative(() => harness.native.audioLoadEntered.isCompleted);
    expect(
        tester.widget<ChatVoiceIdlePanel>(find.byType(ChatVoiceIdlePanel)).busy,
        isTrue);
    harness.expanded.value = false;
    await tester.pump();
    harness.expanded.value = true;
    await tester.pump();
    await tester.runAsync(() async => harness.native.releaseAudioLoad());
    await harness.waitForDiscard();
    await harness.waitForRecordingFinished();
    expect(harness.delivered, 0);
    expect(harness.converted, 0);
    expect(harness.deliveredFiles, isEmpty);
    expect(await tester.runAsync(harness.native.outgoingFiles), isEmpty);
    expect(harness.native.audioInitCalls, 1);
    expect(harness.native.audioLoadCalls, 1);
    expect(harness.native.audioDisposeCalls, 1);
    expect(find.byType(ChatVoiceRecordingOverlay), findsNothing);
  });

  testWidgets('covering the chat route cancels the active recording',
      (tester) async {
    final harness = await _VoiceGestureHarness.mount(tester);
    final gesture = await harness.pressMicrophone();
    final navigator =
        Navigator.of(tester.element(find.byType(HoldToRecordButton)));
    unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('另一个页面')))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await harness.waitForDiscard();
    expect(find.byType(ChatVoiceRecordingOverlay), findsNothing);
    await tester.runAsync(gesture.up);
    harness.expectNoDelivery();
  });

  testWidgets('moving to the left control shows cancel and release discards',
      (tester) async {
    final harness = await _VoiceGestureHarness.mount(tester);
    final mic = harness.microphoneCenter;
    final gesture = await harness.pressMicrophone();
    await tester.runAsync(() => gesture.moveTo(mic - const Offset(120, 0)));
    await tester.pump();
    expect(find.text('松开取消'), findsOneWidget);
    expect(find.byType(ChatVoiceRecordingOverlay), findsOneWidget);

    await tester.runAsync(gesture.up);
    await harness.waitForDiscard();
    expect(find.byType(ChatVoiceRecordingOverlay), findsNothing);
    expect(harness.native.stopCalls, 1);
    harness.expectNoDelivery();
  });

  testWidgets('pointer cancellation removes overlay and discards recording',
      (tester) async {
    final harness = await _VoiceGestureHarness.mount(tester);
    final gesture = await harness.pressMicrophone();
    await tester.pump();
    expect(find.byType(ChatVoiceRecordingOverlay), findsOneWidget);
    await harness.cancel(gesture);
    expect(find.byType(ChatVoiceRecordingOverlay), findsNothing);
    expect(harness.native.stopCalls, 1);
    harness.expectNoDelivery();
  });

  testWidgets(
      'a second pointer cancellation cannot discard the first recording',
      (tester) async {
    final harness = await _VoiceGestureHarness.mount(tester);
    final gesture = await harness.pressMicrophone(pointer: 17);
    await tester.runAsync(() => tester.sendEventToBinding(
        PointerDownEvent(pointer: 18, position: harness.microphoneCenter)));
    await tester.runAsync(() => tester.sendEventToBinding(
        PointerCancelEvent(pointer: 18, position: harness.microphoneCenter)));
    await tester.pump();
    expect(find.byType(ChatVoiceRecordingOverlay), findsOneWidget);
    expect(harness.native.stopCalls, 0);
    await harness.cancel(gesture);
    harness.expectNoDelivery();
  });

  testWidgets('duration limit preserves the active cancel intention',
      (tester) async {
    final harness = await _VoiceGestureHarness.mount(tester);
    final mic = harness.microphoneCenter;
    final gesture = await harness.pressMicrophone();
    await tester.runAsync(() => gesture.moveTo(mic - const Offset(120, 0)));
    await tester.pump();
    final recorder =
        tester.widget<VoiceRecorderWidget>(find.byType(VoiceRecorderWidget));
    await tester.runAsync(() async {
      // Mirrors the existing timer: initiate stop, then notify the limit.
      final stopping = recorder.controller!.stop();
      recorder.onMaxDurationReached!();
      await stopping;
      await gesture.up();
    });
    await harness.waitForDiscard();
    expect(find.byType(ChatVoiceRecordingOverlay), findsNothing);
    expect(harness.native.stopCalls, 1);
    harness.expectNoDelivery();
  });

  testWidgets('release position determines cancel without a final move event',
      (tester) async {
    final harness = await _VoiceGestureHarness.mount(tester);
    final mic = harness.microphoneCenter;
    final gesture = await harness.pressMicrophone(pointer: 17);
    await tester.runAsync(() => gesture.moveTo(mic));
    await tester.pump();
    expect(find.text('松开取消'), findsNothing);
    // Real pointer packets can end at a new position without a final move.
    // A stale remembered move zone would incorrectly send this recording.
    await tester.runAsync(() => tester.sendEventToBinding(PointerUpEvent(
          pointer: 17,
          position: mic - const Offset(120, 0),
        )));
    await harness.waitForDiscard();
    expect(find.byType(ChatVoiceRecordingOverlay), findsNothing);
    expect(harness.native.stopCalls, 1);
    harness.expectNoDelivery();
  });

  for (final transition in ['switch', 'unmount']) {
    testWidgets('$transition during preparation cannot send a late recording',
        (tester) async {
      final harness = await _VoiceGestureHarness.mount(tester);
      await tester.runAsync(() async {
        harness.native.startGate = Completer<void>();
      });
      await harness.pressMicrophone(waitUntilStarted: false);
      await tester.pump();
      expect(find.byType(ChatVoiceRecordingOverlay), findsOneWidget);
      final overlay = tester.widget<ChatVoiceRecordingOverlay>(
          find.byType(ChatVoiceRecordingOverlay));
      expect(overlay.preparing, isTrue);

      if (transition == 'switch') {
        harness.expanded.value = false;
        await tester.pump();
      } else {
        await harness.removeWidget();
      }
      // OverlayEntry removal during the parent's build is applied next frame.
      await tester.pump();
      expect(find.byType(ChatVoiceRecordingOverlay), findsNothing);
      await tester.runAsync(() async => harness.native.releaseStart());
      await harness.waitForNative(() => harness.native.started.isCompleted);
      await harness.waitForDiscard();
      if (transition == 'unmount') await harness.waitForDisposal();
      expect(find.byType(ChatVoiceRecordingOverlay), findsNothing);
      expect(harness.native.startCalls, 1);
      harness.expectNoDelivery();
    });
  }
}

class _VoiceGestureHarness {
  _VoiceGestureHarness(this.tester, this.native);

  final WidgetTester tester;
  final _VoiceGestureNative native;
  final expanded = ValueNotifier(true);
  int delivered = 0;
  int converted = 0;
  final deliveredFiles = <File>[];
  final receivedSeconds = <int>[];
  Completer<void>? callbackGate;
  bool _removed = false;

  Offset get microphoneCenter =>
      tester.getCenter(find.byIcon(Icons.mic_rounded));

  static Future<_VoiceGestureHarness> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    // Futures awaited during real IO must originate outside FakeAsync.
    final native = (await tester.runAsync(() async => _VoiceGestureNative()))!;
    final harness = _VoiceGestureHarness(tester, native);
    await tester.runAsync(() => native.directory.create(recursive: true));
    Config.cachePath = native.directory.path;
    native.install();
    addTearDown(() async {
      native.releaseStart();
      native.releaseAudioLoad();
      harness.releaseCallback();
      await harness.removeWidget();
      await harness.waitForDisposal();
      harness.expanded.dispose();
      await tester.runAsync(() async {
        for (final file in native.files) {
          if (await file.exists()) await file.delete();
        }
        for (final file in await native.outgoingFiles()) {
          if (await file.exists()) await file.delete();
        }
      });
      native.uninstall();
      await EasyLoading.dismiss(animation: false);
      tester.view.reset();
    });
    await tester.pumpWidget(GetMaterialApp(
      builder: EasyLoading.init(),
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(platform: TargetPlatform.iOS),
      home: Scaffold(
        body: Column(children: [
          const Spacer(),
          ValueListenableBuilder<bool>(
            valueListenable: harness.expanded,
            builder: (_, expanded, __) => HoldToRecordButton(
              expandedPanel: expanded,
              onRecorded: (path, seconds) async {
                harness.delivered++;
                harness.deliveredFiles.add(File(path));
                harness.receivedSeconds.add(seconds);
                await harness.callbackGate?.future;
              },
              onConvertToText: (path, seconds) async {
                harness.converted++;
                harness.deliveredFiles.add(File(path));
                harness.receivedSeconds.add(seconds);
                await harness.callbackGate?.future;
              },
            ),
          ),
        ]),
      ),
    ));
    await tester.pump();
    return harness;
  }

  Future<TestGesture> pressMicrophone(
      {int pointer = 11, bool waitUntilStarted = true}) async {
    final position = microphoneCenter;
    final gesture = await tester
        .runAsync(() => tester.startGesture(position, pointer: pointer));
    await waitForNative(() => native.startEntered.isCompleted);
    if (waitUntilStarted) {
      await waitForNative(() => native.started.isCompleted);
    }
    return gesture!;
  }

  Future<void> cancel(TestGesture gesture) async {
    await tester.runAsync(gesture.cancel);
    await waitForDiscard();
  }

  Future<void> waitForDiscard() async {
    await waitForNative(() => native.stopped.isCompleted);
    var deleted = false;
    for (var attempt = 0; attempt < 100; attempt++) {
      final exists = await tester
          .runAsync(() => Future.wait(native.files.map((f) => f.exists())));
      if (exists!.every((value) => !value)) {
        deleted = true;
        break;
      }
      await _drainFrame();
    }
    expect(deleted, isTrue, reason: 'Cancelled recorder left a temporary file');
    await _drainFrame();
    expect(tester.takeException(), isNull);
  }

  Future<void> removeWidget() async {
    if (_removed) return;
    _removed = true;
    await tester.pumpWidget(const SizedBox());
  }

  Future<void> waitForDisposal() async {
    await waitForNative(() => native.disposed.isCompleted);
  }

  Future<void> waitForRecordingFinished() => waitForNative(() {
        final recorder = tester
            .widget<VoiceRecorderWidget>(find.byType(VoiceRecorderWidget));
        final state = recorder.controller!.snapshot;
        final panel =
            tester.widget<ChatVoiceIdlePanel>(find.byType(ChatVoiceIdlePanel));
        return !state.isStarting &&
            !state.isRecording &&
            !state.isStopping &&
            !panel.busy;
      });

  void releaseCallback() {
    final gate = callbackGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  Future<void> waitForNative(bool Function() finished) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      await _drainFrame();
      if (finished()) return;
    }
    fail('Native recorder did not finish its operation');
  }

  Future<void> _drainFrame() async {
    // Native replies/filesystem IO run in the real zone; widget disposal
    // continuations can be queued in FakeAsync. Advance both deliberately.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
  }

  void expectNoDelivery() {
    expect(delivered, 0);
    expect(converted, 0);
    // A mistaken recorder callback could fail while decoding this tiny mock
    // file and leave delivered==0. No player initialization proves the file
    // never reached the application's recorded/send or conversion workflow.
    expect(native.audioCalls, 0);
    expect(native.files, isNotEmpty);
  }
}

class _VoiceGestureNative {
  static const _record = MethodChannel('com.llfbandit.record/messages');
  static const _permissions =
      MethodChannel('flutter.baseflow.com/permissions/methods');
  static const _paths = MethodChannel('plugins.flutter.io/path_provider');
  static const _audio = MethodChannel('com.ryanheise.just_audio.methods');
  static const _audioSession = MethodChannel('com.ryanheise.audio_session');
  final directory = Directory(
      'E:/openim/.temp/voice-gesture-tests/${DateTime.now().microsecondsSinceEpoch}');
  final files = <File>[];
  final startEntered = Completer<void>();
  final started = Completer<void>();
  final stopped = Completer<void>();
  final disposed = Completer<void>();
  final audioLoadEntered = Completer<void>();
  final audioLoadUris = <String>[];
  final _playerChannels = <MethodChannel>[];
  Completer<void>? startGate;
  Completer<void>? audioLoadGate;
  Duration? audioDuration;
  bool _recording = false;
  String? _path;
  int startCalls = 0;
  int stopCalls = 0;
  int audioCalls = 0;
  int audioInitCalls = 0;
  int audioLoadCalls = 0;
  int audioDisposeCalls = 0;
  bool permissionGranted = true;
  double currentDb = -30;

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_record, (call) async {
      switch (call.method) {
        case 'create':
          return null;
        case 'start':
          startCalls++;
          _path = (call.arguments as Map)['path'] as String;
          if (!startEntered.isCompleted) startEntered.complete();
          await startGate?.future;
          final file = File(_path!);
          files.add(file);
          await file.writeAsBytes([0, 1, 2, 3]);
          _recording = true;
          if (!started.isCompleted) started.complete();
          return null;
        case 'stop':
          stopCalls++;
          _recording = false;
          if (!stopped.isCompleted) stopped.complete();
          return _path;
        case 'dispose':
          if (!disposed.isCompleted) disposed.complete();
          return null;
        case 'isRecording':
          return _recording;
        case 'getAmplitude':
          return {'current': currentDb, 'max': -15.0};
        default:
          throw MissingPluginException(call.method);
      }
    });
    messenger.setMockMethodCallHandler(_permissions, (call) async {
      if (call.method == 'requestPermissions') {
        return {7: permissionGranted ? 1 : 0};
      }
      throw MissingPluginException(call.method);
    });
    messenger.setMockMethodCallHandler(_paths, (call) async {
      if (call.method == 'getTemporaryDirectory') return directory.path;
      throw MissingPluginException(call.method);
    });
    messenger.setMockMethodCallHandler(_audio, (call) async {
      audioCalls++;
      // Negative tests deliberately reject any recorded-file callback. Only
      // positive tests opt into a controllable native duration response.
      if (audioDuration == null) {
        throw PlatformException(code: 'unexpected_audio_callback');
      }
      switch (call.method) {
        case 'init':
          audioInitCalls++;
          _installPlayer((call.arguments as Map)['id'] as String);
          return null;
        case 'disposePlayer':
          audioDisposeCalls++;
          return <String, Object?>{};
        case 'disposeAllPlayers':
          return <String, Object?>{};
        default:
          throw MissingPluginException(call.method);
      }
    });
    messenger.setMockMethodCallHandler(_audioSession, (_) async => null);
  }

  void _installPlayer(String id) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final methods = MethodChannel('com.ryanheise.just_audio.methods.$id');
    final events = MethodChannel('com.ryanheise.just_audio.events.$id');
    final data = MethodChannel('com.ryanheise.just_audio.data.$id');
    _playerChannels.addAll([methods, events, data]);
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(data, (_) async => null);
    messenger.setMockMethodCallHandler(methods, (call) async {
      if (call.method == 'load') {
        audioLoadCalls++;
        _collectUris((call.arguments as Map)['audioSource']);
        if (!audioLoadEntered.isCompleted) audioLoadEntered.complete();
        await audioLoadGate?.future;
        final duration = audioDuration!;
        // just_audio waits for its loading state to pass after load replies.
        // Exercise the real MethodChannel player and event decoding contract.
        ui.channelBuffers.push(
            events.name,
            const StandardMethodCodec().encodeSuccessEnvelope({
              'processingState': 3,
              'updateTime': DateTime.now().millisecondsSinceEpoch,
              'updatePosition': 0,
              'bufferedPosition': duration.inMicroseconds,
              'duration': duration.inMicroseconds,
              'currentIndex': 0,
              'icyMetadata': null,
              'androidAudioSessionId': null,
            }),
            (_) {});
        return {'duration': duration.inMicroseconds};
      }
      return <String, Object?>{};
    });
  }

  void _collectUris(dynamic source) {
    if (source is! Map) return;
    final uri = source['uri'];
    if (uri is String) audioLoadUris.add(uri);
    final children = source['children'];
    if (children is List) {
      for (final child in children) {
        _collectUris(child);
      }
    }
    _collectUris(source['child']);
  }

  Future<List<File>> outgoingFiles() async {
    final outgoing = Directory('${directory.path}/outgoing_media');
    if (!await outgoing.exists()) return [];
    return outgoing
        .list(followLinks: false)
        .where((entry) => entry is File)
        .cast<File>()
        .toList();
  }

  void releaseAudioLoad() {
    final gate = audioLoadGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  void releaseStart() {
    final gate = startGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  void uninstall() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_record, null);
    messenger.setMockMethodCallHandler(_permissions, null);
    messenger.setMockMethodCallHandler(_paths, null);
    messenger.setMockMethodCallHandler(_audio, null);
    messenger.setMockMethodCallHandler(_audioSession, null);
    for (final channel in _playerChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  }
}
