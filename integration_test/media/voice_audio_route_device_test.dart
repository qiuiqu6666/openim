import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/voice/voice_playback_source.dart';

Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (ready()) return;
  }
  throw StateError('Media operation did not complete');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'native voice route preserves position and image browsing leaves audio alone',
      (tester) async {
    final coordinator = MediaCoordinator.instance;
    await coordinator.initialize();
    final original = coordinator.output.value;
    final directory = await Directory.systemTemp.createTemp('voice-route-');
    final file = File('${directory.path}/silence.wav');
    // Silent PCM exercises native playback/progress without producing test noise.
    final bytes = Uint8List(44 + 16000 * 2 * 30);
    final data = ByteData.sublistView(bytes);
    void word(int offset, String value) =>
        bytes.setRange(offset, offset + value.length, value.codeUnits);
    word(0, 'RIFF');
    data.setUint32(4, bytes.length - 8, Endian.little);
    word(8, 'WAVE');
    word(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, 16000, Endian.little);
    data.setUint32(28, 32000, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    word(36, 'data');
    data.setUint32(40, bytes.length - 44, Endian.little);
    await file.writeAsBytes(bytes);
    final voice = VoicePlaybackController(
        messages: () => [],
        sourceLoader: (_) async => VoicePlaybackSource.file(file.path));
    StreamSubscription<Duration>? positionSub;
    var position = Duration.zero;
    final snapshots = <String, Object?>{};
    try {
      final image = (await rootBundle.load(
              'packages/openim_common/assets/images/ic_archive_99chat.png'))
          .buffer
          .asUint8List();
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => GetMaterialApp(
              navigatorKey: nav,
              home: const Scaffold(body: Center(child: Text('音频路由验收'))))));
      await coordinator.setOutput(VoiceOutput.speaker);
      final message = Message.fromJson({
        'clientMsgID': 'route-check',
        'soundElem': {'duration': 30, 'soundPath': file.path}
      });
      unawaited(voice.toggle(message));
      await waitFor(tester, () => voice.playing);
      positionSub = voice.positionStream!.listen((value) => position = value);
      await waitFor(tester, () => position.inMilliseconds > 300);
      final before = position;
      snapshots['speaker'] =
          await MediaCoordinator.channel.invokeMapMethod('snapshot');
      await coordinator.setOutput(VoiceOutput.earpiece);
      await tester.pump(const Duration(milliseconds: 400));
      snapshots['earpiece'] =
          await MediaCoordinator.channel.invokeMapMethod('snapshot');
      final speakerState = snapshots['speaker'] as Map;
      final receiverState = snapshots['earpiece'] as Map;
      expect(speakerState['speaker'], isTrue);
      expect(receiverState['speaker'], isFalse);
      if (Platform.isAndroid) {
        if (speakerState.containsKey('deviceType')) {
          expect(speakerState['deviceType'], 2);
          expect(receiverState['deviceType'], 1);
        } else {
          expect(speakerState['speakerphone'], isTrue);
          expect(receiverState['speakerphone'], isFalse);
        }
      } else if (Platform.isIOS) {
        expect(speakerState['outputs'], contains('Speaker'));
        expect(receiverState['outputs'], contains('Receiver'));
      }
      expect(voice.playing, isTrue);
      expect(position, greaterThanOrEqualTo(before));
      final inEarpiece = position;
      await coordinator.setOutput(VoiceOutput.speaker);
      await tester.pump(const Duration(milliseconds: 400));
      expect(position, greaterThanOrEqualTo(inEarpiece));
      unawaited(nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => MediaBrowser(initialIndex: 0, sources: [
                MediaSource(thumbnail: '', bytes: image, tag: 'image-a'),
                MediaSource(thumbnail: '', bytes: image, tag: 'image-b'),
              ]))));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(MediaBrowser), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(voice.playing, isTrue);
      expect(position, greaterThan(inEarpiece));
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(voice.playing, isTrue);
      final recording =
          await coordinator.acquire(MediaKind.recording, () async {});
      expect(voice.playing, isFalse);
      await voice.toggle(message);
      expect(voice.playing, isFalse);
      await recording!.release(stopped: true);
      expect(voice.playing, isFalse);
      snapshots['positionMs'] = position.inMilliseconds;
      binding.reportData = snapshots;
      debugPrint('VOICE_ROUTE_EVIDENCE: $snapshots');
    } finally {
      await positionSub?.cancel();
      await voice.stop();
      voice.dispose();
      await coordinator.stop();
      await coordinator.setOutput(original);
      await tester.pumpWidget(const SizedBox());
      await file.delete();
      await directory.delete();
    }
  });
}
