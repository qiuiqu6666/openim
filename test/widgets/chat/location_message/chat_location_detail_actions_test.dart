import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:openim_common/src/widgets/chat/location_message/chat_location_message_data.dart';
import 'package:openim_common/src/widgets/chat/location_message/detail/chat_location_detail_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('map_launcher');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const data = ChatLocationMessageData(name: '地点', point: LatLng(39.9, 116.4));
  const actions = ChatLocationDetailActions();
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  for (final type in [MapType.amap, MapType.baidu]) {
    test('navigation sends explicit WGS84 flags to $type', () async {
      MethodCall? captured;
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured = call;
        return null;
      });
      await actions.directions(
          data, AvailableMap(mapName: type.name, mapType: type, icon: ''));
      final uri = Uri.parse((captured!.arguments as Map)['url'] as String);
      expect(uri.queryParameters[type == MapType.amap ? 'dev' : 'coord_type'],
          type == MapType.amap ? '1' : 'wgs84');
      expect((captured!.arguments as Map)['destinationLatitude'], '39.9');
    });
  }
  test('native launch failures are awaited instead of escaping asynchronously',
      () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => throw PlatformException(code: 'unavailable'));
    await expectLater(
        actions.directions(data,
            AvailableMap(mapName: 'Google', mapType: MapType.google, icon: '')),
        throwsA(isA<PlatformException>()));
  });
}
