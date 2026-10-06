import 'package:flutter/material.dart';
import '../../mine/settings/widgets/settings_widgets.dart';

class MomentsStatePanel extends StatelessWidget {
  const MomentsStatePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.onAction,
    this.actionLabel,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return SettingsEmptyState(
        icon: icon,
        title: title,
        description: message,
        actionLabel: actionLabel,
        onAction: onAction,
        imageWidth: 180);
  }
}
