import 'package:flutter/material.dart';

import '../widgets/wallet_page_colors.dart';
import 'wallet_i18n.dart';

/// Wallet-local copy of 99chat's shared empty-state presentation.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    this.message,
    this.imageWidth,
    this.padding,
    this.onRetry,
  });

  static const String assetPath = 'assets/img/empty.webp';

  final String? message;
  final double? imageWidth;
  final EdgeInsetsGeometry? padding;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final w = imageWidth ?? 160;
    final textColor = cs.subText;

    return Padding(
      padding: padding ??
          const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              assetPath,
              width: w,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.inbox_outlined,
                size: w * 0.45,
                color: textColor.withValues(alpha: 0.45),
              ),
            ),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: textColor,
                  height: 1.4,
                ),
              ),
            ],
            if (onRetry != null && message != null && message!.isNotEmpty) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => onRetry!(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  AppI18n.of(context).t(
                    zhHans: '点击重新加载',
                    zhHant: '點擊重新載入',
                    en: 'Tap to reload',
                    ja: 'タップで再読み込み',
                    ko: '탭하여 다시 불러오기',
                  ),
                  style: TextStyle(
                    color: cs.blue,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
