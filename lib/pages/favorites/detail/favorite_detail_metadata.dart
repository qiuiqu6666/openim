import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/favorite_repository.dart';
import '../../mine/settings/widgets/settings_widgets.dart';
import 'favorite_detail_tokens.dart';

class FavoriteDetailMetadata extends StatelessWidget {
  const FavoriteDetailMetadata({super.key, required this.item});
  final FavoriteItem item;

  @override
  Widget build(BuildContext context) {
    final source = item.source?.displayName?.trim() ?? '';
    if (source.isEmpty && item.createdAt == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s2, vertical: AppTokens.s6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (source.isNotEmpty)
          _row(context, settingsText(context, zh: '来源', en: 'From'), source),
        if (source.isNotEmpty && item.createdAt != null)
          const SizedBox(height: AppTokens.s4),
        if (item.createdAt != null)
          _row(context, settingsText(context, zh: '收藏时间', en: 'Saved'),
              DateFormat('yyyy-MM-dd HH:mm').format(item.createdAt!.toLocal())),
      ]),
    );
  }

  Widget _row(BuildContext context, String label, String value) =>
      LayoutBuilder(builder: (context, constraints) {
        final title = Text(label,
            style: TextStyle(
                fontSize: AppTokens.captionFontSize,
                color: settingsSecondaryTextColor(context)));
        final content = Text(value,
            style: TextStyle(
                fontSize: AppTokens.captionFontSize,
                height: FavoriteDetailTokens.metadataLineHeight,
                color: settingsTextColor(context)));
        if (MediaQuery.textScalerOf(context).scale(1) >
            FavoriteDetailTokens.stackedTextScale) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: AppTokens.s2), content]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 1, child: title),
          const SizedBox(width: AppTokens.s4),
          Expanded(flex: 3, child: content),
        ]);
      });
}
