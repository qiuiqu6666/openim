import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'in_app_browser_page.dart';
export 'in_app_browser_page.dart';

/// Opens a web link on the app's navigator without invoking another application.
Future<bool> openInAppBrowser(Uri uri, {BuildContext? context}) async {
  if (!isInAppBrowserUri(uri)) return false;
  final navigator = context != null
      ? Navigator.of(context, rootNavigator: true)
      : Get.key.currentState;
  if (navigator == null) return false;
  navigator.push<void>(MaterialPageRoute(
    settings: const RouteSettings(name: '/in-app-browser'),
    builder: (_) => InAppBrowserPage(uri: uri),
  ));
  return true;
}

bool isInAppBrowserUri(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http') &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty;
