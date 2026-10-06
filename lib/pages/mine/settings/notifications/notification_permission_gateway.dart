import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Platform access for the notification permission prompt and resume check.
abstract class NotificationPermissionGateway {
  const NotificationPermissionGateway();

  /// Null means the platform does not expose this permission.
  Future<PermissionStatus?> status();
  Future<PermissionStatus> request();
  Future<bool> openSettings();
}

class SystemNotificationPermissionGateway
    extends NotificationPermissionGateway {
  const SystemNotificationPermissionGateway();

  @override
  Future<PermissionStatus?> status() async {
    try {
      return await Permission.notification.status;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<PermissionStatus> request() => Permission.notification.request();

  @override
  Future<bool> openSettings() => openAppSettings();
}
