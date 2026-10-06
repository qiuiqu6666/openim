import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../models/live_errors.dart';

/// Geometry and art from 99chat group_live_*; semantic colors stay shared.
abstract final class LiveStyle {
  static const aspect = 16 / 9;
  static const bannerHeight = 56.0;
  static const controlExtent = 48.0;
  static const controlIconSize = 20.0;
  static const waitingIndicatorSize = 36.0;
  static const waitingProgressSize = 24.0;
  static const cardRadius = 20.0;
  static const fieldRadius = 12.0;
  static const submitHeight = 52.0;
  static const blue = Color(0xFF2D8CFF);
  static const red = Color(0xFFFC4F53);
  static const waiting = Color(0xFFFF6B35);
  static const screen = Color(0xFF000000);
  static const screenInk = AppTokens.onAccent;
  static const backgroundAsset = 'assets/img/group_live_background.webp';
  static const createAsset = 'assets/img/group_live_create.webp';
  static const bannerAsset = 'assets/img/group_live_banner.webp';
  static const heroAsset = 'assets/img/group_live_hero.webp';
  static const onlineAsset = 'assets/img/group_live_online.webp';
  static const guideAsset = 'assets/img/group_live_guide.webp';
  static const guideImageAspect = 1201 / 1310;
  static const guideHeightFactor = .85;
  static const guideDesktopHeightFactor = .82;
  static const guideDesktopWidth = 420.0;
  static const guideRadius = 16.0;
  static const guideHandleWidth = 36.0;
  static const guideHandleHeight = 4.0;
  static const guideButtonHeight = 48.0;
  static const guideButtonRadius = 24.0;
  static Color guideHandle(BuildContext context) =>
      dark(context) ? const Color(0xFF4B5563) : const Color(0xFF9CA3AF);
  static bool dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
  static Color card(BuildContext context) =>
      AppTokens.surface(dark: dark(context));
  static Color field(BuildContext context) => dark(context)
      ? AppTokens.surfaceAlt(dark: true)
      : const Color(0xFFF1F2F4);
  static Color text(BuildContext context) =>
      AppTokens.textPrimary(dark: dark(context));
  static Color secondary(BuildContext context) =>
      AppTokens.textSecondary(dark: dark(context));
}

class LiveSetupShell extends StatelessWidget {
  const LiveSetupShell(
      {super.key,
      required this.body,
      this.bottom,
      this.actions = const [],
      this.title = '',
      this.bodyPadding = const EdgeInsets.fromLTRB(16, 0, 16, 24),
      this.create = false});
  final Widget body;
  final Widget? bottom;
  final List<Widget> actions;
  final String title;
  final EdgeInsetsGeometry bodyPadding;
  final bool create;
  @override
  Widget build(BuildContext context) => DecoratedBox(
      decoration: BoxDecoration(
          color: AppTokens.background(dark: LiveStyle.dark(context)),
          image: LiveStyle.dark(context)
              ? null
              : const DecorationImage(
                  image: AssetImage(LiveStyle.backgroundAsset),
                  fit: BoxFit.cover)),
      child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
              leading: const LiveBackButton(),
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              foregroundColor: LiveStyle.blue,
              title: Text(title),
              actions: actions),
          body: Column(children: [
            Expanded(
                child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: bodyPadding,
                    child: body)),
            if (bottom != null)
              SafeArea(
                  top: false,
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: bottom!))
          ])));
}

class LiveBackButton extends StatelessWidget {
  const LiveBackButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      icon:
          const Icon(Icons.arrow_back_ios_new_rounded, color: AppTokens.accent),
      onPressed: () => Navigator.of(context).maybePop());
}

class LivePrimaryButton extends StatelessWidget {
  const LivePrimaryButton(
      {super.key,
      required this.label,
      this.onPressed,
      this.busy = false,
      this.height = LiveStyle.submitHeight,
      this.radius = 14});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final double height;
  final double radius;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      height: height,
      child: FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: LiveStyle.blue,
              foregroundColor: AppTokens.onAccent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radius))),
          onPressed: busy ? null : onPressed,
          child: busy
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTokens.onAccent))
              : Text(label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600))));
}

class LiveError extends StatelessWidget {
  const LiveError({super.key, required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(liveErrorMessage(error),
            textAlign: TextAlign.center,
            style: TextStyle(color: LiveStyle.secondary(context))),
        const SizedBox(height: 12),
        TextButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'))
      ]));
}
