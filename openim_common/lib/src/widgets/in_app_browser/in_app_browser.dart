import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
export 'in_app_browser_host.dart';
export 'in_app_browser_page.dart';
export 'in_app_browser_share.dart';

/// Uses system-owned browser chrome; does not create an app-managed WebView.
Future<bool> openInAppBrowser(Uri uri, {BuildContext? context}) async {
  return await openSystemBrowser(uri) == SystemBrowserOpenResult.opened;
}

enum SystemBrowserOpenResult { opened, invalidLink, unavailable, failed }

/// Preserve the failure reason so a missing browser is not blamed on the link.
Future<SystemBrowserOpenResult> openSystemBrowser(Uri uri) async {
  if (!isInAppBrowserUri(uri)) return SystemBrowserOpenResult.invalidLink;
  try {
    // Avoid the launcher's fallback to a custom WebView or an external browser.
    if (!await supportsLaunchMode(LaunchMode.inAppBrowserView)) {
      return SystemBrowserOpenResult.unavailable;
    }
    return await launchUrl(uri, mode: LaunchMode.inAppBrowserView)
        ? SystemBrowserOpenResult.opened
        : SystemBrowserOpenResult.failed;
  } catch (_) {
    return SystemBrowserOpenResult.failed;
  }
}

bool isInAppBrowserUri(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http') &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty;
