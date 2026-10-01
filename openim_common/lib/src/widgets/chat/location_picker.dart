import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class ChatLocationPicker extends StatefulWidget {
  const ChatLocationPicker({super.key});
  @override
  State<ChatLocationPicker> createState() => _ChatLocationPickerState();
}

class _ChatLocationPickerState extends State<ChatLocationPicker> {
  final map = MapController();
  final description = TextEditingController();
  LatLng? selected;
  bool locating = false;
  Future<void> locate() async {
    if (locating) return;
    setState(() => locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled())
        throw StateError('sdkLocationDisabled'.tr);
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        throw StateError('sdkLocationDenied'.tr);
      final position = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(timeLimit: Duration(seconds: 20)));
      if (!mounted) return;
      setState(() => selected = LatLng(position.latitude, position.longitude));
      map.move(selected!, 16);
    } catch (error) {
      if (mounted) IMViews.showToast(error.toString());
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  @override
  void dispose() {
    description.dispose();
    map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: GlassAppBar(title: Text(StrRes.plsSelectLocation), actions: [
          TextButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(context, (
                        latitude: selected!.latitude,
                        longitude: selected!.longitude,
                        description: description.text.trim()
                      )),
              child: Text(StrRes.send)),
        ]),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                  controller: description,
                  maxLength: 120,
                  decoration: InputDecoration(
                      labelText: 'sdkLocationName'.tr,
                      hintText: 'sdkTapMap'.tr))),
          if (locating) const LinearProgressIndicator(),
          Expanded(
              child: FlutterMap(
                  mapController: map,
                  options: MapOptions(
                      initialCenter: const LatLng(0, 0),
                      initialZoom: 2,
                      onTap: (_, point) => setState(() => selected = point)),
                  children: [
                TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'io.openim.app'),
                if (selected != null)
                  MarkerLayer(markers: [
                    Marker(
                        point: selected!,
                        child: Icon(Icons.location_on, color: Styles.c_FF381F))
                  ]),
                const SimpleAttributionWidget(
                    source: Text('OpenStreetMap contributors')),
              ])),
          SafeArea(
              top: false,
              child: TextButton.icon(
                  onPressed: locating ? null : locate,
                  icon: const Icon(Icons.my_location),
                  label: Text('sdkMyLocation'.tr))),
        ]),
      );
}
