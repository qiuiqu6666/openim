import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'wallet_99chat_app_colors.dart';
import 'wallet_99chat_tokens.dart';
import 'wallet_system_ui.dart';

/// 钱包子页面（转账、红包等）双主题配色 + 与搜索页一致的顶栏色。
class WalletPageColors {
  final bool dark;
  final Color bg;
  final Color card;
  final Color text;
  final Color subText;
  final Color line;
  final Color shadow;
  final Color red;
  final Color blue;

  /// 输入框光标/选区高亮（深色背景下避免使用偏黑的主题色）。
  final Color inputCursor;
  final Color inputHint;

  /// 表单输入区背景（略区别于 [card]，无阴影扁平风格）。
  final Color inputFill;
  final Color avatarPlaceholder;
  final Color avatarIcon;
  final Color filterActiveBg;
  final Color filterActiveText;
  final Color filterActiveBorder;
  final Color filterInactiveBg;
  final Color filterInactiveText;
  final Color tagBg;
  final Color tagBorder;
  final Color tagTextColor;
  final Color warningBg;
  final Color warningText;
  final Color warningIconBg;
  final Color surfaceAlt;
  final Color disabledButton;

  const WalletPageColors({
    required this.dark,
    required this.bg,
    required this.card,
    required this.text,
    required this.subText,
    required this.line,
    required this.shadow,
    required this.red,
    required this.blue,
    required this.inputCursor,
    required this.inputHint,
    required this.inputFill,
    required this.avatarPlaceholder,
    required this.avatarIcon,
    required this.filterActiveBg,
    required this.filterActiveText,
    required this.filterActiveBorder,
    required this.filterInactiveBg,
    required this.filterInactiveText,
    required this.tagBg,
    required this.tagBorder,
    required this.tagTextColor,
    required this.warningBg,
    required this.warningText,
    required this.warningIconBg,
    required this.surfaceAlt,
    required this.disabledButton,
  });

  factory WalletPageColors.of(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    const accentBlue = AppColors.primaryBlue;
    return WalletPageColors(
      dark: dark,
      bg: AppColors.background(dark: dark),
      card: AppColors.card(dark: dark),
      text: AppColors.text(dark: dark),
      subText: AppColors.subText(dark: dark),
      line: AppColors.line(dark: dark),
      shadow: AppColors.shadow(dark: dark),
      red: AppColors.primaryRed,
      blue: accentBlue,
      inputCursor: dark ? AppTokens.brand400 : accentBlue,
      inputHint: AppColors.subText(dark: dark),
      inputFill: AppColors.surfaceAlt(dark: dark),
      avatarPlaceholder: dark ? AppTokens.borderDark : AppTokens.brand100,
      avatarIcon: dark ? AppTokens.ink300 : AppTokens.ink500,
      filterActiveBg:
          dark ? accentBlue.withValues(alpha: 0.28) : AppTokens.accentSoft,
      filterActiveText: dark ? const Color(0xFFFFFFFF) : accentBlue,
      filterActiveBorder:
          dark ? accentBlue : accentBlue.withValues(alpha: 0.35),
      filterInactiveBg:
          dark ? AppTokens.surfaceAltDark : AppTokens.surfaceAltLight,
      filterInactiveText: AppColors.text(dark: dark),
      tagBg:
          dark ? AppTokens.warningSurfaceDark : AppTokens.warningSurfaceLight,
      tagBorder: dark
          ? AppTokens.warning.withValues(alpha: 0.45)
          : AppTokens.warning.withValues(alpha: 0.25),
      tagTextColor: dark ? const Color(0xFFE8C46A) : AppTokens.warning,
      warningBg:
          dark ? AppTokens.warningSurfaceDark : AppTokens.warningSurfaceLight,
      warningText: dark ? const Color(0xFFE8C46A) : AppTokens.warning,
      warningIconBg: dark ? AppTokens.warning : const Color(0xFFF2C230),
      surfaceAlt: AppColors.surfaceAlt(dark: dark),
      disabledButton: dark ? const Color(0xFF3A3D45) : AppTokens.ink200,
    );
  }
}

class WalletAppBarColors {
  final Color background;
  final Color title;
  final Color icon;

  const WalletAppBarColors({
    required this.background,
    required this.title,
    required this.icon,
  });

  factory WalletAppBarColors.of(BuildContext context) {
    final cs = WalletPageColors.of(context);
    return WalletAppBarColors(
      background: cs.bg,
      title: cs.text,
      icon: AppColors.primaryBlue,
    );
  }
}

SystemUiOverlayStyle walletPageOverlayStyle(BuildContext context) {
  final cs = WalletPageColors.of(context);
  return immersiveOverlayForColors(
    statusBarBackground: cs.bg,
    navigationBarBackground: cs.bg,
  );
}

/// 钱包子页面包裹：透明系统栏 + 与 Tab 内钱包页一致的图标明暗。
Widget wrapWalletPage(BuildContext context, Widget child) {
  return AnnotatedRegion<SystemUiOverlayStyle>(
    value: walletPageOverlayStyle(context),
    child: child,
  );
}
