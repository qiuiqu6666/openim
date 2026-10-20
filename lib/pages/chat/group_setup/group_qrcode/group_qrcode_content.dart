import 'package:openim_common/localization.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'group_qrcode_background.dart';
import 'group_qrcode_tokens.dart';

/// Presentation only: the existing group controller owns saving and scanning.
class GroupQrcodeContent extends StatelessWidget {
  const GroupQrcodeContent(
      {super.key,
      required this.groupName,
      required this.groupId,
      this.faceUrl,
      required this.qrData,
      required this.cardKey,
      this.saving = false,
      this.scanning = false,
      required this.onSave,
      required this.onScan,
      required this.onCopy});
  final String groupName, groupId, qrData;
  final String? faceUrl;
  final GlobalKey cardKey;
  final bool saving, scanning;
  final VoidCallback onSave, onScan, onCopy;

  String _text(BuildContext context, String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = AppTokens.textPrimary(dark: dark);
    final sub = AppTokens.textSecondary(dark: dark);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.s5, AppTokens.s5, AppTokens.s5, AppTokens.s7),
      child: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: GroupQrcodeTokens.maxWidth),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          RepaintBoundary(
              key: cardKey,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(GroupQrcodeTokens.cardPadding),
                decoration: BoxDecoration(
                    color: AppTokens.surface(dark: dark),
                    image: groupQrcodeBackgroundImage(dark: dark),
                    borderRadius:
                        BorderRadius.circular(GroupQrcodeTokens.cardRadius)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    AvatarView(
                        width: GroupQrcodeTokens.avatar,
                        height: GroupQrcodeTokens.avatar,
                        url: faceUrl,
                        text: groupName,
                        isGroup: true),
                    const SizedBox(width: AppTokens.s4),
                    Expanded(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(groupName,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: text,
                                  fontSize: GroupQrcodeTokens.titleSize,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3)),
                          const SizedBox(height: AppTokens.s2),
                          Text(groupId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: sub,
                                  fontSize: GroupQrcodeTokens.idSize,
                                  letterSpacing: .3)),
                          const SizedBox(height: AppTokens.s2),
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppTokens.s3,
                                  vertical: AppTokens.s2),
                              decoration: BoxDecoration(
                                  color: AppTokens.surfaceAlt(dark: dark),
                                  borderRadius:
                                      BorderRadius.circular(AppTokens.rSm)),
                              child: Text(StrRes.groupQrcode,
                                  style: TextStyle(
                                      color: sub,
                                      fontSize: GroupQrcodeTokens.captionSize,
                                      fontWeight: FontWeight.w600))),
                        ])),
                    IconButton(
                        tooltip: _text(
                            context, AppCopy.text('复制群号'), 'Copy group ID'),
                        onPressed: groupId.isEmpty ? null : onCopy,
                        constraints:
                            const BoxConstraints(minWidth: 48, minHeight: 48),
                        icon: Icon(Icons.content_copy_rounded,
                            size: 18, color: sub)),
                  ]),
                  const SizedBox(height: AppTokens.s4),
                  LayoutBuilder(
                      builder: (_, constraints) => Container(
                            decoration: BoxDecoration(
                                color: AppTokens.onAccent,
                                borderRadius: BorderRadius.circular(
                                    GroupQrcodeTokens.cardRadius),
                                border:
                                    Border.all(color: AppTokens.borderLight)),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                  GroupQrcodeTokens.cardRadius - 1),
                              child: QrImageView(
                                data: qrData,
                                size: math.min(GroupQrcodeTokens.qrSize,
                                    constraints.maxWidth),
                                padding: const EdgeInsets.all(
                                    GroupQrcodeTokens.qrQuietZone),
                                backgroundColor: AppTokens.onAccent,
                                eyeStyle: const QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: Colors.black),
                                dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: Colors.black),
                              ),
                            ),
                          )),
                  const SizedBox(height: AppTokens.s5),
                  Text(
                      _text(context, AppCopy.text('扫一扫二维码，立即加入群聊'),
                          'Scan the QR code to join this group'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: sub,
                          fontSize: GroupQrcodeTokens.bodySize,
                          height: 1.5)),
                ]),
              )),
          const SizedBox(height: AppTokens.s5),
          SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: saving ? null : onSave,
                icon: saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTokens.onAccent))
                    : const Icon(Icons.file_download_outlined),
                label: Text(StrRes.saveToAlbum),
                style: FilledButton.styleFrom(
                    backgroundColor: AppTokens.accent,
                    foregroundColor: AppTokens.onAccent,
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(
                        vertical: AppTokens.s4, horizontal: AppTokens.s5),
                    shape: const StadiumBorder(),
                    textStyle: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
              )),
          const SizedBox(height: AppTokens.s4),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: scanning ? null : onScan,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(StrRes.scan),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppTokens.accent,
                    side: BorderSide(
                        color: AppTokens.accent.withValues(alpha: .25)),
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(
                        vertical: AppTokens.s4, horizontal: AppTokens.s5),
                    shape: const StadiumBorder(),
                    textStyle: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
              )),
        ]),
      )),
    );
  }
}
