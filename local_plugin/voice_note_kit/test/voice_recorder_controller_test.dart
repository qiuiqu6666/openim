import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_note_kit/voice_note_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('repeated start and stop deliver one native recording',
      (tester) async {
    final recorder = await _RecorderHarness.mount(tester);
    await tester.runAsync(() async {
      await Future.wait([
        recorder.controller.start(),
        recorder.controller.start(),
      ]);
    });
    expect(recorder.native.startCalls, 1);
    expect(recorder.controller.snapshot.isRecording, isTrue);
    expect(recorder.controller.snapshot.isStarting, isFalse);

    // Metering is native state, not an animation synthesized by the widget.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 140));
    });
    expect(recorder.controller.snapshot.amplitude, closeTo(.5, .001));
    await tester.runAsync(() async {
      await Future.wait([
        recorder.controller.stop(),
        recorder.controller.stop(),
      ]);
    });
    expect(recorder.native.stopCalls, 1);
    expect(recorder.recorded, hasLength(1));
    _expectIdle(recorder.controller.snapshot);
    final delivered = recorder.recorded.single;
    expect(await tester.runAsync(() => delivered.exists()), isTrue);

    // The consumer owns a delivered file; native teardown must preserve it
    // while an asynchronous copy, duration check or text review uses it.
    // In particular, teardown must not fall back to native cancel on that file.
    recorder.native.stopFailures = 1;
    await recorder.unmount();
    expect(recorder.native.stopCalls, 1);
    expect(recorder.native.cancelCalls, 0);
    expect(await tester.runAsync(() => delivered.exists()), isTrue);
    expect(recorder.errors, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final cancellation in ['cancel', 'stop']) {
    testWidgets('$cancellation during native start discards the late file',
        (tester) async {
      final recorder = await _RecorderHarness.mount(tester);
      await tester.runAsync(() async {
        recorder.native.startGate = Completer<void>();
        final starting = recorder.controller.start();
        await recorder.native.startEntered.future
            .timeout(const Duration(seconds: 3));
        expect(recorder.controller.snapshot.isStarting, isTrue);
        final ending = cancellation == 'cancel'
            ? recorder.controller.cancel()
            : recorder.controller.stop();
        recorder.native.releaseStart();
        await Future.wait([starting, ending]);
      });
      expect(recorder.native.startCalls, 1);
      expect(recorder.native.stopCalls, 1);
      expect(recorder.recorded, isEmpty);
      expect(recorder.errors, isEmpty);
      _expectIdle(recorder.controller.snapshot);
      expect(await recorder.filesExist(), everyElement(isFalse));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  for (final cancellation in ['cancel', 'stop']) {
    testWidgets(
        '$cancellation before permission resolves never starts native audio',
        (tester) async {
      final recorder = await _RecorderHarness.mount(tester);
      await tester.runAsync(() async {
        recorder.native.permissionGate = Completer<void>();
        final starting = recorder.controller.start();
        await recorder.native.permissionEntered.future
            .timeout(const Duration(seconds: 3));
        expect(recorder.controller.snapshot.isStarting, isTrue);
        final ending = cancellation == 'cancel'
            ? recorder.controller.cancel()
            : recorder.controller.stop();
        recorder.native.releasePermission();
        await Future.wait([starting, ending]);
      });
      expect(recorder.native.startCalls, 0);
      expect(recorder.native.stopCalls, 0);
      expect(recorder.recorded, isEmpty);
      expect(recorder.errors, isEmpty);
      _expectIdle(recorder.controller.snapshot);

      // A granted permission response from the cancelled gesture must not
      // poison the next user attempt or start recording on its own.
      await tester.runAsync(recorder.controller.start);
      expect(recorder.native.startCalls, 1);
      expect(recorder.controller.snapshot.isRecording, isTrue);
      await tester.runAsync(recorder.controller.cancel);
      expect(recorder.recorded, isEmpty);
    });
  }

  for (final finishing in ['stop', 'cancel']) {
    testWidgets('$finishing failure releases native audio and permits retry',
        (tester) async {
      final recorder = await _RecorderHarness.mount(tester);
      await tester.runAsync(recorder.controller.start);
      recorder.native.stopFailures = 1;
      await tester.runAsync(finishing == 'stop'
          ? recorder.controller.stop
          : recorder.controller.cancel);
      expect(recorder.native.isRecording, isFalse);
      expect(recorder.recorded, isEmpty);
      expect(recorder.errors, hasLength(1));
      expect(recorder.errors.single, contains('Native stop failed'));
      expect(await recorder.filesExist(), everyElement(isFalse));
      _expectIdle(recorder.controller.snapshot);

      await tester.runAsync(recorder.controller.start);
      await tester.runAsync(recorder.controller.stop);
      expect(recorder.native.startCalls, 2);
      expect(recorder.recorded, hasLength(1));
      expect(recorder.errors, hasLength(1));
      _expectIdle(recorder.controller.snapshot);
    });
  }

  testWidgets(
      'persistent stop failures release the recorder without delivering a file',
      (tester) async {
    final recorder = await _RecorderHarness.mount(tester);
    await tester.runAsync(recorder.controller.start);
    recorder.native.stopFailures = 99;
    await tester.runAsync(recorder.controller.stop);
    expect(recorder.native.isRecording, isFalse);
    expect(recorder.native.cancelCalls, 0);
    expect(recorder.native.disposeCalls, 1);
    expect(recorder.recorded, isEmpty);
    expect(recorder.errors, hasLength(1));
    expect(await recorder.filesExist(), everyElement(isFalse));
    _expectIdle(recorder.controller.snapshot);

    recorder.native.stopFailures = 0;
    await tester.runAsync(recorder.controller.start);
    expect(recorder.native.createCalls, 2);
    expect(recorder.native.concurrentCreateCalls, 0);
    await tester.runAsync(recorder.controller.stop);
    expect(recorder.recorded, hasLength(1));
    expect(recorder.errors, hasLength(1));
  });

  testWidgets(
      'cancel cleanup bypasses unawaited native cancel and releases before retry',
      (tester) async {
    final recorder = await _RecorderHarness.mount(tester);
    await tester.runAsync(recorder.controller.start);
    recorder.native.stopFailures = 99;
    // The pinned platform's native cancel Future drops method-channel errors.
    // Leave an error armed to ensure cleanup never calls that unsafe branch.
    recorder.native.cancelFailures = 1;
    await tester.runAsync(recorder.controller.cancel);
    expect(recorder.native.isRecording, isFalse);
    expect(recorder.native.createCalls, 1);
    expect(recorder.native.disposeCalls, 1);
    expect(recorder.native.cancelCalls, 0);
    expect(recorder.recorded, isEmpty);
    expect(recorder.errors, hasLength(1));
    expect(await recorder.filesExist(), everyElement(isFalse));
    _expectIdle(recorder.controller.snapshot);

    recorder.native.stopFailures = 0;
    await tester.runAsync(recorder.controller.start);
    expect(recorder.native.createCalls, 2);
    expect(recorder.native.concurrentCreateCalls, 0);
    expect(recorder.controller.snapshot.isRecording, isTrue);
    await tester.runAsync(recorder.controller.stop);
    expect(recorder.recorded, hasLength(1));
    expect(recorder.errors, hasLength(1));
  });

  testWidgets(
      'failed release prevents a replacement until the old recorder is released',
      (tester) async {
    final recorder = await _RecorderHarness.mount(tester);
    await tester.runAsync(recorder.controller.start);
    recorder.native.stopFailures = 99;
    recorder.native.disposeFailures = 1;
    await tester.runAsync(recorder.controller.cancel);
    expect(recorder.native.isRecording, isTrue);
    expect(recorder.native.createCalls, 1);
    expect(recorder.native.cancelCalls, 0);
    expect(recorder.recorded, isEmpty);
    expect(recorder.errors, hasLength(1));
    expect(await recorder.filesExist(), everyElement(isFalse));
    _expectIdle(recorder.controller.snapshot);

    // Even if another release attempt fails, a retry must not create a new
    // recorder alongside the native microphone session that still exists.
    recorder.native.disposeFailures = 1;
    await tester.runAsync(recorder.controller.start);
    expect(recorder.native.createCalls, 1);
    expect(recorder.native.startCalls, 1);
    expect(recorder.native.concurrentCreateCalls, 0);
    expect(recorder.native.isRecording, isFalse);
    expect(recorder.errors, hasLength(2));
    _expectIdle(recorder.controller.snapshot);

    recorder.native.stopFailures = 0;
    await tester.runAsync(recorder.controller.start);
    expect(recorder.native.createCalls, 2);
    expect(recorder.native.concurrentCreateCalls, 0);
    expect(recorder.controller.snapshot.isRecording, isTrue);
    await tester.runAsync(recorder.controller.stop);
    expect(recorder.recorded, hasLength(1));
    expect(recorder.errors, hasLength(2));
  });

  testWidgets('denied microphone permission returns a specific error and idle',
      (tester) async {
    final recorder = await _RecorderHarness.mount(tester);
    recorder.native.permissionGranted = false;
    await tester.runAsync(recorder.controller.start);
    expect(recorder.errors, ['请允许麦克风权限']);
    expect(recorder.native.startCalls, 0);
    expect(recorder.recorded, isEmpty);
    _expectIdle(recorder.controller.snapshot);
    await tester.pump();
    expect(find.text('idle'), findsOneWidget);

    // Granting permission afterwards must allow the same recorder to retry.
    recorder.native.permissionGranted = true;
    await tester.runAsync(recorder.controller.start);
    expect(recorder.controller.snapshot.isRecording, isTrue);
    await tester.runAsync(recorder.controller.cancel);
    expect(recorder.recorded, isEmpty);
  });

  testWidgets('unmount while recording stops and deletes without a callback',
      (tester) async {
    final recorder = await _RecorderHarness.mount(tester);
    var notifications = 0;
    recorder.controller.addListener(() => notifications++);
    await tester.runAsync(recorder.controller.start);
    expect(recorder.controller.snapshot.isRecording, isTrue);
    expect(await recorder.filesExist(), everyElement(isTrue));
    final beforeUnmount = notifications;

    await recorder.unmount();
    expect(recorder.native.stopCalls, 1);
    expect(recorder.native.disposeCalls, 1);
    expect(recorder.recorded, isEmpty);
    expect(recorder.errors, isEmpty);
    expect(await recorder.filesExist(), everyElement(isFalse));
    _expectIdle(recorder.controller.snapshot);
    expect(notifications, beforeUnmount);
    await tester.runAsync(() async {
      await recorder.controller.start();
      await recorder.controller.stop();
      await recorder.controller.cancel();
    });
    expect(recorder.native.startCalls, 1);
    expect(notifications, beforeUnmount);
    expect(tester.takeException(), isNull);
  });

  testWidgets('native start failure cleans the partial file and allows retry',
      (tester) async {
    final recorder = await _RecorderHarness.mount(tester);
    recorder.native.failNextStart = true;
    await tester.runAsync(recorder.controller.start);
    expect(recorder.errors.single, contains('Microphone unavailable'));
    _expectIdle(recorder.controller.snapshot);
    expect(recorder.recorded, isEmpty);
    expect(await recorder.filesExist(), everyElement(isFalse));
    await tester.pump();
    expect(find.text('idle'), findsOneWidget);

    await tester.runAsync(recorder.controller.start);
    expect(recorder.native.startCalls, 2);
    expect(recorder.controller.snapshot.isRecording, isTrue);
    await tester.runAsync(recorder.controller.stop);
    expect(recorder.recorded, hasLength(1));
    expect(recorder.errors, hasLength(1));
    _expectIdle(recorder.controller.snapshot);
    expect(tester.takeException(), isNull);
  });

  test('a controller rejects a second owner and ignores detached publications',
      () async {
    final controller = VoiceRecorderController();
    final first = Object();
    final second = Object();
    var starts = 0;
    var stops = 0;
    var cancels = 0;
    var notifications = 0;
    Future<void> start() async => starts++;
    Future<void> stop() async => stops++;
    Future<void> cancel() async => cancels++;
    void attach(Object owner) => controller.attach(
        owner: owner, start: start, stop: stop, cancel: cancel);
    controller.addListener(() => notifications++);
    attach(first);
    attach(first);
    expect(() => attach(second), throwsStateError);
    controller.detach(second);
    await controller.start();
    expect(starts, 1);
    controller.updateSnapshot(
        first, const VoiceRecorderSnapshot(isRecording: true, seconds: 2));
    expect(notifications, 1);
    controller.updateSnapshot(
        first, const VoiceRecorderSnapshot(isRecording: true, seconds: 2));
    expect(notifications, 1);
    controller.detach(first);
    controller.updateSnapshot(
        first, const VoiceRecorderSnapshot(isRecording: true, seconds: 3));
    await controller.start();
    await controller.stop();
    await controller.cancel();
    expect(starts, 1);
    expect(stops, 0);
    expect(cancels, 0);
    expect(notifications, 1);
    _expectIdle(controller.snapshot);

    attach(second);
    await controller.start();
    expect(starts, 2);
    controller.dispose();
    controller.updateSnapshot(
        second, const VoiceRecorderSnapshot(isRecording: true));
    await controller.start();
    await controller.stop();
    await controller.cancel();
    expect(starts, 2);
    expect(stops, 0);
    expect(cancels, 0);
    expect(notifications, 1);
    _expectIdle(controller.snapshot);
    expect(() => attach(second), throwsStateError);
  });
}

void _expectIdle(VoiceRecorderSnapshot snapshot) {
  expect(snapshot.isStarting, isFalse);
  expect(snapshot.isRecording, isFalse);
  expect(snapshot.isStopping, isFalse);
  expect(snapshot.seconds, 0);
  expect(snapshot.amplitude, 0);
}

class _RecorderHarness {
  _RecorderHarness(this.tester, this.native);

  final WidgetTester tester;
  final _NativeRecorder native;
  final controller = VoiceRecorderController();
  final recorded = <File>[];
  final errors = <String>[];
  bool _unmounted = false;

  static Future<_RecorderHarness> mount(WidgetTester tester) async {
    final native = (await tester.runAsync(() async => _NativeRecorder()))!;
    final harness = _RecorderHarness(tester, native);
    await tester.runAsync(() => native.directory.create(recursive: true));
    native.install();
    addTearDown(() async {
      native.releaseStart();
      native.releasePermission();
      await harness.unmount();
      harness.controller.dispose();
      await tester.runAsync(() async {
        for (final file in native.files) {
          if (await file.exists()) await file.delete();
        }
      });
      native.uninstall();
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VoiceRecorderWidget(
          controller: harness.controller,
          enableHapticFeedback: false,
          permissionNotGrantedMessage: '请允许麦克风权限',
          onRecorded: (file) => harness.recorded.add(file),
          onError: harness.errors.add,
          actionWhenCancel: () {},
          builder: (_, controller) {
            final snapshot = controller.snapshot;
            final label = snapshot.isStarting
                ? 'starting'
                : snapshot.isRecording
                    ? 'recording'
                    : snapshot.isStopping
                        ? 'stopping'
                        : 'idle';
            return Text(label);
          },
        ),
      ),
    ));
    return harness;
  }

  Future<List<bool>?> filesExist() => tester.runAsync(() async {
        return Future.wait(native.files.map((file) => file.exists()));
      });

  Future<void> unmount() async {
    if (_unmounted) return;
    _unmounted = true;
    await tester.pumpWidget(const SizedBox());
    // Disposal starts in Flutter's fake frame zone, while file IO finishes
    // in real async. Keep draining frames until that cleanup has completed.
    for (var frame = 0; frame < 150 && !native.disposed.isCompleted; frame++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.runAsync(() async {
      await native.disposed.future.timeout(const Duration(seconds: 3));
    });
    await tester.pump();
  }
}

class _NativeRecorder {
  static const _record = MethodChannel('com.llfbandit.record/messages');
  static const _permissions =
      MethodChannel('flutter.baseflow.com/permissions/methods');
  static const _paths = MethodChannel('plugins.flutter.io/path_provider');
  final directory = Directory('E:/openim/.temp/voice-controller-tests');
  final files = <File>[];
  // These native signals cross the tester's fake-async/runAsync boundary.
  final startEntered = Completer<void>.sync();
  final permissionEntered = Completer<void>.sync();
  final disposed = Completer<void>.sync();
  Completer<void>? startGate;
  Completer<void>? permissionGate;
  bool permissionGranted = true;
  bool failNextStart = false;
  int stopFailures = 0;
  int cancelFailures = 0;
  int disposeFailures = 0;
  bool _recording = false;
  bool get isRecording => _recording;
  String? _path;
  int createCalls = 0;
  int concurrentCreateCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  int disposeCalls = 0;

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_record, (call) async {
      switch (call.method) {
        case 'create':
          createCalls++;
          if (_recording) concurrentCreateCalls++;
          return null;
        case 'start':
          startCalls++;
          _path = (call.arguments as Map)['path'] as String;
          if (!startEntered.isCompleted) startEntered.complete();
          await startGate?.future;
          final file = File(_path!);
          files.add(file);
          await file.writeAsBytes([0, 1, 2, 3]);
          if (failNextStart) {
            failNextStart = false;
            throw PlatformException(
                code: 'record_start_failed', message: 'Microphone unavailable');
          }
          _recording = true;
          return null;
        case 'stop':
          stopCalls++;
          if (stopFailures > 0) {
            stopFailures--;
            throw PlatformException(
                code: 'record_stop_failed', message: 'Native stop failed');
          }
          _recording = false;
          return _path;
        case 'cancel':
          cancelCalls++;
          if (cancelFailures > 0) {
            cancelFailures--;
            throw PlatformException(
                code: 'record_cancel_failed', message: 'Native cancel failed');
          }
          _recording = false;
          final path = _path;
          if (path != null) {
            final file = File(path);
            if (await file.exists()) await file.delete();
          }
          return null;
        case 'dispose':
          disposeCalls++;
          if (disposeFailures > 0) {
            disposeFailures--;
            throw PlatformException(
                code: 'record_dispose_failed',
                message: 'Native release failed');
          }
          _recording = false;
          if (!disposed.isCompleted) disposed.complete();
          return null;
        case 'isRecording':
          return _recording;
        case 'getAmplitude':
          return {'current': -30.0, 'max': -15.0};
        default:
          throw MissingPluginException(call.method);
      }
    });
    messenger.setMockMethodCallHandler(_permissions, (call) async {
      if (call.method == 'requestPermissions') {
        if (!permissionEntered.isCompleted) permissionEntered.complete();
        await permissionGate?.future;
        return {7: permissionGranted ? 1 : 0};
      }
      throw MissingPluginException(call.method);
    });
    messenger.setMockMethodCallHandler(_paths, (call) async {
      if (call.method == 'getTemporaryDirectory') return directory.path;
      throw MissingPluginException(call.method);
    });
  }

  void releaseStart() {
    final gate = startGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  void releasePermission() {
    final gate = permissionGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  void uninstall() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_record, null);
    messenger.setMockMethodCallHandler(_permissions, null);
    messenger.setMockMethodCallHandler(_paths, null);
  }
}
