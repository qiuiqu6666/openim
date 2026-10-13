import 'dart:io';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class QrContentActions {
  const QrContentActions();
  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
  Future<bool> openBrowser(Uri uri) {
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return Future.value(false);
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> exportContact(String vcard, Rect origin) async {
    final directory = await Directory.systemTemp.createTemp('qr-contact-');
    try {
      final file =
          await File('${directory.path}/contact.vcf').writeAsString(vcard);
      await Share.shareXFiles([XFile(file.path, mimeType: 'text/vcard')],
          sharePositionOrigin: origin);
    } finally {
      await directory.delete(recursive: true);
    }
  }
}
