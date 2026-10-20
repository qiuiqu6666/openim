import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/localization.dart';

import '../../mine/settings/widgets/settings_widgets.dart';

/// Uploading bytes is not the final server-side validation/save acknowledgement.
class FavoriteMediaProgress extends StatelessWidget {
  const FavoriteMediaProgress({super.key, required this.progress});
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final uploaded = progress != null && progress! >= 1;
    final label = uploaded
        ? settingsText(context,
            zh: '上传完成，正在校验并保存，暂未收藏成功',
            en: 'Upload complete. Validating and saving; not saved yet.')
        : progress == null
            ? settingsText(context,
                zh: '正在准备原文件…', en: 'Preparing original file…')
            : settingsText(context,
                zh: AppCopy.format(
                    '正在上传原文件 {#0}%', [(progress!.clamp(0, 1) * 100).floor()],
                    locale: Localizations.localeOf(context)),
                en: 'Uploading original ${(progress!.clamp(0, 1) * 100).floor()}%');
    return Semantics(
      // Announce phase changes, not every percentage update.
      liveRegion: uploaded || progress == null,
      label: label,
      excludeSemantics: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        LinearProgressIndicator(value: uploaded ? null : progress),
        Padding(
          padding: const EdgeInsets.all(AppTokens.s3),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(color: settingsTextColor(context))),
        ),
      ]),
    );
  }
}
