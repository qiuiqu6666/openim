class DesktopDevice {
  const DesktopDevice(
      {required this.id, required this.name, required this.platform});
  final String id, name, platform;
}

/// Only explicit online records count; historical login is not online presence.
List<DesktopDevice> onlineDesktopDevices(
    List<Map<String, dynamic>> records, String currentID) {
  final devices = <String, DesktopDevice>{};
  for (final row in records) {
    final id = row['deviceID']?.toString() ?? '';
    final platform = row['platform']?.toString().toLowerCase() ?? '';
    final label = switch (platform) {
      'windows' => 'Windows',
      'macos' || 'macosx' => 'Mac',
      'linux' => 'Linux',
      'web' => '网页版',
      _ => '',
    };
    if (id.isEmpty ||
        id == currentID ||
        row['online'] != true ||
        label.isEmpty) {
      continue;
    }
    devices[id] = DesktopDevice(
        id: id, name: row['deviceName']?.toString() ?? label, platform: label);
  }
  return devices.values.toList();
}
