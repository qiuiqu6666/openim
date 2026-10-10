import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../widgets/settings_widgets.dart';
import 'platform_update_tokens.dart';

final _visibleUpdates = Expando<Future<void>>();

Future<void> showPlatformUpdateDialog(
  BuildContext context, {
  required String title,
  required String message,
  required bool force,
  required Future<void> Function() onUpdate,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final active = _visibleUpdates[navigator];
  if (active != null) return active;
  late final Future<void> work;
  work = showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: PlatformUpdateTokens.barrier,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : PlatformUpdateTokens.transition,
    pageBuilder: (_, __, ___) => PopScope(
      canPop: false,
      child: _PlatformUpdateDialog(
          title: title, message: message, force: force, onUpdate: onUpdate),
    ),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
          scale: Tween<double>(begin: .96, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child),
    ),
  ).whenComplete(() {
    if (identical(_visibleUpdates[navigator], work)) {
      _visibleUpdates[navigator] = null;
    }
  });
  _visibleUpdates[navigator] = work;
  return work;
}

class _PlatformUpdateDialog extends StatefulWidget {
  const _PlatformUpdateDialog(
      {required this.title,
      required this.message,
      required this.force,
      required this.onUpdate});
  final String title, message;
  final bool force;
  final Future<void> Function() onUpdate;
  @override
  State<_PlatformUpdateDialog> createState() => _PlatformUpdateDialogState();
}

class _PlatformUpdateDialogState extends State<_PlatformUpdateDialog> {
  bool _updating = false, _failed = false;

  void _close() {
    final route = ModalRoute.of(context);
    if (route != null) Navigator.of(context).removeRoute(route);
  }

  Future<void> _update() async {
    if (_updating) return;
    setState(() {
      _updating = true;
      _failed = false;
    });
    try {
      await widget.onUpdate();
      if (!mounted) return;
      if (!widget.force) _close();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final size = MediaQuery.sizeOf(context);
    final width = math.min(
        size.width - AppTokens.s7,
        (math.min(size.width, 480) * PlatformUpdateTokens.widthFraction).clamp(
            PlatformUpdateTokens.minWidth, PlatformUpdateTokens.maxWidth));
    final text = AppTokens.textPrimary(dark: dark);
    final sub = AppTokens.textSecondary(dark: dark);
    return SafeArea(
        child: Center(
            child: Padding(
      padding: const EdgeInsets.all(AppTokens.s4),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: width,
            maxHeight: size.height * PlatformUpdateTokens.maxHeightFraction),
        child: Material(
            color: Colors.transparent,
            child: Stack(children: [
              Container(
                decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(PlatformUpdateTokens.radius),
                    boxShadow: [
                      BoxShadow(
                          color: PlatformUpdateTokens.shadow
                              .withValues(alpha: dark ? .45 : .18),
                          blurRadius: AppTokens.s7,
                          spreadRadius: 2,
                          offset: const Offset(0, AppTokens.s3))
                    ]),
                child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(PlatformUpdateTokens.radius),
                    child: Stack(children: [
                      Positioned.fill(
                          child: Image.asset(PlatformUpdateTokens.artwork,
                              excludeFromSemantics: true,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              color:
                                  dark ? PlatformUpdateTokens.darkTint : null,
                              colorBlendMode: dark ? BlendMode.modulate : null,
                              errorBuilder: (_, __, ___) => ColoredBox(
                                  color: AppTokens.surface(dark: dark)))),
                      if (dark)
                        const Positioned.fill(
                            child: IgnorePointer(
                                child: DecoratedBox(
                                    decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: PlatformUpdateTokens
                                                .darkGradient,
                                            stops: [.16, .4, 1]))))),
                      Padding(
                          padding: EdgeInsets.fromLTRB(
                              width * .1, width * .32, width * .1, width * .06),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Flexible(
                                child: SingleChildScrollView(
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                  Semantics(
                                      namesRoute: true,
                                      child: Text(widget.title,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: text,
                                              fontSize: PlatformUpdateTokens
                                                  .titleSize,
                                              fontWeight: FontWeight.w800,
                                              height: 1.25))),
                                  const SizedBox(height: AppTokens.s4),
                                  Text(widget.message,
                                      style: TextStyle(
                                          color: sub,
                                          fontSize:
                                              PlatformUpdateTokens.bodySize,
                                          height: 1.45)),
                                  if (_failed) ...[
                                    const SizedBox(height: AppTokens.s4),
                                    Semantics(
                                        liveRegion: true,
                                        child: Text(
                                            settingsText(context,
                                                zh: '无法打开下载页面，请稍后重试',
                                                en:
                                                    'Unable to open the download page. Please retry.'),
                                            style: TextStyle(
                                                color: settingsDanger(dark),
                                                fontSize: PlatformUpdateTokens
                                                    .bodySize,
                                                height: 1.45))),
                                  ],
                                ]))),
                            const SizedBox(height: AppTokens.s5),
                            SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _updating ? null : _update,
                                  style: FilledButton.styleFrom(
                                      backgroundColor: AppTokens.accent,
                                      foregroundColor: AppTokens.onAccent,
                                      minimumSize: Size(
                                          0,
                                          SettingsResponsive.controlHeight(
                                              context)),
                                      shape: const StadiumBorder(),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: AppTokens.s5,
                                          vertical: AppTokens.s4)),
                                  child: _updating
                                      ? const SizedBox.square(
                                          dimension: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppTokens.onAccent))
                                      : Text(
                                          settingsText(context,
                                              zh: '立即更新', en: 'Update Now'),
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600)),
                                )),
                          ])),
                    ])),
              ),
              if (!widget.force)
                Positioned(
                    top: AppTokens.s2,
                    right: AppTokens.s2,
                    child: SizedBox.square(
                        dimension: PlatformUpdateTokens.closeSize,
                        child: IconButton.filled(
                          tooltip: settingsText(context, zh: '关闭', en: 'Close'),
                          onPressed: _updating ? null : _close,
                          style: IconButton.styleFrom(
                              backgroundColor: AppTokens.surface(dark: dark),
                              foregroundColor: text),
                          icon: const Icon(Icons.close_rounded,
                              size: PlatformUpdateTokens.closeIconSize),
                        ))),
            ])),
      ),
    )));
  }
}
