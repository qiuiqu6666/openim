import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../mine/settings/widgets/settings_widgets.dart';

abstract final class _RetentionSettingTokens {
  static const compactWidth = 320.0;
  static const stackedTextScale = 1.3;
  static const textHeight = 1.4;
  static const disabledOpacity = .45;
}

/// A retention option reuses the shared settings card and whole-row action.
/// Title/value stack when a phone or larger text needs more reading room.
class MessageRetentionSetting extends StatelessWidget {
  const MessageRetentionSetting({
    super.key,
    required this.rowKey,
    required this.title,
    required this.value,
    required this.description,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final Key rowKey;
  final String title;
  final String value;
  final String description;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final opacity = enabled ? 1.0 : _RetentionSettingTokens.disabledOpacity;
    final titleStyle = TextStyle(
      color: AppTokens.textPrimary(dark: dark).withValues(alpha: opacity),
      fontSize: AppTokens.listTitleFontSize,
      height: _RetentionSettingTokens.textHeight,
    );
    final valueStyle = TextStyle(
      color: AppTokens.textSecondary(dark: dark).withValues(alpha: opacity),
      fontSize: AppTokens.captionFontSize,
      height: _RetentionSettingTokens.textHeight,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          margin: EdgeInsets.zero,
          children: [
            LayoutBuilder(builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < _RetentionSettingTokens.compactWidth ||
                      SettingsResponsive.textScale(context) >
                          _RetentionSettingTokens.stackedTextScale ||
                      value.length > 12;
              return Semantics(
                button: true,
                enabled: enabled,
                label: '$title，$value',
                hint:
                    settingsText(context, zh: '选择时长', en: 'Choose a duration'),
                onTap: enabled ? onTap : null,
                excludeSemantics: true,
                child: SettingsCell(
                  key: rowKey,
                  title: title,
                  titleWidget: stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: titleStyle),
                            const SizedBox(height: AppTokens.s2),
                            Text(value, style: valueStyle),
                          ],
                        )
                      : Text(title, style: titleStyle),
                  value: stacked ? null : value,
                  valueStyle: valueStyle,
                  icon: icon,
                  showDivider: false,
                  enabled: enabled,
                  onTap: onTap,
                ),
              );
            }),
          ],
        ),
        SettingsSectionText(description,
            top: AppTokens.s3, bottom: AppTokens.s5),
      ],
    );
  }
}
