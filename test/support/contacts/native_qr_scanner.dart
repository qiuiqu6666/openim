import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs the real QRView/controller against native method-channel responses.
/// It never opens a hardware camera or replaces application scan logic.
class NativeQrScanner {
  NativeQrScanner(this.tester) {
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final arguments = call.arguments as Map;
        final id = arguments['id'] as int;
        channel = MethodChannel('net.touchcapture.qr.flutterqrplus/qrview_$id');
        messenger.setMockMethodCallHandler(channel!, (call) async {
          calls.add(call.method);
          if (call.method == 'pauseCamera' || call.method == 'resumeCamera') {
            cameraCalls.add(call.method);
          }
          switch (call.method) {
            case 'getSystemFeatures':
              return {
                'hasFlash': hasFlash,
                'hasBackCamera': true,
                'hasFrontCamera': true,
              };
            case 'getFlashInfo':
              return flashOn;
            case 'toggleFlash':
              if (flashFailure != null) throw flashFailure!;
              flashOn = !flashOn;
              return flashOn;
          }
          return null;
        });
        return id + 100;
      }
      if (call.method == 'resize') {
        final arguments = call.arguments as Map;
        return {'width': arguments['width'], 'height': arguments['height']};
      }
      return null;
    });
  }

  final WidgetTester tester;
  TestDefaultBinaryMessenger get messenger =>
      tester.binding.defaultBinaryMessenger;
  MethodChannel? channel;
  final cameraCalls = <String>[];
  final calls = <String>[];
  bool hasFlash = true;
  bool flashOn = false;
  PlatformException? flashFailure;

  Future<void> permission(bool granted) =>
      _callback('onPermissionSet', granted);
  Future<void> recognize(String code) => _callback('onRecognizeQR', {
        'code': code,
        'type': 'QR_CODE',
        'rawBytes': Uint8List(0),
      });

  Future<void> _callback(String method, Object arguments) async {
    final reply = Completer<ByteData?>();
    // Exercise the plugin-owned incoming callback, not a test scan hook.
    // ignore: deprecated_member_use
    await messenger.handlePlatformMessage(
      channel!.name,
      channel!.codec.encodeMethodCall(MethodCall(method, arguments)),
      reply.complete,
    );
    final response = await reply.future;
    if (response != null) channel!.codec.decodeEnvelope(response);
  }

  void dispose() {
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    if (channel != null) messenger.setMockMethodCallHandler(channel!, null);
  }
}
