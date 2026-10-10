import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

const _watermarkAsset =
    'lib/pages/chat/group_setup/group_qrcode/assets/99chat_watermark.png';
const groupQrcodeWatermarkImage = AssetImage(_watermarkAsset);

/// Keeps the supplied artwork intact and removes its white backing in dark mode.
DecorationImage groupQrcodeBackgroundImage({required bool dark}) {
  final tint = AppTokens.accent;
  return DecorationImage(
    image: groupQrcodeWatermarkImage,
    fit: BoxFit.cover,
    colorFilter: dark
        ? ColorFilter.matrix([
            0, 0, 0, 0, tint.r * 255,
            0, 0, 0, 0, tint.g * 255,
            0, 0, 0, 0, tint.b * 255,
            // The source is white with blue artwork: A - R makes white clear.
            -1, 0, 0, 1, 0,
          ])
        : null,
  );
}
