import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:openim/pages/favorites/media/favorite_audio_preview.dart';
import 'package:openim_common/openim_common.dart';

import 'support/favorite_ui_test_support.dart';

class _Platform extends JustAudioPlatform {
  _Player? player;
  bool released = false;
  Duration? duration = const Duration(seconds: 12);
  Completer<void>? loadGate, seekGate;
  int loads = 0, seeks = 0, loadFailures = 0, seekFailures = 0;
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      player = _Player(request.id, this);
  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    released = true;
    await player?.events.close();
    return DisposePlayerResponse();
  }
}

class _Player extends AudioPlayerPlatform {
  _Player(super.id, this.owner);
  final _Platform owner;
  final events = StreamController<PlaybackEventMessage>.broadcast();
  int plays = 0, pauses = 0;
  Duration? sought;
  Map<dynamic, dynamic>? source;
  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => events.stream;
  void ready(
          [Duration position = Duration.zero,
          ProcessingStateMessage state = ProcessingStateMessage.ready]) =>
      events.add(PlaybackEventMessage(
          processingState: state,
          updateTime: DateTime.now(),
          updatePosition: position,
          bufferedPosition: owner.duration ?? Duration.zero,
          duration: owner.duration,
          icyMetadata: null,
          currentIndex: 0,
          androidAudioSessionId: null));
  @override
  Future<LoadResponse> load(LoadRequest request) async {
    owner.loads++;
    source = request.toMap();
    await owner.loadGate?.future;
    if (owner.loadFailures > 0) {
      owner.loadFailures--;
      throw PlatformException(code: 'audio_load_failed');
    }
    ready();
    return LoadResponse(duration: owner.duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    plays++;
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    pauses++;
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    owner.seeks++;
    sought = request.position;
    await owner.seekGate?.future;
    if (owner.seekFailures > 0) {
      owner.seekFailures--;
      throw PlatformException(code: 'audio_seek_failed');
    }
    ready(request.position ?? Duration.zero);
    return SeekResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();
  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();
  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();
  @override
  Future<SetShuffleModeResponse> setShuffleMode(
          SetShuffleModeRequest request) async =>
      SetShuffleModeResponse();
  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
          SetAndroidAudioAttributesRequest request) async =>
      SetAndroidAudioAttributesResponse();
}

Future<void> _mountAudio(WidgetTester tester,
    {String? title,
    int? size,
    Duration? hint,
    File? file,
    bool dark = false,
    double textScale = 1}) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(favoriteUiHost(
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FavoriteAudioPreview(
              file: file ?? File('verified-local-audio.m4a').absolute,
              title: title,
              fileSizeBytes: size,
              durationHint: hint,
            ),
          ]),
        ),
      ),
      dark: dark,
      textScale: textScale,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
}

Future<void> _nativeTurn(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });
  await tester.pump();
}

Future<void> _tapAudio(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.byKey(const ValueKey('favorite-audio-play')));
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });
  await tester.pump();
}

Future<void> _closeAudio(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _nativeTurn(tester);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late JustAudioPlatform previous;
  late _Platform platform;
  const channel = MethodChannel('com.ryanheise.audio_session');
  setUp(() {
    previous = JustAudioPlatform.instance;
    platform = _Platform();
    JustAudioPlatform.instance = platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel, (call) async => call.method == 'setActive' ? true : null);
  });
  tearDown(() {
    JustAudioPlatform.instance = previous;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
      'audio plays only on tap, seeks, pauses in background and releases',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(favoriteUiHost(Scaffold(
          body: FavoriteAudioPreview(
              file: File('verified-local-audio.m4a').absolute))));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('favorite-audio-play')), findsOneWidget);
    expect(platform.player!.source.toString(), contains('file:'));
    expect(platform.player!.plays, 0);
    expect(find.text('0:00'), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('favorite-audio-play')));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    expect(platform.player!.plays, 1);
    final slider = tester
        .widget<Slider>(find.byKey(const ValueKey('favorite-audio-seek')));
    await tester.runAsync(() async {
      slider.onChanged!(6000);
      slider.onChangeEnd!(6000);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    expect(platform.player!.sought, const Duration(seconds: 6));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    expect(platform.player!.pauses, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(platform.released, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('metadata loading keeps geometry and decoded duration wins',
      (tester) async {
    platform.duration = const Duration(seconds: 7);
    platform.loadGate = Completer<void>();
    await _mountAudio(tester,
        title: '   ', size: 44 * 1024, hint: const Duration(seconds: 6));
    expect(find.text('语音收藏'), findsOneWidget);
    expect(find.text('44.0 KB'), findsOneWidget);
    expect(find.text('0:06'), findsOneWidget);
    expect(find.text('0:07'), findsNothing);
    expect(
        tester
            .widget<IconButton>(
                find.byKey(const ValueKey('favorite-audio-play')))
            .onPressed,
        isNull);
    final height = tester
        .getSize(find.byKey(const ValueKey('favorite-audio-preview')))
        .height;
    platform.loadGate!.complete();
    await _nativeTurn(tester);
    await tester.pumpAndSettle();
    expect(find.text('0:06'), findsNothing);
    expect(find.text('0:07'), findsOneWidget);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('favorite-audio-preview')))
            .height,
        height);
    expect(platform.player!.plays, 0);
    await _closeAudio(tester);
  });

  testWidgets('metadata duration is used only while native duration is absent',
      (tester) async {
    platform.duration = null;
    await _mountAudio(tester, hint: const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('0:06'), findsOneWidget);
    platform.duration = const Duration(milliseconds: 7900);
    platform.player!.ready();
    await _nativeTurn(tester);
    expect(find.text('0:06'), findsNothing);
    expect(find.text('0:07'), findsOneWidget);
    await _closeAudio(tester);
  });

  testWidgets('load failure retries in place without autoplay', (tester) async {
    platform.loadFailures = 1;
    await _mountAudio(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('favorite-audio-error')), findsOneWidget);
    final height = tester
        .getSize(find.byKey(const ValueKey('favorite-audio-preview')))
        .height;
    await _tapAudio(tester);
    await tester.pumpAndSettle();
    expect(platform.loads, 2);
    expect(find.byKey(const ValueKey('favorite-audio-error')), findsNothing);
    expect(platform.player!.plays, 0);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('favorite-audio-preview')))
            .height,
        height);
    expect(tester.takeException(), isNull);
    await _closeAudio(tester);
  });

  testWidgets(
      'same-frame playback taps issue one command and completed replays',
      (tester) async {
    await _mountAudio(tester);
    await tester.pumpAndSettle();
    final tap = tester
        .widget<IconButton>(find.byKey(const ValueKey('favorite-audio-play')))
        .onPressed!;
    tap();
    tap();
    await _nativeTurn(tester);
    expect(platform.player!.plays, 1);
    platform.player!
        .ready(const Duration(seconds: 12), ProcessingStateMessage.completed);
    await _nativeTurn(tester);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await _tapAudio(tester);
    expect(platform.player!.sought, Duration.zero);
    expect(platform.player!.plays, 2);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    await _closeAudio(tester);
  });

  testWidgets('seek previews while dragging and commits once at release',
      (tester) async {
    await _mountAudio(tester);
    await tester.pumpAndSettle();
    final slider = tester
        .widget<Slider>(find.byKey(const ValueKey('favorite-audio-seek')));
    final seeks = platform.seeks;
    slider.onChangeStart!(0);
    slider.onChanged!(3000);
    slider.onChanged!(6000);
    await tester.pump();
    expect(platform.seeks, seeks);
    expect(find.text('0:06'), findsOneWidget);
    slider.onChangeEnd!(6000);
    slider.onChangeEnd!(8000);
    await _nativeTurn(tester);
    expect(platform.seeks, seeks + 1);
    expect(platform.player!.sought, const Duration(seconds: 6));
    await _closeAudio(tester);
  });

  testWidgets('seek failure exposes retry and clears transient slider state',
      (tester) async {
    await _mountAudio(tester);
    await tester.pumpAndSettle();
    platform.seekFailures = 1;
    final slider = tester
        .widget<Slider>(find.byKey(const ValueKey('favorite-audio-seek')));
    slider.onChanged!(6000);
    slider.onChangeEnd!(6000);
    await _nativeTurn(tester);
    expect(find.byKey(const ValueKey('favorite-audio-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _tapAudio(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('favorite-audio-error')), findsNothing);
    expect(find.text('0:00'), findsOneWidget);
    expect(platform.player!.plays, 0);
    await _closeAudio(tester);
  });

  testWidgets('background during replay prevents a late play after resuming',
      (tester) async {
    await _mountAudio(tester);
    await tester.pumpAndSettle();
    await _tapAudio(tester);
    platform.player!
        .ready(const Duration(seconds: 12), ProcessingStateMessage.completed);
    await _nativeTurn(tester);
    platform.seekGate = Completer<void>();
    await _tapAudio(tester);
    expect(platform.player!.sought, Duration.zero);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    platform.seekGate!.complete();
    await _nativeTurn(tester);
    expect(platform.player!.plays, 1);
    await _closeAudio(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing preview releases player but preserves loader-owned file',
      (tester) async {
    final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('favorite-audio-owner-test-')))!;
    final file = (await tester.runAsync(
        () => File('${directory.path}/audio.m4a').writeAsBytes([1, 2, 3])))!;
    await _mountAudio(tester, file: file);
    await tester.pumpAndSettle();
    await _closeAudio(tester);
    expect(platform.released, isTrue);
    expect(await tester.runAsync(file.exists), isTrue);
    await tester.runAsync(() => directory.delete(recursive: true));
  });

  for (final dark in [false, true]) {
    testWidgets('320px, 2x text uses app colors without overflow ($dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _mountAudio(tester,
          title: '一个非常长的收藏语音原始文件名-会议记录.m4a',
          size: 18 * 1024 * 1024,
          dark: dark,
          textScale: 2);
      await tester.pumpAndSettle();
      final play = tester.widget<IconButton>(
          find.byKey(const ValueKey('favorite-audio-play')));
      expect(play.style!.backgroundColor!.resolve({}), AppTokens.accent);
      expect(tester.getSize(find.byKey(const ValueKey('favorite-audio-play'))),
          const Size(56, 56));
      final sliderTheme = tester.widget<SliderTheme>(find
          .ancestor(
              of: find.byKey(const ValueKey('favorite-audio-seek')),
              matching: find.byType(SliderTheme))
          .first);
      expect(sliderTheme.data.activeTrackColor, AppTokens.accent);
      expect(sliderTheme.data.inactiveTrackColor, AppTokens.border(dark: dark));
      final time = tester
          .widget<Text>(find.byKey(const ValueKey('favorite-audio-duration')));
      expect(time.style!.color, AppTokens.textSecondary(dark: dark));
      expect(time.style!.fontFeatures!.single.feature, 'tnum');
      expect(tester.takeException(), isNull);
      await _closeAudio(tester);
    });

    testWidgets('download loading and retry use the same audio frame ($dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget frame({String? error, VoidCallback? retry}) => favoriteUiHost(
          Scaffold(
              body: Padding(
            padding: const EdgeInsets.all(20),
            child: FavoriteAudioPreview.placeholder(
              fileSizeBytes: 42 * 1024,
              durationHint: const Duration(seconds: 7),
              progress: .5,
              error: error,
              onRetry: retry,
            ),
          )),
          dark: dark,
          textScale: 2);
      await tester.pumpWidget(frame());
      await tester.pumpAndSettle();
      final height = tester
          .getSize(find.byKey(const ValueKey('favorite-audio-preview')))
          .height;
      expect(find.text('0:07'), findsOneWidget);
      final progress = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator));
      expect(progress.color, AppTokens.onAccent);
      expect(progress.value, .5);
      var retries = 0;
      await tester
          .pumpWidget(frame(error: '原件访问已过期，请重试预览', retry: () => retries++));
      await tester.pumpAndSettle();
      expect(
          tester
              .getSize(find.byKey(const ValueKey('favorite-audio-preview')))
              .height,
          height);
      await tester.tap(find.byKey(const ValueKey('favorite-audio-play')));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
