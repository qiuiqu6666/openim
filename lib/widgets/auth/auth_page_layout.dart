import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'auth_copy.dart';
import 'auth_tokens.dart';
import 'auth_wave_background.dart';

/// A scrollable, keyboard-aware surface shared by all authentication steps.
class RegisterBgView extends StatelessWidget {
  const RegisterBgView({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.icon,
    this.step,
    this.totalSteps,
    this.showBack = true,
    this.footer,
    this.toolbar,
    this.centeredHeader = false,
    this.showWaves = false,
  });
  final Widget child;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final int? step;
  final int? totalSteps;
  final bool showBack;
  final Widget? footer;
  final Widget? toolbar;
  final bool centeredHeader;
  final bool showWaves;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = AuthTokens.background(context);
    return AppSystemBars(
      background: background,
      child: Scaffold(
        backgroundColor: background,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Stack(
            children: [
              if (showWaves) Positioned.fill(child: AuthWaveBackground()),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: showWaves
                      ? null
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.center,
                          colors: [
                            Color.alphaBlend(
                                colors.primary.withValues(alpha: .06),
                                background),
                            background,
                          ],
                        ),
                ),
                child: SafeArea(
                  child: LayoutBuilder(builder: (context, constraints) {
                    return SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.symmetric(
                          horizontal: AuthTokens.gutter,
                          vertical: AppTokens.s5),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: AuthTokens.maxWidth,
                            minHeight: math.max(
                                0, constraints.maxHeight - AppTokens.s8),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (toolbar != null) ...[
                                    Row(children: [
                                      if (showBack)
                                        IconButton(
                                          key: const ValueKey('auth-back'),
                                          tooltip: authText('返回', 'Back'),
                                          onPressed: () => Get.back(),
                                          constraints: const BoxConstraints(
                                              minWidth: AuthTokens.touchTarget,
                                              minHeight:
                                                  AuthTokens.touchTarget),
                                          icon: const Icon(
                                              Icons.arrow_back_rounded),
                                        ),
                                      Expanded(child: toolbar!),
                                    ]),
                                    const SizedBox(height: AppTokens.s7),
                                  ] else if (showBack || step != null) ...[
                                    Row(children: [
                                      if (showBack)
                                        IconButton(
                                          tooltip: authText('返回', 'Back'),
                                          onPressed: () => Get.back(),
                                          style: IconButton.styleFrom(
                                            backgroundColor:
                                                colors.surfaceContainerHighest,
                                            minimumSize: const Size.square(
                                                AuthTokens.touchTarget),
                                          ),
                                          icon: const Icon(
                                              Icons.arrow_back_rounded),
                                        ),
                                      const Spacer(),
                                      if (step != null && !centeredHeader)
                                        Text(
                                            authText('步骤 $step / $totalSteps',
                                                'Step $step of $totalSteps'),
                                            style: AuthTokens.body(context)),
                                    ]),
                                    const SizedBox(height: AppTokens.s7),
                                  ] else
                                    const SizedBox(height: AppTokens.s7),
                                  if (title != null) ...[
                                    Align(
                                      alignment: centeredHeader
                                          ? Alignment.center
                                          : AlignmentDirectional.centerStart,
                                      child: icon == null
                                          ? Transform.scale(
                                              // The brand asset includes clear padding.
                                              scale: centeredHeader ? 1.5 : 1,
                                              child: ImageRes.loginLogo.toImage
                                                ..width = centeredHeader
                                                    ? AuthTokens
                                                        .welcomeBrandSize
                                                    : AuthTokens.brandSize
                                                ..height = centeredHeader
                                                    ? AuthTokens
                                                        .welcomeBrandSize
                                                    : AuthTokens.brandSize,
                                            )
                                          : Container(
                                              width: AuthTokens.brandSize,
                                              height: AuthTokens.brandSize,
                                              decoration: BoxDecoration(
                                                color: colors.primary
                                                    .withValues(alpha: .1),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        AuthTokens.radius),
                                              ),
                                              child: ExcludeSemantics(
                                                  child: Icon(icon,
                                                      color: colors.primary,
                                                      size: AppTokens
                                                          .profileMenuIconSize)),
                                            ),
                                    ),
                                    SizedBox(
                                        height: centeredHeader
                                            ? AppTokens.s6
                                            : AppTokens.s7),
                                    Semantics(
                                        header: true,
                                        child: Text(title!,
                                            textAlign: centeredHeader
                                                ? TextAlign.center
                                                : TextAlign.start,
                                            style: AuthTokens.title(context))),
                                    if (subtitle != null) ...[
                                      const SizedBox(height: AppTokens.s3),
                                      Text(subtitle!,
                                          textAlign: centeredHeader
                                              ? TextAlign.center
                                              : TextAlign.start,
                                          style: AuthTokens.body(context)),
                                    ],
                                    if (centeredHeader && step != null) ...[
                                      const SizedBox(height: AppTokens.s4),
                                      Text(
                                        authText('步骤 $step / $totalSteps',
                                            'Step $step of $totalSteps'),
                                        key: const ValueKey('auth-step'),
                                        textAlign: TextAlign.center,
                                        style: AuthTokens.body(context)
                                            .copyWith(color: colors.primary),
                                      ),
                                    ],
                                    SizedBox(
                                        height: centeredHeader
                                            ? AuthTokens.welcomeHeaderGap
                                            : AuthTokens.sectionGap),
                                  ],
                                  child,
                                ],
                              ),
                              if (footer != null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      top: AuthTokens.sectionGap),
                                  child: footer,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
