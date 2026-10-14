import '../../../../../services/platform_config_service.dart';

/// The URL identifies an APK, never a landing page. Missing metadata disables
/// background installation without preventing the user from using the app.
class AndroidUpdatePackage {
  AndroidUpdatePackage(this.release);
  final PlatformRelease release;
  bool get valid {
    final uri = Uri.tryParse(release.downloadLink);
    final build = int.tryParse(release.latest.split('+').last);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(release.packageSha256) &&
        release.packageSize > 0 &&
        release.packageSize <= 2147483648 &&
        release.versionCode > 0 &&
        release.versionCode <= 2147483647 &&
        RegExp(r'^\d+\.\d+\.\d+\+[1-9]\d*$').hasMatch(release.latest) &&
        build == release.versionCode &&
        compareAppVersions(release.latest, release.minimum) >= 0;
  }

  String get key => '${release.versionCode}:${release.packageSha256}:'
      '${release.packageSize}:${release.downloadLink}';
  Map<String, Object> get arguments => {
        'key': key,
        'url': release.downloadLink,
        'sha256': release.packageSha256,
        'size': release.packageSize,
        'versionCode': release.versionCode,
        'versionName': release.latest.split('+').first,
      };
}
