import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_live/src/platform/call_picture_in_picture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('openim_call_pip');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  String? session;

  Future<void> state(String phase, {String? sessionID}) async {
    final response = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('state', {
        'session': sessionID ?? session,
        'phase': phase,
      })),
      (_) => response.complete(),
    );
    await response.future;
  }

  setUp(() {
    calls = [];
    session = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'configure') {
        session = (call.arguments as Map)['session'] as String;
        return {
          'supported': true,
          'ready': true,
          'backgroundCameraSupported': true,
        };
      }
      return true;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('native state drives PiP, restore and close are delivered once',
      () async {
    var restored = 0;
    var closed = 0;
    final controller = CallPictureInPictureController(
      platform: TargetPlatform.android,
      onRestore: () => restored++,
      onClosed: () => closed++,
    );
    addTearDown(controller.dispose);
    expect(await controller.configure(enabled: true), isTrue);
    expect(controller.backgroundCameraSupported, isTrue);
    expect(await controller.enter(), isTrue);
    expect(controller.entering, isTrue);
    expect(controller.active, isFalse);
    expect(await controller.enter(), isFalse);
    expect(calls.where((call) => call.method == 'enter'), hasLength(1));
    await state('active');
    expect(controller.active, isTrue);
    expect(controller.entering, isFalse);
    await state('restored');
    await state('restored');
    expect(restored, 1);
    expect(controller.active, isFalse);
    await state('entering');
    await state('active');
    await state('closed');
    await state('closed');
    expect(closed, 1);
  });

  test('stopped and replaced calls reject stale native events', () async {
    var closed = 0;
    final controller = CallPictureInPictureController(
      platform: TargetPlatform.android,
      onClosed: () => closed++,
    );
    addTearDown(controller.dispose);
    await controller.configure(enabled: true);
    final oldSession = session;
    await state('active');
    await controller.stop();
    expect(controller.active, isFalse);
    await state('closed', sessionID: oldSession);
    expect(closed, 0);
    await controller.configure(enabled: true);
    expect(session, isNot(oldSession));
    await state('active', sessionID: oldSession);
    expect(controller.active, isFalse);
    await state('active');
    expect(controller.active, isTrue);
  });

  test('late capability response cannot rearm a stopped call', () async {
    final gate = Completer<Map<String, bool>>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'configure') return gate.future;
      return true;
    });
    final controller =
        CallPictureInPictureController(platform: TargetPlatform.android);
    addTearDown(controller.dispose);
    final pending = controller.configure(enabled: true);
    await Future<void>.delayed(Duration.zero);
    await controller.stop();
    gate.complete({'supported': true, 'ready': true});
    expect(await pending, isFalse);
    expect(await controller.enter(), isFalse);
  });

  test('loss of native video capability restores application call UI',
      () async {
    var closed = 0;
    final controller = CallPictureInPictureController(
      platform: TargetPlatform.iOS,
      onClosed: () => closed++,
    );
    addTearDown(controller.dispose);
    await controller.configure(enabled: true, remoteVideoTrackId: 'video-one');
    final retiredSession = session;
    await state('active');
    expect(controller.active, isTrue);
    messenger.setMockMethodCallHandler(
        channel,
        (call) async => {
              'supported': false,
              'ready': false,
              'backgroundCameraSupported': false,
            });
    expect(await controller.configure(enabled: true), isFalse);
    expect(controller.active, isFalse);
    expect(controller.entering, isFalse);
    expect(await controller.enter(), isFalse);
    await state('active', sessionID: retiredSession);
    expect(controller.active, isFalse);
    expect(closed, 0); // A remote camera change must not hang up the call.
  });

  test('missing plugin, native refusal and audio-only iOS safely fall back',
      () async {
    final controller =
        CallPictureInPictureController(platform: TargetPlatform.iOS);
    addTearDown(controller.dispose);
    messenger.setMockMethodCallHandler(
        channel, (_) async => throw MissingPluginException());
    expect(await controller.configure(enabled: true), isFalse);
    messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
              'supported': false,
              'ready': false,
              'backgroundCameraSupported': false,
            });
    expect(await controller.configure(enabled: true), isFalse);
    expect(await controller.enter(), isFalse);
    expect(controller.backgroundCameraSupported, isFalse);
    messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'configure'
            ? {'supported': true, 'ready': true}
            : throw PlatformException(code: 'PIP_DISABLED'));
    await controller.configure(enabled: true, remoteVideoTrackId: 'real-track');
    expect(await controller.enter(), isFalse);
    expect(controller.entering, isFalse);
  });

  testWidgets('accepted entry without native activation recovers after timeout',
      (tester) async {
    final controller =
        CallPictureInPictureController(platform: TargetPlatform.android);
    addTearDown(controller.dispose);
    await controller.configure(enabled: true);
    await controller.enter();
    expect(controller.entering, isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(controller.entering, isFalse);
    expect(controller.active, isFalse);
    expect(await controller.enter(), isTrue);
    await controller.stop();
  });

  test('unsupported desktop makes no native calls and dispose rejects events',
      () async {
    final desktop =
        CallPictureInPictureController(platform: TargetPlatform.windows);
    expect(await desktop.configure(enabled: true), isFalse);
    expect(await desktop.enter(), isFalse);
    desktop.dispose();
    expect(calls, isEmpty);
    var notifications = 0;
    final mobile =
        CallPictureInPictureController(platform: TargetPlatform.android);
    await mobile.configure(enabled: true);
    mobile.addListener(() => notifications++);
    final oldSession = session;
    mobile.dispose();
    await state('active', sessionID: oldSession);
    expect(notifications, 0);
  });
}
