import 'dart:io';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../pages/storage_media_repository.dart';
import '../../widgets/settings_widgets.dart';

class StorageMediaThumbnail extends StatelessWidget {
  const StorageMediaThumbnail(
      {super.key, required this.item, this.fit = BoxFit.cover});

  final StorageMediaItem item;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.rSm),
      child: ColoredBox(
        color: AppTokens.surface(dark: dark),
        child: Stack(fit: StackFit.expand, children: [
          if (item.previewPath != null)
            Image.file(File(item.previewPath!),
                fit: fit,
                cacheWidth: 280,
                errorBuilder: (_, __, ___) => _fileIcon(context))
          else
            _fileIcon(context),
          if (item.type == StorageMediaType.video)
            const Center(
              child: Icon(Icons.play_circle_fill_rounded,
                  size: 30, color: AppTokens.onAccent),
            ),
        ]),
      ),
    );
  }

  Widget _fileIcon(BuildContext context) => Center(
        child: Icon(
          item.type == StorageMediaType.file
              ? Icons.insert_drive_file_rounded
              : Icons.image_outlined,
          size: 30,
          color: AppTokens.accent,
        ),
      );
}
