// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:flutter/material.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';

/// 与设置页一致的返回箭头。
class AppBackButton extends StatelessWidget {
  /// Kept for existing callers; the shared back arrow always uses app blue.
  final Color? color;
  final VoidCallback? onPressed;

  const AppBackButton({
    super.key,
    this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded),
      color: AppTokens.accent,
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
    );
  }
}
