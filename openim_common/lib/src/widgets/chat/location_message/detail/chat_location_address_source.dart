import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class ChatLocationAddress {
  const ChatLocationAddress({required this.name, required this.address});
  final String name, address;
}

/// Resolves the message's WGS84 point, independently of the viewer's GPS.
class ChatLocationAddressSource {
  const ChatLocationAddressSource();
  static const _channel = MethodChannel('openim/location-address');
  Future<ChatLocationAddress> resolve(LatLng point, String locale) async {
    final row = await _channel.invokeMapMethod<String, dynamic>('reverse', {
      'latitude': point.latitude,
      'longitude': point.longitude,
      'locale': locale,
    }).timeout(const Duration(seconds: 15));
    final address = (row?['address'] as String?)?.trim() ?? '';
    if (address.isEmpty) throw StateError('Address unavailable');
    return ChatLocationAddress(
        name: (row?['name'] as String?)?.trim() ?? '', address: address);
  }
}
