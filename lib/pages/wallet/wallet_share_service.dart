import 'dart:io';
import 'dart:ui' as ui;
import 'host/wallet_platform_guard.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:url_launcher/url_launcher.dart';

enum WalletCopyResult {
  success,
  empty,
  failed,
}

enum WalletSaveImgResult {
  success,
  permissionDenied,
  permanentlyDenied,
  renderFailed,
  saveFailed,
  unsupported,
  unknown,
}

enum WalletLaunchAppResult {
  success,
  unavailable,
  failed,
}

enum WalletShareTextResult {
  success,
  unavailable,
  failed,
}

enum WalletSystemShareResult {
  success,
  unavailable,
  failed,
}

class WalletShareService {
  static const MethodChannel _shareChannel =
      MethodChannel('wallet_share_channel');

  Future<WalletCopyResult> copyAddr(String addr) async {
    final v = addr.trim();
    if (v.isEmpty) return WalletCopyResult.empty;

    try {
      await ClipboardGuard.copy(v);
      return WalletCopyResult.success;
    } catch (_) {
      return WalletCopyResult.failed;
    }
  }

  Future<WalletSaveImgResult> saveQrImg(BuildContext context, GlobalKey key) async {
    try {
      final allowed = await PermissionGuard.photosForSave(context);
      if (!allowed) return WalletSaveImgResult.permissionDenied;

      await Future<void>.delayed(const Duration(milliseconds: 80));

      final bd = key.currentContext?.findRenderObject();
      if (bd is! RenderRepaintBoundary) return WalletSaveImgResult.renderFailed;

      final img = await bd.toImage(pixelRatio: 3.0);
      final bytes = await _toBytes(img);
      if (bytes == null || bytes.isEmpty) return WalletSaveImgResult.renderFailed;

      final name = 'wallet_receive_${DateTime.now().millisecondsSinceEpoch}';
      final ret = await ImageGallerySaverPlus.saveImage(
        bytes,
        quality: 100,
        name: name,
      );

      return _isSaved(ret) ? WalletSaveImgResult.success : WalletSaveImgResult.saveFailed;
    } catch (_) {
      return WalletSaveImgResult.unknown;
    }
  }

  Future<WalletLaunchAppResult> launchWechat() {
    return _launchScheme('weixin://');
  }

  Future<WalletLaunchAppResult> launchQQ() {
    return _launchScheme('mqq://');
  }

  Future<WalletLaunchAppResult> launchSms(String addr) async {
    final text = addr.trim();
    final uri = Uri.parse('sms:?body=${Uri.encodeComponent(text)}');
    return _launchUri(uri);
  }

  Future<WalletShareTextResult> shareText(String text) async {
    final value = text.trim();
    if (value.isEmpty) return WalletShareTextResult.failed;
    final uri = Uri.parse('sms:?body=${Uri.encodeComponent(value)}');
    final ret = await _launchUri(uri);
    switch (ret) {
      case WalletLaunchAppResult.success:
        return WalletShareTextResult.success;
      case WalletLaunchAppResult.unavailable:
        return WalletShareTextResult.unavailable;
      case WalletLaunchAppResult.failed:
        return WalletShareTextResult.failed;
    }
  }

  Future<WalletSystemShareResult> shareSystemText(String text) async {
    final value = text.trim();
    if (value.isEmpty) return WalletSystemShareResult.failed;
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return WalletSystemShareResult.unavailable;
    }
    try {
      final ret = await _shareChannel.invokeMethod<bool>(
        'shareText',
        {'text': value},
      );
      if (ret == true) return WalletSystemShareResult.success;
      return WalletSystemShareResult.unavailable;
    } on MissingPluginException {
      return WalletSystemShareResult.unavailable;
    } catch (_) {
      return WalletSystemShareResult.failed;
    }
  }

  Future<Uint8List?> _toBytes(ui.Image img) async {
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<WalletLaunchAppResult> _launchScheme(String scheme) {
    return _launchUri(Uri.parse(scheme));
  }

  Future<WalletLaunchAppResult> _launchUri(Uri uri) async {
    try {
      final can = await canLaunchUrl(uri);
      if (!can) return WalletLaunchAppResult.unavailable;
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return ok ? WalletLaunchAppResult.success : WalletLaunchAppResult.failed;
    } catch (_) {
      return WalletLaunchAppResult.failed;
    }
  }

  bool _isSaved(dynamic ret) {
    if (ret is Map) {
      final ok = ret['isSuccess'];
      if (ok is bool) return ok;

      final path = ret['filePath'] ?? ret['filepath'];
      return path != null && path.toString().isNotEmpty;
    }

    return ret != null;
  }
}
