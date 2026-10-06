import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// A typed choice; the caller performs the operation after the sheet closes.
class AppAction<T> {
  const AppAction(
    this.label,
    this.value, {
    this.key,
    this.subtitle,
    this.selected = false,
    this.enabled = true,
    this.destructive = false,
  });

  final String label;
  final Key? key;
  final String? subtitle;
  final T value;
  final bool selected;
  final bool enabled;
  final bool destructive;
}

/// The existing application choice sheet, shared with package-owned surfaces.
/// Layout follows 99chat's AppDialog.actionSheet (Apache 2.0).
Future<T?> showAppActionSheet<T>(
  BuildContext context, {
  required String title,
  required List<AppAction<T>> actions,
}) {
  HapticFeedback.selectionClick();
  final cancelLabel = CupertinoLocalizations.of(context).cancelButtonLabel;
  var closing = false;
  void close(BuildContext sheetContext, [T? value]) {
    if (closing || ModalRoute.of(sheetContext)?.isCurrent != true) {
      return;
    }
    closing = true;
    Navigator.of(sheetContext).pop<T>(value);
  }

  return showCupertinoModalPopup<T>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: title.trim().isEmpty
          ? null
          : Text(title, style: _ActionSheetTokens.headingStyle),
      actions: [
        for (final action in actions)
          Semantics(
            key: action.key,
            enabled: action.enabled,
            selected: action.selected,
            child: CupertinoActionSheetAction(
              isDestructiveAction: action.destructive,
              onPressed: action.enabled
                  ? () => close(sheetContext, action.value)
                  : () {},
              child: _ActionSheetLabel(
                label: action.label,
                subtitle: action.subtitle,
                enabled: action.enabled,
              ),
            ),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => close(sheetContext),
        child: Text(cancelLabel),
      ),
    ),
  );
}

abstract final class _ActionSheetTokens {
  static const headingStyle =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const subtitleGap = 2.0;
  static const subtitleSize = 12.0;
}

class _ActionSheetLabel extends StatelessWidget {
  const _ActionSheetLabel({
    required this.label,
    required this.enabled,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final disabledColor = CupertinoColors.systemGrey.resolveFrom(context);
    final title = Text(
      label,
      style: enabled ? null : TextStyle(color: disabledColor),
    );
    final detail = subtitle?.trim() ?? '';
    if (detail.isEmpty) {
      return title;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        title,
        const SizedBox(height: _ActionSheetTokens.subtitleGap),
        Text(
          detail,
          style: TextStyle(
            fontSize: _ActionSheetTokens.subtitleSize,
            color: enabled
                ? CupertinoColors.secondaryLabel.resolveFrom(context)
                : disabledColor,
          ),
        ),
      ],
    );
  }
}
