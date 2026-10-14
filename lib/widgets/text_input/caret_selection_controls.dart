import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

TextSelectionControls? caretSelectionControls(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.iOS => CaretCupertinoSelectionControls(),
      TargetPlatform.android || TargetPlatform.fuchsia =>
        CaretMaterialSelectionControls(),
      _ => null,
    };

/// Hide only the caret handle; retain native range selection and menus.
final class CaretMaterialSelectionControls
    extends MaterialTextSelectionControls with TextSelectionHandleControls {
  @override
  Widget buildHandle(
      BuildContext context, TextSelectionHandleType type, double textHeight,
      [VoidCallback? onTap]) {
    if (type == TextSelectionHandleType.collapsed) {
      return const SizedBox.shrink();
    }
    return super.buildHandle(context, type, textHeight, onTap);
  }
}

final class CaretCupertinoSelectionControls
    extends CupertinoTextSelectionControls with TextSelectionHandleControls {
  @override
  Widget buildHandle(
      BuildContext context, TextSelectionHandleType type, double textLineHeight,
      [VoidCallback? onTap]) {
    if (type == TextSelectionHandleType.collapsed) {
      return const SizedBox.shrink();
    }
    return super.buildHandle(context, type, textLineHeight, onTap);
  }
}
