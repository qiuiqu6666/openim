import '../pages/mine/settings/widgets/platform_update.dart';
import '../pages/mine/settings/update/android/android_update_runtime.dart';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'package:url_launcher/url_launcher_string.dart';

mixin UpgradeManger {
  PackageInfo? packageInfo;
  UpgradeInfoV2? upgradeInfoV2;
  var isShowUpgradeDialog = false;
  var isNowIgnoreUpdate = false;
  Future<void>? _automaticUpdateCheck;
  bool _updateBlocksNavigation = false;
  bool get updateBlocksNavigation => Platform.isAndroid
      ? AndroidUpdateRuntime.instance.blocksNavigation
      : _updateBlocksNavigation;
  set updateBlocksNavigation(bool value) => _updateBlocksNavigation = value;
  final subject = PublishSubject<double>();
  final notificationService = NotificationService();

  void closeSubject() {
    subject.close();
  }

  void ignoreUpdate() {
    DataSp.putIgnoreVersion(
        upgradeInfoV2!.buildVersion! + upgradeInfoV2!.buildVersionNo!);
    Get.back();
  }

  void laterUpdate() {
    isNowIgnoreUpdate = true;
    Get.back();
  }

  Future<void> getAppInfo() async {
    packageInfo ??= await PackageInfo.fromPlatform();
  }

  void nowUpdate() async {
    final appUrl = upgradeInfoV2?.appURl;

    if (appUrl != null && await canLaunchUrlString(appUrl)) {
      launchUrlString(appUrl);
      return;
    }
  }

  void checkUpdate() async {
    final context = Get.context;
    if (context != null) await checkPlatformUpdate(context);
  }

  Future<void> autoCheckVersionUpgrade() {
    if (Platform.isAndroid) return AndroidUpdateRuntime.instance.start();
    // Home entry reuses the same check so rebuilding the home route cannot
    // issue another request or show a duplicate update dialog.
    if (_automaticUpdateCheck != null) return _automaticUpdateCheck!;
    if (isNowIgnoreUpdate) return Future.value();
    final context = Get.context;
    if (context == null) return Future.value();
    isShowUpgradeDialog = true;
    return _automaticUpdateCheck = checkPlatformUpdate(context,
        automatic: true,
        onBlocking: () => updateBlocksNavigation = true).then<void>((checked) {
      if (checked) {
        isNowIgnoreUpdate = true;
        updateBlocksNavigation = false;
      }
    }).whenComplete(() {
      isShowUpgradeDialog = false;
      _automaticUpdateCheck = null;
    });
  }

  bool get canUpdate =>
      packageInfo!.version + packageInfo!.buildNumber !=
      upgradeInfoV2!.buildVersion! + upgradeInfoV2!.buildVersionNo!;
}

class NotificationService {
  static final NotificationService _notificationService =
      NotificationService._internal();
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final AndroidInitializationSettings _androidInitializationSettings =
      const AndroidInitializationSettings('@mipmap/ic_launcher');

  factory NotificationService() {
    return _notificationService;
  }

  NotificationService._internal() {
    if (Platform.isAndroid) {
      init();
    }
  }

  void init() async {
    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: _androidInitializationSettings,
    );
    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future createNotification(int count, int i, int id, String status) async {
    var androidPlatformChannelSpecifics = AndroidNotificationDetails(
        'progress channel', 'progress channel',
        channelDescription: 'progress channel description',
        channelShowBadge: false,
        importance: Importance.max,
        priority: Priority.high,
        onlyAlertOnce: true,
        showProgress: true,
        maxProgress: count,
        progress: i);
    var platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await _flutterLocalNotificationsPlugin
        .show(id, status, '$i%', platformChannelSpecifics, payload: 'item x');

    return;
  }
}
