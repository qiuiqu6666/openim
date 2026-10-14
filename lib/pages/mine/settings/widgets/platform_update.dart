import 'package:flutter/material.dart';
import 'dart:io';
import '../update/android/android_update_runtime.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../../../services/platform_config_service.dart';
import '../update/platform_update_dialog.dart';
import '../update/platform_update_retry.dart';
import 'settings_widgets.dart';

Future<bool> checkPlatformUpdate(BuildContext context,
    {bool automatic = false,
    Future<PlatformConfig> Function()? fetchConfig,
    Future<bool> Function(Uri)? openURL,
    void Function()? onBlocking,
    PlatformConfig? prefetchedConfig}) async {
  if (Platform.isAndroid) {
    try {
      await AndroidUpdateRuntime.instance.start(manual: !automatic);
      if (!automatic && context.mounted) {
        final status = AndroidUpdateRuntime.instance.statusText(context);
        if (!AndroidUpdateRuntime.instance.blocksNavigation) {
          showSettingsMessage(
              context,
              status.isEmpty
                  ? settingsText(context,
                      zh: '暂无可用的新版本', en: 'No update available')
                  : status);
        }
      }
    } catch (_) {
      // Configuration/storage failure must never lock an Android user out.
    }
    return true;
  }
  final fetch = fetchConfig ?? () => PlatformConfigService.fetch();
  final open = openURL ??
      (Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
  try {
    final config =
        prefetchedConfig ?? await retryPlatformUpdate<PlatformConfig>(fetch);
    final current = await PackageInfo.fromPlatform();
    final installedVersion = '${current.version}+${current.buildNumber}';
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
        compareAppVersions(installedVersion, release.minimum) < 0;
    if (force) onBlocking?.call();
    if (!context.mounted) return false;
    if (release.latest.isEmpty && !force) {
      if (!automatic) {
        showSettingsMessage(
            context,
            settingsText(context,
                zh: '暂未配置版本信息', en: 'Version information is not configured'));
      }
      return true;
    }
    final target =
        force && compareAppVersions(release.latest, release.minimum) < 0
            ? release.minimum
            : release.latest;
    final available = force ||
        (compareAppVersions(installedVersion, target) < 0 &&
            bucket < release.grayRatio);
    if (!available) {
      if (!automatic) {
        showSettingsMessage(context,
            settingsText(context, zh: '暂无可用的新版本', en: 'No update available'));
      }
      return true;
    }
    if (!force && release.installURL.isEmpty) {
      if (!automatic) {
        showSettingsMessage(
            context,
            settingsText(context,
                zh: '新版本下载地址未配置',
                en: 'Update download link is not configured'));
      }
      return true;
    }
    final uri = Uri.tryParse(release.installURL);
    final invalidURI = uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty;
    if (!force && invalidURI) {
      if (!automatic) {
        showSettingsMessage(
            context,
            settingsText(context,
                zh: '新版本下载地址暂不可用，请稍后重试',
                en: 'The update download link is unavailable. Please retry later.'));
      }
      return true;
    }
    await showPlatformUpdateDialog(
      context,
      title: settingsText(context,
          zh: force ? '发现新版本！' : '发现新版本',
          en: force ? 'Update Required' : 'Update Available'),
      message: invalidURI
          ? settingsText(context,
              zh: '当前版本必须更新，下载地址暂不可用，请重试获取更新。',
              en:
                  'An update is required. The download link is unavailable. Please retry.')
          : release.changelog.isNotEmpty
              ? release.changelog
              : settingsText(context,
                  zh: '发现新版本 v$target，是否立即更新？',
                  en: 'Version $target is available. Update now?'),
      force: force,
      actionLabel: invalidURI
          ? settingsText(context, zh: '重试获取更新', en: 'Retry Update')
          : null,
      failureMessage: settingsText(context,
          zh: '获取或打开更新失败，请检查网络后重试。',
          en: 'Unable to fetch or open the update. Check your connection and retry.'),
      onUpdate: () async {
        final fresh = await retryPlatformUpdate<PlatformConfig>(fetch);
        final freshURI = Uri.tryParse(fresh.release.installURL);
        if (freshURI == null ||
            !['http', 'https'].contains(freshURI.scheme) ||
            freshURI.host.isEmpty ||
            !await open(freshURI)) {
          throw StateError('无法打开下载地址');
        }
      },
    );
    // Removing a route externally is not proof that a required update finished.
    return !force && context.mounted;
  } catch (_) {
    if (context.mounted && automatic) {
      onBlocking?.call();
      PlatformConfig? retryConfig;
      await showPlatformUpdateDialog(context,
          title: settingsText(context,
              zh: '暂时无法检查更新', en: 'Update Check Unavailable'),
          message: settingsText(context,
              zh: '请检查网络，重试完成版本检查后继续使用。',
              en:
                  'Check your connection and retry the version check to continue.'),
          force: true,
          closeOnSuccess: true,
          actionLabel: settingsText(context, zh: '重试', en: 'Retry'),
          failureMessage: settingsText(context,
              zh: '仍无法检查更新，请检查网络后重试。',
              en: 'Still unable to check updates. Check your connection and retry.'),
          onUpdate: () async {
        retryConfig = await retryPlatformUpdate<PlatformConfig>(fetch);
      });
      if (context.mounted) {
        return checkPlatformUpdate(context,
            automatic: true,
            fetchConfig: fetch,
            openURL: open,
            onBlocking: onBlocking,
            prefetchedConfig: retryConfig);
      }
    }
    if (context.mounted && !automatic) {
      showSettingsMessage(
          context,
          settingsText(context,
              zh: '检查更新失败，请稍后重试',
              en: 'Unable to check for updates. Please retry.'));
    }
    return false;
  }
}
