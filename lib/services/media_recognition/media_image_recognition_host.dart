import 'dart:async';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/localization.dart';
import 'package:openim_common/media_recognition.dart';
import '../../pages/contacts/scanning/contact_qr_navigation.dart';
import '../../widgets/qr_scanner/qr_gallery_service.dart';
import '../../widgets/qr_scanner/content/qr_content_actions.dart';
import '../../widgets/qr_scanner/content/qr_content_sheet.dart';
import 'media_image_file.dart';
import 'media_recognition_parser.dart';

MediaRecognitionRequest recognizePreviewImage(MediaSource source) {
  final token = QrGalleryCancellation();
  final file = MediaImageFile();
  final owner = (DataSp.userID, DataSp.chatToken, DataSp.imToken);
  bool current() =>
      !token.isCancelled &&
      owner == (DataSp.userID, DataSp.chatToken, DataSp.imToken);
  Future<MediaRecognitionResult> scan() async {
    try {
      final image = await file.resolve(source);
      if (!current()) return const MediaRecognitionResult([]);
      final qr =
          await const QrGalleryService().scan(image.path, cancellation: token);
      if (!current()) return const MediaRecognitionResult([]);
      var text = '',
          partial = qr.partial ||
              ![QrGalleryStatus.success, QrGalleryStatus.noCode]
                  .contains(qr.status);
      try {
        text = await const MethodChannel('99chat/qr_image_decoder')
                .invokeMethod<String>('recognizeText', {'path': image.path}) ??
            '';
      } catch (_) {
        partial = true;
      }
      if (!current()) return const MediaRecognitionResult([]);
      final parsed = parseImageRecognition(qr.codes.map((c) => c.text), text);
      final zh = Get.locale?.languageCode == 'zh';
      String label(String cn, String en) => zh ? AppCopy.text(cn) : en;
      return MediaRecognitionResult([
        for (final item in parsed)
          MediaRecognitionTarget(
            value: item.value,
            title: switch (item.kind) {
              RecognizedImageKind.friend => label('好友二维码', 'Friend QR code'),
              RecognizedImageKind.group => label('群二维码', 'Group QR code'),
              RecognizedImageKind.tron => label('TRON 地址', 'TRON address'),
              RecognizedImageKind.url => label('二维码链接', 'QR link'),
              RecognizedImageKind.text => label('二维码内容', 'QR content'),
            },
            copyLabel: switch (item.kind) {
              RecognizedImageKind.tron => label('复制地址', 'Copy address'),
              RecognizedImageKind.text => label('复制内容', 'Copy content'),
              _ => label('复制链接', 'Copy link'),
            },
            openLabel: switch (item.kind) {
              RecognizedImageKind.group =>
                label('识别群二维码', 'Recognize group QR code'),
              RecognizedImageKind.friend =>
                label('识别好友二维码', 'Recognize friend QR code'),
              RecognizedImageKind.tron =>
                label('复制 TRON 地址', 'Copy TRON address'),
              _ => label('识别图中二维码', 'Recognize QR code in image'),
            },
            open: item.kind != RecognizedImageKind.tron
                ? (context, isActive) async {
                    // The menu has closed and cancelled its scan by this point.
                    bool active() =>
                        isActive() &&
                        owner ==
                            (DataSp.userID, DataSp.chatToken, DataSp.imToken);
                    if (!active()) return;
                    if (item.contact != null) {
                      await openScannedContact(item.contact!, isActive: active);
                    } else if (item.kind == RecognizedImageKind.url) {
                      if (!await const QrContentActions()
                          .openBrowser(Uri.parse(item.value))) {
                        throw StateError('unavailable');
                      }
                    } else {
                      await showQrContent(context, item.value);
                    }
                  }
                : null,
          ),
      ], partial: partial);
    } finally {
      // The native OCR reply means it no longer holds the image file.
      await file.dispose();
    }
  }

  void cancel() {
    token.cancel();
    file.cancel();
  }

  final result = scan();
  return MediaRecognitionRequest(
      result.timeout(const Duration(seconds: 30), onTimeout: () {
        cancel();
        throw TimeoutException('Image recognition timed out');
      }),
      cancel);
}
