import 'package:latlong2/latlong.dart';
import 'package:openim_common/src/widgets/chat/location_picker/data/chat_location_source.dart';

class LocationTestSource implements ChatLocationSource {
  final requests = <bool>[];
  Future<LatLng?> Function(bool requestPermission)? respond;

  @override
  Future<LatLng?> locate({required bool requestPermission}) {
    requests.add(requestPermission);
    return respond?.call(requestPermission) ?? Future.value(null);
  }
}
