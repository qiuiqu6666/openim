import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../../../services/platform_config_service.dart';
import 'settings_widgets.dart';

Future<void> checkPlatformUpdate(BuildContext context,
    {bool automatic = false}) async {
  try {
    final config = await PlatformConfigService.fetch();
    final current = await PackageInfo.fromPlatform();
    final currentVersion = current.buildNumber.isEmpty
        ? current.version
        : '${current.version}+${current.buildNumber}';
    final release = config.release;
    final prefs = await SharedPreferences.getInstance();
    var install = prefs.getString('platform_update_install_id');
    if (install == null) {
      install = const Uuid().v4();
      await prefs.setString('platform_update_install_id', install);
    }
    final bucket =
        install.codeUnits.fold<int>(0, (sum, c) => (sum * 31 + c) % 100);
    final force = release.minimum.isNotEmpty &&
        compareAppVersions(currentVersion, release.minimum) < 0;
    if (!context.mounted) return;
    if (release.latest.isEmpty && !force) {
      if (!automatic) {
        showSettingsMessage(
            context,
            settingsText(context,
                zh: '暂未配置版本信息', en: 'Version information is not configured'));
      }
      return;
    }
    final target =
        force && compareAppVersions(release.latest, release.minimum) < 0
            ? release.minimum
            : release.latest;
    final available = force ||
        (compareAppVersions(currentVersion, target) < 0 &&
            bucket < release.grayRatio);
    if (!available) {
      if (!automatic) {
        showSettingsMessage(context,
            settingsText(context, zh: '暂无可用的新版本', en: 'No update available'));
      }
      return;
    }
    if (release.installURL.isEmpty) {
      if (!automatic) {
        showSettingsMessage(
            context,
            settingsText(context,
                zh: '新版本下载地址未配置',
                en: 'Update download link is not configured'));
      }
      return;
    }
    final confirmed = await showSettingsConfirm(context,
        title: settingsText(context,
            zh: '发现新版本 $target', en: 'New version $target'),
        message: settingsText(context,
            zh: force ? '当前版本低于最低支持版本，请更新应用。' : '有新版本可用，是否前往下载？',
            en: force
                ? 'Please update to a supported version.'
                : 'Download the new version?'),
        confirmText: settingsText(context, zh: '前往更新', en: 'Update'));
    if (!confirmed || !context.mounted) return;
    final uri = Uri.tryParse(release.installURL);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('无法打开下载地址');
    }
  } catch (_) {
    if (context.mounted && !automatic) {
      showSettingsMessage(
          context,
          settingsText(context,
              zh: '检查更新失败，请稍后重试',
              en: 'Unable to check for updates. Please retry.'));
    }
  }
}
