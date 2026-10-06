import 'package:flutter/material.dart';

import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../wallet_home_tokens.dart';

/// A wallet shortcut with one Material owning both its shape and its ink.
/// The three compact, equally sized actions in the balance overview.
class WalletHomeAction extends StatelessWidget {
  const WalletHomeAction({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final foreground =
        primary ? WalletHomeTokens.onOverviewAction(context) : colors.text;
    final radius = BorderRadius.circular(AppTokens.rSm);
    return Semantics(
      button: true,
      child: Material(
        color: primary
            ? WalletHomeTokens.overviewAction(context)
            : colors.surfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: WalletHomeTokens.primaryActionHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.s2,
                vertical: AppTokens.s2,
              ),
              child: Center(
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: WalletHomeTokens.body,
                        fontWeight: FontWeight.w500,
                        color: foreground)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
