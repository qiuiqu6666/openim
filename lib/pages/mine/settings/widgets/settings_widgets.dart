import 'dart:math' as math;
import '../security_feedback.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

String settingsText(
  BuildContext context, {
  required String zh,
  required String en,
}) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

bool settingsIsDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color settingsSurfaceAlt(bool dark) => AppTokens.surfaceAlt(dark: dark);

Color settingsDanger(bool dark) => AppTokens.paymentError(dark: dark);

Color settingsTextColor(BuildContext context) =>
    AppTokens.textPrimary(dark: settingsIsDark(context));

Color settingsSecondaryTextColor(BuildContext context) =>
    AppTokens.textSecondary(dark: settingsIsDark(context));

Color settingsBorderColor(BuildContext context) =>
    AppTokens.border(dark: settingsIsDark(context));

Color settingsSurfaceColor(BuildContext context) =>
    AppTokens.surface(dark: settingsIsDark(context));

/// Mirrors the 99chat AppResponsive values used by Settings surfaces.
class SettingsResponsive {
  SettingsResponsive._();

  static bool isDesktop(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (kIsWeb) {
      // Tencent TUIKit/99chat classifies web form factor from the logical
      // screen diagonal at the browser-standard 96dpi threshold.
      final diagonalInInches =
          math.sqrt(size.width * size.width + size.height * size.height) / 96.0;
      return diagonalInInches >= 11.0;
    }

    // Match TUIKitScreenUtils.getFormFactor(context): desktop starts at a
    // 900px-wide surface or a clearly landscape/wide window. This keeps
    // Android tablets, iPad/windowed layouts and desktop resizes aligned with
    // 99chat instead of relying on the operating-system name.
    return size.width > 900 || size.width > size.height * 1.1;
  }

  static double textScale(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1.0);

  static double _extraForScale(
    BuildContext context, {
    required double mobileStep,
    required double desktopStep,
    double maxExtra = 10,
  }) {
    final delta = math.max(0.0, textScale(context) - 1.0);
    final step = isDesktop(context) ? desktopStep : mobileStep;
    return math.min(maxExtra, delta * step);
  }

  static double listRowMinHeight(BuildContext context) =>
      (isDesktop(context) ? 52.0 : 56.0) +
      _extraForScale(
        context,
        mobileStep: 8,
        desktopStep: 4,
        maxExtra: 12,
      );

  static EdgeInsets listRowPadding(BuildContext context) =>
      EdgeInsets.symmetric(
        horizontal: isDesktop(context) ? 20 : 16,
        vertical: (isDesktop(context) ? 10 : 12) +
            _extraForScale(
              context,
              mobileStep: 4,
              desktopStep: 2,
              maxExtra: 6,
            ),
      );

  static double controlHeight(BuildContext context) =>
      (isDesktop(context) ? 44.0 : 48.0) +
      _extraForScale(
        context,
        mobileStep: 6,
        desktopStep: 4,
        maxExtra: 10,
      );

  static double labelWidth(BuildContext context) =>
      (isDesktop(context) ? 104.0 : 88.0) +
      _extraForScale(
        context,
        mobileStep: 10,
        desktopStep: 6,
        maxExtra: 20,
      );
}

class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.children,
    this.titleWidget,
    this.leading,
    this.actions,
    this.bottom,
    this.body,
    this.onLeadingPressed,
    this.disableLeading = false,
    this.showLeading = true,
    this.dismissKeyboardOnOutsideTap = false,
    this.embedded = false,
    this.scrollController,
    this.backgroundColor,
    this.leadingColor,
  });

  final String title;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget> children;
  final List<Widget>? actions;
  final Widget? bottom;

  /// Custom content for pages that need a fixed footer and adaptive layout.
  final Widget? body;
  final VoidCallback? onLeadingPressed;
  final bool disableLeading;
  final bool showLeading;
  final bool dismissKeyboardOnOutsideTap;
  final bool embedded;
  final ScrollController? scrollController;
  final Color? backgroundColor;
  final Color? leadingColor;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final background = backgroundColor ?? AppTokens.background(dark: dark);
    final text = AppTokens.textPrimary(dark: dark);
    final canShowLeading =
        showLeading && !disableLeading && Navigator.of(context).canPop();

    final overlay = AppSystemBars.styleFor(background);
    final scrollsUnderHeader = !embedded && body == null;

    Widget listView = ListView(
      controller: scrollController,
      keyboardDismissBehavior: dismissKeyboardOnOutsideTap
          ? ScrollViewKeyboardDismissBehavior.onDrag
          : ScrollViewKeyboardDismissBehavior.manual,
      padding: EdgeInsets.fromLTRB(
        12,
        12 +
            (scrollsUnderHeader
                ? MediaQuery.paddingOf(context).top + kToolbarHeight
                : 0),
        12,
        24,
      ),
      children: children,
    );
    if (dismissKeyboardOnOutsideTap) {
      listView = TapRegion(
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        child: listView,
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: background,
        extendBody: true,
        extendBodyBehindAppBar: scrollsUnderHeader,
        appBar: embedded
            ? null
            : GlassAppBar(
                toolbarHeight: kToolbarHeight,
                elevation: 0,
                scrolledUnderElevation: 0,
                centerTitle: true,
                backgroundColor: background,
                surfaceTintColor: Colors.transparent,
                systemOverlayStyle: overlay,
                automaticallyImplyLeading: false,
                leading: canShowLeading
                    ? leading ??
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          color: leadingColor ?? AppTokens.accent,
                          onPressed: onLeadingPressed ??
                              () => Navigator.of(context).pop(),
                        )
                    : null,
                actions: actions,
                title: titleWidget ??
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: text,
                        fontSize:
                            SettingsResponsive.isDesktop(context) ? 16 : 17,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
              ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(child: body ?? listView),
              if (bottom != null) bottom!,
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.backgroundColor,
    this.borderRadius,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final Color? backgroundColor;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    return Container(
      margin: margin,
      child: Material(
        color: backgroundColor ?? AppTokens.surface(dark: dark),
        borderRadius: BorderRadius.circular(borderRadius ?? AppTokens.rLg),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }
}

class SettingsCell extends StatelessWidget {
  const SettingsCell({
    super.key,
    required this.title,
    this.titleWidget,
    this.subtitle,
    this.leading,
    this.value,
    this.icon,
    this.iconColor,
    this.showArrow = true,
    this.showDivider = true,
    this.onTap,
    this.trailing,
    this.titleStyle,
    this.valueStyle,
    this.enabled = true,
    this.indent = 0,
  });

  final String title;
  final Widget? titleWidget;
  final String? subtitle;
  final Widget? leading;
  final String? value;
  final IconData? icon;
  final Color? iconColor;
  final bool showArrow;
  final bool showDivider;
  final VoidCallback? onTap;
  final Widget? trailing;
  final TextStyle? titleStyle;
  final TextStyle? valueStyle;
  final bool enabled;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final text = AppTokens.textPrimary(dark: dark);
    final secondary = AppTokens.textSecondary(dark: dark);
    final line = AppTokens.border(dark: dark);
    final minHeight = SettingsResponsive.listRowMinHeight(context);
    final padding = SettingsResponsive.listRowPadding(context);
    final iconSize = SettingsResponsive.isDesktop(context) ? 20.0 : 22.0;
    final valueMaxWidth = (MediaQuery.sizeOf(context).width *
            (SettingsResponsive.isDesktop(context) ? 0.36 : 0.48))
        .clamp(120.0, SettingsResponsive.isDesktop(context) ? 360.0 : 220.0)
        .toDouble();

    final titleColor = text.withValues(alpha: enabled ? 1 : 0.45);
    final secondaryColor = secondary.withValues(alpha: enabled ? 1 : 0.45);

    final row = Container(
      constraints: BoxConstraints(
        minHeight:
            subtitle == null ? minHeight : math.max(minHeight, 64.0).toDouble(),
      ),
      padding: padding,
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: line, width: 0.7))
            : null,
      ),
      child: Row(
        crossAxisAlignment: subtitle == null
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          if (indent > 0) SizedBox(width: indent),
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 12),
          ],
          if (icon != null) ...[
            Icon(icon, color: iconColor ?? secondaryColor, size: iconSize),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: titleWidget ??
                (subtitle == null
                    ? Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle ??
                            TextStyle(
                              color: titleColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                            ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle ??
                                TextStyle(
                                  color: titleColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: secondaryColor,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      )),
          ),
          if (value != null) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: valueMaxWidth),
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: valueStyle ??
                    TextStyle(color: secondaryColor, fontSize: 14),
              ),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Opacity(opacity: enabled ? 1 : 0.45, child: trailing!),
          ],
          if (showArrow) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: secondary.withValues(alpha: enabled ? 1 : 0),
              size: 22,
            ),
          ],
        ],
      ),
    );

    if (!enabled || onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

class SettingsInputCell extends StatelessWidget {
  const SettingsInputCell({
    super.key,
    required this.label,
    required this.hint,
    this.obscureText = false,
    this.readOnly = false,
    this.keyboardType = TextInputType.text,
    this.controller,
    this.inputFormatters,
    this.leading,
    this.leadingWidth = 96,
    this.trailing,
    this.showDivider = true,
    this.enabled = true,
    this.contentPadding,
  });

  final String label;
  final String hint;
  final bool obscureText;
  final bool readOnly;
  final TextInputType keyboardType;
  final TextEditingController? controller;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? leading;
  final double leadingWidth;
  final Widget? trailing;
  final bool showDivider;
  final bool enabled;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final text = AppTokens.textPrimary(dark: dark);
    final secondary = AppTokens.textSecondary(dark: dark);
    final line = AppTokens.border(dark: dark);

    return Container(
      constraints: BoxConstraints(
        minHeight: SettingsResponsive.listRowMinHeight(context),
      ),
      padding: contentPadding ?? SettingsResponsive.listRowPadding(context),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: line, width: 0.7))
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: SettingsResponsive.labelWidth(context),
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: text, fontSize: 16),
            ),
          ),
          if (leading != null) SizedBox(width: leadingWidth, child: leading),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              readOnly: readOnly,
              enabled: enabled && !readOnly,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              cursorColor: AppTokens.accent,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                filled: false,
                isCollapsed: true,
                hintStyle: TextStyle(color: secondary, fontSize: 16),
              ),
              style: TextStyle(color: text, fontSize: 16),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Opacity(opacity: enabled ? 1 : 0.45, child: trailing!),
          ],
        ],
      ),
    );
  }
}

class SettingsPlatformSwitch extends StatelessWidget {
  const SettingsPlatformSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final isCupertino =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    if (isCupertino) {
      return CupertinoSwitch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: AppTokens.accent,
      );
    }
    return Switch(
      value: value,
      onChanged: onChanged,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      thumbColor: const WidgetStatePropertyAll<Color>(Colors.white),
      activeTrackColor: AppTokens.accent,
    );
  }
}

class SettingsSwitchCell extends StatelessWidget {
  const SettingsSwitchCell({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.showDivider = true,
    this.enabled = true,
    this.isSubItem = false,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool showDivider;
  final bool enabled;
  final bool isSubItem;

  @override
  Widget build(BuildContext context) => SettingsCell(
        title: isSubItem ? '- $title' : title,
        subtitle: subtitle,
        showArrow: false,
        showDivider: showDivider,
        enabled: enabled,
        indent: isSubItem ? 8 : 0,
        trailing: SettingsPlatformSwitch(
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
      );
}

class SettingsSectionText extends StatelessWidget {
  const SettingsSectionText(
    this.text, {
    super.key,
    this.top = 0,
    this.bottom = 10,
  });

  final String text;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, top, 16, bottom),
      child: Text(
        text,
        style: TextStyle(
          color: AppTokens.textSecondary(dark: dark),
          fontSize: 13,
          height: 1.45,
        ),
      ),
    );
  }
}

class SettingsPrimaryButton extends StatelessWidget {
  const SettingsPrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.loading = false,
    this.backgroundColor,
    this.foregroundColor,
    this.borderRadius,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 20),
  });

  final String text;
  final VoidCallback? onPressed;
  final bool loading;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: SizedBox(
          width: double.infinity,
          height: SettingsResponsive.controlHeight(context),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: backgroundColor ?? AppTokens.accent,
              foregroundColor: foregroundColor ?? AppTokens.onAccent,
              disabledBackgroundColor: AppTokens.border(
                dark: settingsIsDark(context),
              ),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(borderRadius ?? AppTokens.rMd),
              ),
            ),
            onPressed: loading ? null : onPressed,
            child: loading
                ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(
                        foregroundColor ?? AppTokens.onAccent,
                      ),
                    ),
                  )
                : Text(
                    text,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      );
}

class SettingsEmptyState extends StatelessWidget {
  const SettingsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description = '',
    this.actionLabel,
    this.onAction,
    this.imageWidth = 160,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double imageWidth;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final secondary = AppTokens.textSecondary(dark: dark);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/empty_99chat.webp',
              package: 'openim_common',
              width: imageWidth,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                icon,
                size: imageWidth * 0.45,
                color: secondary.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: secondary,
                fontSize: 15,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
            ),
            if (description.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(color: secondary, fontSize: 13, height: 1.45),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onAction,
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    color: AppTokens.accent,
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

/// Compatibility name for existing settings and application callers.
typedef SettingsAction<T> = AppAction<T>;

/// Kept as a thin adapter while callers migrate to the shared package API.
Future<T?> showSettingsActionSheet<T>(
  BuildContext context, {
  required String title,
  required List<SettingsAction<T>> actions,
}) =>
    showAppActionSheet<T>(context, title: title, actions: actions);

Future<bool> showSettingsConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmText,
  bool destructive = false,
}) async {
  final result = await showCupertinoDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(settingsText(context, zh: '取消', en: 'Cancel')),
        ),
        CupertinoDialogAction(
          isDestructiveAction: destructive,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}

String settingsErrorMessage(BuildContext context, Object error,
        {required String fallback}) =>
    securityErrorMessage(error,
        zh: Localizations.localeOf(context).languageCode == 'zh',
        fallback: fallback);

void showSettingsError(BuildContext context, Object error, String fallback) {
  showSettingsMessage(
      context, settingsErrorMessage(context, error, fallback: fallback));
}

void showSettingsMessage(BuildContext context, String message) {
  IMViews.showToast(message, duration: const Duration(seconds: 2));
}

Future<void> showUnavailableSettingsAction(
  BuildContext context, [
  String feature = '此功能',
]) async {
  showSettingsMessage(
    context,
    settingsText(
      context,
      zh: '$feature 暂未开放',
      en: '$feature is not available yet',
    ),
  );
}

@Deprecated('Use showUnavailableSettingsAction for user-facing UI.')
Future<void> showReservedSettingsAction(
  BuildContext context,
  String feature,
) =>
    showUnavailableSettingsAction(context, feature);

class SettingsDestructiveButton extends StatelessWidget {
  const SettingsDestructiveButton(
      {super.key,
      required this.text,
      required this.loadingText,
      required this.onPressed,
      this.loading = false,
      this.soft = false});
  final String text;
  final String loadingText;
  final VoidCallback? onPressed;
  final bool loading;
  final bool soft;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      height: SettingsResponsive.controlHeight(context),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                disabledForegroundColor:
                    AppTokens.textSecondary(dark: settingsIsDark(context)),
                textStyle: const TextStyle(
                    fontSize: AppTokens.listTitleFontSize,
                    fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTokens.rMd)))
            .copyWith(
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              loading || !states.contains(WidgetState.disabled)
                  ? Theme.of(context).colorScheme.error
                  : AppTokens.textSecondary(dark: settingsIsDark(context))),
          backgroundColor: WidgetStateProperty.resolveWith((states) => loading
              ? Theme.of(context)
                  .colorScheme
                  .error
                  .withValues(alpha: soft ? 0.1 : 0.04)
              : states.contains(WidgetState.disabled)
                  ? AppTokens.surfaceAlt(dark: settingsIsDark(context))
                  : states.contains(WidgetState.pressed)
                      ? Theme.of(context)
                          .colorScheme
                          .error
                          .withValues(alpha: 0.12)
                      : soft
                          ? Theme.of(context).colorScheme.error.withValues(
                              alpha: settingsIsDark(context) ? 0.18 : 0.08)
                          : AppTokens.surface(dark: settingsIsDark(context))),
          overlayColor: WidgetStatePropertyAll(
              Theme.of(context).colorScheme.error.withValues(alpha: 0.06)),
          side: WidgetStateProperty.resolveWith((states) => soft
              ? BorderSide.none
              : BorderSide(
                  color: loading || states.contains(WidgetState.pressed)
                      ? Theme.of(context)
                          .colorScheme
                          .error
                          .withValues(alpha: 0.3)
                      : AppTokens.border(dark: settingsIsDark(context)))),
        ),
        onPressed: loading ? null : onPressed,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (loading)
            SizedBox(
                width: AppTokens.chevronSize,
                height: AppTokens.chevronSize,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Theme.of(context).colorScheme.error))
          else
            const Icon(Icons.delete_outline_rounded,
                size: AppTokens.chevronSize),
          const SizedBox(width: AppTokens.s3),
          Flexible(child: Text(loading ? loadingText : text)),
        ]),
      ));
}
