import 'package:flutter/material.dart';

import '../moments_widgets.dart';

/// Personal timeline disclosure, with the same reference spacing in both modes.
class MomentsProfileRangeHint extends StatelessWidget {
  const MomentsProfileRangeHint(
      {super.key, required this.days, this.onSettings});

  final int days;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final dark = momentsDark(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Column(children: [
        Row(children: [
          Expanded(child: Divider(height: 1, color: MomentsTheme.border(dark))),
          const SizedBox(width: 12),
          Flexible(
              flex: 4,
              child: Text(
                  momentsText(context,
                      zh: onSettings != null
                          ? '朋友仅能查看最近$days天的朋友圈'
                          : '仅展示最近$days天动态',
                      en: 'Posts from the past $days days'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: MomentsTheme.secondary(dark),
                      fontSize: 13,
                      height: 1.35))),
          const SizedBox(width: 12),
          Expanded(child: Divider(height: 1, color: MomentsTheme.border(dark))),
        ]),
        if (onSettings != null) ...[
          const SizedBox(height: 12),
          TextButton(
              onPressed: onSettings,
              child: Text(
                  momentsText(context, zh: '前往设置', en: 'Go to settings'),
                  style: const TextStyle(fontSize: 14))),
        ],
      ]),
    );
  }
}
