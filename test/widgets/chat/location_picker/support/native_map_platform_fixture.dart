import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Only the platform-view and map channels are simulated; no native SDK starts.
class NativeMapPlatformFixture {
  NativeMapPlatformFixture(this.platform);
  final TargetPlatform platform;
  final creates = <({int id, String viewType, Map<Object?, Object?> params})>[];
  final calls = <MethodCall>[];
  final platformCalls = <MethodCall>[];
  final _channels = <MethodChannel>[];
  String? statusError;
  TestDefaultBinaryMessenger get messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() {
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      platformCalls.add(call);
      if (call.method == 'create') {
        final args = call.arguments as Map<Object?, Object?>;
        final id = args['id']! as int;
        final bytes = args['params']! as Uint8List;
        final params = const StandardMessageCodec()
                .decodeMessage(ByteData.sublistView(bytes))
            as Map<Object?, Object?>;
        creates.add(
            (id: id, viewType: args['viewType']! as String, params: params));
        final channel = MethodChannel('openim/chat-location-map/$id');
        _channels.add(channel);
        messenger.setMockMethodCallHandler(channel, (mapCall) async {
          calls.add(mapCall);
          if (mapCall.method == 'status') return {'error': statusError};
          return null;
        });
        return platform == TargetPlatform.android && args['hybrid'] != true
            ? 7
            : null;
      }
      if (call.method == 'resize') {
        final args = call.arguments as Map<Object?, Object?>;
        return {'width': args['width'], 'height': args['height']};
      }
      return null;
    });
  }

  Future<void> event(String name, [Object? arguments]) async {
    final channel = _channels.last;
    await messenger.handlePlatformMessage(channel.name,
        channel.codec.encodeMethodCall(MethodCall(name, arguments)), (_) {});
  }

  void uninstall() {
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in _channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  }
}
