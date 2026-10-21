import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'in_app_browser_route.dart';
import 'in_app_browser_host.dart';
export 'in_app_browser_host.dart';
export 'in_app_browser_page.dart';
export 'in_app_browser_share.dart';

/// Opens a web link on the app's navigator without invoking another application.
Future<bool> openInAppBrowser(Uri uri, {BuildContext? context}) async {
  if (!isInAppBrowserUri(uri)) return false;
  final browserHost = InAppBrowserHost.active;
  if (browserHost != null) {
    browserHost.open(uri);
    return true;
  }
  final navigator = context != null
      ? Navigator.of(context, rootNavigator: true)
      : Get.key.currentState;
  if (navigator == null) return false;
  final host = context ?? navigator.context;
  navigator.push<void>(InAppBrowserRoute(
    uri: uri,
    scrim: Theme.of(host).colorScheme.scrim,
    reduced: MediaQuery.disableAnimationsOf(host),
  ));
  return true;
}

bool isInAppBrowserUri(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http') &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty;
