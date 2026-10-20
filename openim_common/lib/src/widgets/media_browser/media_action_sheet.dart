import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'media_share_sheet.dart';
import 'recognition/media_image_recognition.dart';
export 'media_share_sheet.dart';

Future<MediaSheetSelection?> showMediaActionSheet(
  BuildContext context, {
  required bool canSave,
  required bool canForward,
  required bool canViewInChat,
  required bool canDelete,
  bool canFavorite = false,
  bool canShowGallery = false,
  Future<List<MediaShareRecipient>> Function()? loadRecipients,
  MediaRecognitionRequest Function()? recognize,
}) =>
    showModalBottomSheet<MediaSheetSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTokens.surfaceAlt(
          dark: Theme.of(context).brightness == Brightness.dark),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppTokens.s6))),
      clipBehavior: Clip.antiAlias,
      builder: (_) => MediaShareSheet(
        canSave: canSave,
        canForward: canForward,
        canViewInChat: canViewInChat,
        canDelete: canDelete,
        canFavorite: canFavorite,
        canShowGallery: canShowGallery,
        loadRecipients: canForward ? loadRecipients : null,
        recognize: recognize,
      ),
    );
