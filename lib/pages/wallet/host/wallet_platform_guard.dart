import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class ClipboardGuard {
  ClipboardGuard._();
  static Future<void> copy(String text) => Clipboard.setData(ClipboardData(text: text));
}

class PermissionGuard {
  PermissionGuard._();

  static Future<bool> photosForSave(BuildContext context) async {
    if (kIsWeb) return false;
    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      return status.isGranted || status.isLimited;
    }
    if (Platform.isAndroid) {
      // Android 10+ gallery insertion through MediaStore does not require legacy storage permission.
      return true;
    }
    return false;
  }
}
