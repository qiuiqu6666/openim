import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

enum MediaAction { save, forward, viewInChat, delete }

/// Media capabilities supply actions to the app's shared action sheet.
Future<MediaAction?> showMediaActionSheet(
  BuildContext context, {
  required bool canSave,
  required bool canForward,
  required bool canViewInChat,
  required bool canDelete,
}) =>
    showAppActionSheet<MediaAction>(context, title: '', actions: [
      if (canSave) AppAction(StrRes.saveToAlbum, MediaAction.save),
      if (canForward) AppAction(StrRes.menuForward, MediaAction.forward),
      if (canViewInChat)
        AppAction('mediaViewInChat'.tr, MediaAction.viewInChat),
      if (canDelete)
        AppAction(StrRes.delete, MediaAction.delete, destructive: true),
    ]);
