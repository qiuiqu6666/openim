import 'dart:io';
import 'dart:ui' as ui;
import 'host/wallet_platform_guard.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:share_plus/share_plus.dart';
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
  dismissed,
  unavailable,
  failed,
}

class WalletShareService {
  WalletShareService({
    Future<bool> Function(BuildContext)? requestPhotoPermission,
  }) : _requestPhotoPermission =
            requestPhotoPermission ?? PermissionGuard.photosForSave;

  final Future<bool> Function(BuildContext) _requestPhotoPermission;
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

  Future<WalletSaveImgResult> saveQrImg(
    BuildContext context,
    GlobalKey key, {
    bool Function()? isCurrent,
    Color backgroundColor = const Color(0xFFFFFFFF),
  }) async {
    bool active() => context.mounted && (isCurrent?.call() ?? true);
    try {
      if (!active()) return WalletSaveImgResult.unknown;
      final allowed = await _requestPhotoPermission(context);
      if (!active()) return WalletSaveImgResult.unknown;
      if (!allowed) return WalletSaveImgResult.permissionDenied;

      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!active()) return WalletSaveImgResult.unknown;

      final bd = key.currentContext?.findRenderObject();
      if (bd is! RenderRepaintBoundary) return WalletSaveImgResult.renderFailed;

      final bytes = await _captureBytes(bd, backgroundColor: backgroundColor);
      if (!active()) return WalletSaveImgResult.unknown;
      if (bytes == null || bytes.isEmpty) {
        return WalletSaveImgResult.renderFailed;
      }

      final name = 'wallet_receive_${DateTime.now().millisecondsSinceEpoch}';
      if (!active()) return WalletSaveImgResult.unknown;
      final ret = await ImageGallerySaverPlus.saveImage(
        bytes,
        quality: 100,
        name: name,
      );
      if (!active()) return WalletSaveImgResult.unknown;

      return _isSaved(ret)
          ? WalletSaveImgResult.success
          : WalletSaveImgResult.saveFailed;
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

  /// Shares only the rendered deposit card, without a separate address payload.
  Future<WalletSystemShareResult> shareSystemImage(
    BuildContext context,
    GlobalKey key, {
    required bool Function() isCurrent,
    Color backgroundColor = const Color(0xFFFFFFFF),
  }) async {
    bool active() => context.mounted && isCurrent();
    if (!active()) return WalletSystemShareResult.dismissed;
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return WalletSystemShareResult.unavailable;
    }
    try {
      final boundaryContext = key.currentContext;
      final boundary = boundaryContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary ||
          !boundary.attached ||
          !boundary.hasSize ||
          boundary.size.isEmpty) {
        return WalletSystemShareResult.failed;
      }
      if (boundary.debugNeedsPaint) {
        await WidgetsBinding.instance.endOfFrame;
        if (!active() || boundaryContext?.mounted != true) {
          return WalletSystemShareResult.dismissed;
        }
      }
      final bytes =
          await _captureBytes(boundary, backgroundColor: backgroundColor);
      if (!active() || boundaryContext?.mounted != true) {
        return WalletSystemShareResult.dismissed;
      }
      if (bytes == null || bytes.isEmpty || !boundary.attached) {
        return WalletSystemShareResult.failed;
      }

      final viewport = MediaQuery.sizeOf(context);
      final origin = (boundary.localToGlobal(Offset.zero) & boundary.size)
          .intersect(Offset.zero & viewport);
      if (origin.isEmpty || !origin.isFinite) {
        return WalletSystemShareResult.failed;
      }
      final name =
          '99Chat_deposit_${DateTime.now().microsecondsSinceEpoch}.png';
      final file = XFile.fromData(bytes, mimeType: 'image/png', name: name);
      if (!active()) return WalletSystemShareResult.dismissed;
      final result = await Share.shareXFiles(
        [file],
        fileNameOverrides: [name],
        sharePositionOrigin: origin,
      );
      if (!active()) return WalletSystemShareResult.dismissed;
      return switch (result.status) {
        ShareResultStatus.success => WalletSystemShareResult.success,
        ShareResultStatus.dismissed => WalletSystemShareResult.dismissed,
        ShareResultStatus.unavailable => WalletSystemShareResult.unavailable,
      };
    } on MissingPluginException {
      return WalletSystemShareResult.unavailable;
    } catch (_) {
      return WalletSystemShareResult.failed;
    }
  }

  Future<Uint8List?> _captureBytes(
    RenderRepaintBoundary boundary, {
    required Color backgroundColor,
  }) async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    ui.PictureRecorder? recorder;
    ui.Picture? picture;
    ui.Image? flattened;
    try {
      // The Android gallery plugin converts PNG to JPEG. Composite transparent
      // rounded corners first so that conversion keeps the card background.
      recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Paint()..color = backgroundColor.withAlpha(255),
      );
      canvas.drawImage(image, Offset.zero, ui.Paint());
      picture = recorder.endRecording();
      flattened = await picture.toImage(image.width, image.height);
      return await _toBytes(flattened);
    } finally {
      flattened?.dispose();
      picture?.dispose();
      if (recorder != null && recorder.isRecording) {
        recorder.endRecording().dispose();
      }
      image.dispose();
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
