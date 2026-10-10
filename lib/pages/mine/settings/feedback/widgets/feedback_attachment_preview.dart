import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Screenshot preview keeps a readable placeholder when an image is invalid.
class FeedbackAttachmentPreview extends StatelessWidget {
  const FeedbackAttachmentPreview({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, _, __) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return ColoredBox(
            color: AppTokens.surfaceAlt(dark: dark),
            child: Icon(
              Icons.broken_image_outlined,
              color: AppTokens.textSecondary(dark: dark),
            ),
          );
        },
      );
}
