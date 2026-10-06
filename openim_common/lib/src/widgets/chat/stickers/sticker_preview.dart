import 'package:flutter/material.dart';

import '../../photo_browser.dart';

/// Single sticker preview using the shared media viewer without media actions.
Future<void> showStickerPreview(BuildContext context, MediaSource source) {
  FocusManager.instance.primaryFocus?.unfocus();
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      fullscreenDialog: true,
      pageBuilder: (_, __, ___) => MediaBrowser(
        sources: [source],
        initialIndex: 0,
        closeOnly: true,
        showGallery: false,
        showCounter: false,
        muted: true,
        onAutoPlay: (_) => true,
      ),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}
