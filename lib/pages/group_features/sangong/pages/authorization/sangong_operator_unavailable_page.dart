import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';
import '../../support/settings_exports.dart';

/// Keeps an existing configuration separate from unavailable game operations.
class SangongOperatorUnavailablePage extends StatelessWidget {
  const SangongOperatorUnavailablePage(
      {super.key,
      required this.reason,
      required this.onRetry,
      this.onViewConfig});

  final String reason;
  final VoidCallback onRetry;
  final VoidCallback? onViewConfig;

  @override
  Widget build(BuildContext context) =>
      SettingsScaffold(title: '三公管理', children: [
        const SizedBox(height: 100),
        Text(AppCopy.text(reason), textAlign: TextAlign.center),
        SettingsPrimaryButton(text: AppCopy.text('重试'), onPressed: onRetry),
        if (onViewConfig != null)
          Center(
              child: TextButton(
                  onPressed: onViewConfig, child: Text(AppCopy.text('查看我的配置'))))
      ]);
}
