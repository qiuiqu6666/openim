import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../theme/profile_tokens.dart';
import 'group_qrcode_logic.dart';

abstract final class _QrTokens {
  static const maxCardWidth = 420.0;
  static const padding = 24.0;
  static const avatar = 48.0;
  static const qrSize = 248.0;
  static const quietZone = 20.0;
}

class GroupQrcodePage extends StatelessWidget {
  final logic = Get.find<GroupQrcodeLogic>();

  GroupQrcodePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final group = logic.groupSetupLogic.groupInfo.value;
      return Scaffold(
        appBar: GlassAppBar(
          centerTitle: true,
          title: Text(StrRes.groupQrcode, style: Styles.ts_0C1C33_17sp),
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Get.back(),
            icon:
                Icon(Icons.arrow_back_ios_new_rounded, color: Styles.c_0089FF),
          ),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(_QrTokens.padding),
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: _QrTokens.maxCardWidth),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  RepaintBoundary(
                      key: logic.cardKey,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(_QrTokens.padding),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius:
                              BorderRadius.circular(ProfileTokens.radius),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: [
                              AvatarView(
                                width: _QrTokens.avatar,
                                height: _QrTokens.avatar,
                                url: group.faceURL,
                                text: group.groupName,
                                isGroup: true,
                              ),
                              const SizedBox(width: ProfileTokens.gutter),
                              Expanded(
                                  child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(group.groupName ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(StrRes.groupQrcode,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSurfaceVariant)),
                                ],
                              )),
                            ]),
                            const SizedBox(height: _QrTokens.padding),
                            LayoutBuilder(builder: (_, constraints) {
                              final size = math.min(
                                  _QrTokens.qrSize, constraints.maxWidth);
                              // Keep the quiet zone white in both themes. The code
                              // itself has no decorative frame or overlaid logo.
                              return Container(
                                decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(
                                        ProfileTokens.radius)),
                                child: QrImageView(
                                  data: logic.buildQRContent(),
                                  size: size,
                                  padding:
                                      const EdgeInsets.all(_QrTokens.quietZone),
                                  backgroundColor: Colors.white,
                                  eyeStyle: const QrEyeStyle(
                                      eyeShape: QrEyeShape.square,
                                      color: Colors.black),
                                  dataModuleStyle: const QrDataModuleStyle(
                                      dataModuleShape: QrDataModuleShape.square,
                                      color: Colors.black),
                                ),
                              );
                            }),
                            const SizedBox(height: _QrTokens.padding),
                            Text(StrRes.groupQrcodeHint,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    height: 1.5)),
                          ],
                        ),
                      )),
                  const SizedBox(height: _QrTokens.padding),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            logic.saving.value ? null : logic.saveToAlbum,
                        icon: logic.saving.value
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.download_outlined),
                        label: Text(StrRes.saveToAlbum),
                      )),
                  const SizedBox(height: ProfileTokens.gutter),
                  SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: logic.scanning.value ? null : logic.scan,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: Text(StrRes.scan),
                      )),
                ]),
              ),
            ),
          ),
        ),
      );
    });
  }
}
