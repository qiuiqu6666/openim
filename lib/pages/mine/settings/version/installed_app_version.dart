import 'package:package_info_plus/package_info_plus.dart';

/// Uses the installed package, including build-name/build-number overrides.
String installedAppVersion(PackageInfo info) {
  final version = info.version.trim();
  final build = info.buildNumber.trim();
  if (version.isEmpty) return '';
  return build.isEmpty ? version : '$version+$build';
}
