import 'package:flutter/material.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:map_launcher/map_launcher_platform_interface.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../chat_location_message_data.dart';

/// All message coordinates are WGS84. Never pass them as GCJ02/BD09.
class ChatLocationDetailActions {
  const ChatLocationDetailActions();
  Future<List<AvailableMap>> installedMaps() async =>
      (await MapLauncher.installedMaps)
          .where((map) => const {
                MapType.apple,
                MapType.google,
                MapType.googleGo,
                MapType.amap,
                MapType.baidu
              }.contains(map.mapType))
          .toList();
  Uri link(ChatLocationMessageData data, {bool directions = false}) {
    final point = data.point!;
    return Uri.https(
        'www.google.com', directions ? '/maps/dir/' : '/maps/search/', {
      'api': '1',
      directions ? 'destination' : 'query':
          '${point.latitude},${point.longitude}',
    });
  }

  Future<void> share(ChatLocationMessageData data, Rect origin) async {
    await Share.share(
        [data.name, data.address, link(data).toString()]
            .where((s) => s.isNotEmpty)
            .join('\n'),
        sharePositionOrigin: origin);
  }

  Future<void> directions(
      ChatLocationMessageData data, AvailableMap? map) async {
    if (map == null) {
      if (!await launchUrl(link(data, directions: true),
          mode: LaunchMode.externalApplication)) {
        throw StateError('No navigation application');
      }
      return;
    }
    final point = data.point!;
    // map_launcher 4.4.2's convenience wrapper drops this Future.
    // Await the public platform interface so launch errors reach the page.
    await MapLauncherPlatform.instance.showDirections(
        mapType: map.mapType,
        destination: Coords(point.latitude, point.longitude),
        destinationTitle: data.name,
        extraParams: switch (map.mapType) {
          MapType.amap => {'dev': '1', 'sourceApplication': '99Chat'},
          MapType.baidu => {'coord_type': 'wgs84'},
          _ => null,
        });
  }
}
