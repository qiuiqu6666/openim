import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class ChatLocationPlace {
  const ChatLocationPlace(
      {required this.id,
      required this.name,
      required this.address,
      required this.point});
  final String id, name, address;
  final LatLng point;
}

typedef ChatLocationPlaceSearch = Future<List<ChatLocationPlace>> Function(
    String query, LatLng? center);

/// The native provider returns WGS84, just like the existing map boundary.
Future<List<ChatLocationPlace>> searchNativePlaces(
    MethodChannel channel, String query, LatLng? center) async {
  final rows = await channel.invokeListMethod<dynamic>('searchPlaces', {
    'query': query,
    if (center != null) 'latitude': center.latitude,
    if (center != null) 'longitude': center.longitude,
  }).timeout(const Duration(seconds: 15));
  return (rows ?? [])
      .whereType<Map>()
      .map((row) {
        final lat = row['latitude'], lng = row['longitude'];
        if (lat is! num ||
            lng is! num ||
            !lat.isFinite ||
            !lng.isFinite ||
            lat.abs() > 90 ||
            lng.abs() > 180 ||
            row['name'] is! String) {
          return null;
        }
        return ChatLocationPlace(
            id: '${row['id'] ?? ''}',
            name: row['name'] as String,
            address: '${row['address'] ?? ''}',
            point: LatLng(lat.toDouble(), lng.toDouble()));
      })
      .whereType<ChatLocationPlace>()
      .toList();
}
