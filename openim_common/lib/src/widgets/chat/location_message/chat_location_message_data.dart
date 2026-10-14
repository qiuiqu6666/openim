import 'package:latlong2/latlong.dart';

/// Plain text stays readable by older clients; legacy ///// addresses are read too.
class ChatLocationMessageData {
  const ChatLocationMessageData(
      {required this.name, this.address = '', this.point});
  final String name, address;
  final LatLng? point;

  factory ChatLocationMessageData.parse(
      String? description, double? latitude, double? longitude) {
    final text = description ?? '';
    final parts =
        text.contains('/////') ? text.split('/////') : text.split('\n');
    return ChatLocationMessageData(
        name: parts.first.trim(),
        address: parts.skip(1).join(' ').trim(),
        point: latitude != null &&
                longitude != null &&
                latitude.isFinite &&
                longitude.isFinite &&
                latitude.abs() <= 90 &&
                longitude.abs() <= 180
            ? LatLng(latitude, longitude)
            : null);
  }

  static String describe(String name, String? address) =>
      address == null || address.trim().isEmpty
          ? name
          : '$name\n${address.trim()}';
}
