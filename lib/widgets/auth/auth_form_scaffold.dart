import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_reference_tokens.dart';

/// 99chat's plain authentication form, used for secondary identity checks.
/// Its surfaces follow the application's current theme.
class AuthFormScaffold extends StatelessWidget {
  const AuthFormScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.showBack = true,
    this.onBack,
    this.backLabel,
    this.titleStyle,
  });

  final TextStyle? titleStyle;
  final String title;
  final String subtitle;
  final Widget child;
  final bool showBack;
  final VoidCallback? onBack;
  final String? backLabel;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final dark = AuthReferenceTokens.isDark(context);
    final surface =
        AuthReferenceTokens.color(context, AuthReferenceTokens.surface);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: surface,
        systemNavigationBarIconBrightness:
            dark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: surface,
        resizeToAvoidBottomInset: false,
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(
              bottom: keyboard > 0
                  ? keyboard + AuthReferenceTokens.keyboardScrollExtra
                  : bottom + AuthReferenceTokens.plainFormBottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AuthReferenceTokens.formHeaderHorizontal,
                    top + AuthReferenceTokens.formHeaderTop,
                    AuthReferenceTokens.formHeaderHorizontal,
                    AuthReferenceTokens.formHeaderBottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showBack) ...[
                        SizedBox(
                          width: AuthReferenceTokens.tapTarget,
                          height: AuthReferenceTokens.tapTarget,
                          child: IconButton(
                            key: const ValueKey('auth-form-back'),
                            tooltip: backLabel ?? 'Back',
                            onPressed:
                                onBack ?? () => Navigator.maybePop(context),
                            padding: EdgeInsets.zero,
                            alignment: Alignment.topLeft,
                            icon: Container(
                              width: AuthReferenceTokens.formBackSize,
                              height: AuthReferenceTokens.formBackSize,
                              decoration: BoxDecoration(
                                color: AuthReferenceTokens.color(
                                    context, AuthReferenceTokens.ink50),
                                borderRadius: BorderRadius.circular(
                                    AuthReferenceTokens.formBackRadius),
                              ),
                              child: Icon(
                                Icons.arrow_back_ios_new_rounded,
                                size: AuthReferenceTokens.formBackIcon,
                                color: AuthReferenceTokens.color(
                                    context, AuthReferenceTokens.brand500),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: AuthReferenceTokens.formHeaderBackGap -
                              (AuthReferenceTokens.tapTarget -
                                  AuthReferenceTokens.formBackSize),
                        ),
                      ],
                      Text(title,
                          style: AuthReferenceTokens.style(context,
                              titleStyle ?? AuthReferenceTokens.formTitle)),
                      const SizedBox(
                          height: AuthReferenceTokens.formHeaderSubtitleGap),
                      Text(subtitle,
                          style: AuthReferenceTokens.style(
                              context, AuthReferenceTokens.formSubtitle)),
                    ],
                  ),
                ),
                SizedBox(
                  height: 1,
                  child: ColoredBox(
                      color: AuthReferenceTokens.color(
                          context, AuthReferenceTokens.divider)),
                ),
                Padding(
                  padding: AuthReferenceTokens.plainFormPadding,
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
