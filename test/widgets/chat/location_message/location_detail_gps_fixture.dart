import 'package:geolocator/geolocator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Card/navigation tests have no device GPS. Dedicated detail tests inject fixes.
void installUnavailableDetailGps() {
  final previous = GeolocatorPlatform.instance;
  GeolocatorPlatform.instance = _UnavailableGps();
  addTearDown(() => GeolocatorPlatform.instance = previous);
}

class _UnavailableGps extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => false;
}
