import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

enum _AvatarAction { view, change }

/// Shared avatar actions; callers retain ownership of picking and saving.
abstract final class AvatarActions {
  static bool canPreview({String? url, Uint8List? bytes}) =>
      bytes?.isNotEmpty == true || IMUtils.isUrlValid(url?.trim());

  static void preview(BuildContext context, {String? url, Uint8List? bytes}) {
    if (!context.mounted || !canPreview(url: url, bytes: bytes)) return;
    final address = url?.trim() ?? '';
    if (bytes?.isNotEmpty == true) {
      IMUtils.previewMediaFile(
        context: context,
        message: Message(),
        sources: [MediaSource(thumbnail: address, url: address, bytes: bytes)],
        showGallery: false,
        showCounter: false,
      );
    } else {
      IMUtils.previewUrlPicture(
        [MediaSource(thumbnail: address, url: address)],
        showSaveButton: true,
      );
    }
  }

  static Future<void> open(
    BuildContext context, {
    String? url,
    Uint8List? bytes,
    required VoidCallback onChange,
    bool Function()? isActive,
  }) async {
    if (!context.mounted || isActive?.call() == false) return;
    final action = await showAppActionSheet<_AvatarAction>(
      context,
      title: StrRes.avatar,
      actions: [
        if (canPreview(url: url, bytes: bytes))
          AppAction(StrRes.viewAvatar, _AvatarAction.view),
        AppAction(StrRes.selectAssetsFromAlbum, _AvatarAction.change),
      ],
    );
    if (!context.mounted || isActive?.call() == false) return;
    switch (action) {
      case _AvatarAction.view:
        preview(context, url: url, bytes: bytes);
        break;
      case _AvatarAction.change:
        onChange();
        break;
      case null:
        break;
    }
  }
}
