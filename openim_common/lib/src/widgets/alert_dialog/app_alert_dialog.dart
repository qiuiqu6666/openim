import 'package:flutter/cupertino.dart';

import '../action_sheet/app_action_sheet.dart';

/// Shared iOS alert, extracted from the settings confirmation dialog.
/// Callers keep ownership of business actions and perform them after closing.
class AppAlertDialog<T> extends StatelessWidget {
  const AppAlertDialog({
    super.key,
    required this.title,
    this.message,
    required this.actions,
    this.onSelected,
  });

  final String title;
  final String? message;
  final List<AppAction<T>> actions;
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) {
    var closing = false;
    void select(T value) {
      if (closing || ModalRoute.of(context)?.isCurrent != true) return;
      if (onSelected != null) {
        onSelected!(value);
      } else {
        closing = true;
        Navigator.of(context).pop<T>(value);
      }
    }

    return CupertinoAlertDialog(
      title: title.isEmpty ? null : Text(title),
      content: message == null || message!.isEmpty ? null : Text(message!),
      actions: [
        for (final action in actions)
          CupertinoDialogAction(
            key: action.key,
            isDestructiveAction: action.destructive,
            onPressed: action.enabled ? () => select(action.value) : null,
            child: Text(action.label),
          ),
      ],
    );
  }
}

Future<T?> showAppAlert<T>(
  BuildContext context, {
  required String title,
  String? message,
  required List<AppAction<T>> actions,
  bool barrierDismissible = false,
}) =>
    showCupertinoDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => AppAlertDialog<T>(
        title: title,
        message: message,
        actions: actions,
      ),
    );

Future<bool> showAppConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmText,
  String? cancelText,
  bool destructive = false,
  bool barrierDismissible = false,
}) async =>
    await showAppAlert<bool>(
      context,
      title: title,
      message: message,
      barrierDismissible: barrierDismissible,
      actions: [
        AppAction(
            cancelText ?? CupertinoLocalizations.of(context).cancelButtonLabel,
            false),
        AppAction(confirmText, true, destructive: destructive),
      ],
    ) ??
    false;
