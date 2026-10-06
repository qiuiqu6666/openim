import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_reference_tokens.dart';

/// 99chat's plain authentication form, used for secondary identity checks.
/// Its authentication palette stays light in both application themes.
class AuthFormScaffold extends StatelessWidget {
  const AuthFormScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.showBack = true,
    this.onBack,
    this.backLabel,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool showBack;
  final VoidCallback? onBack;
  final String? backLabel;

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final light = ThemeData(
      brightness: Brightness.light,
      fontFamily: fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AuthReferenceTokens.brand500,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AuthReferenceTokens.surface,
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AuthReferenceTokens.brand500,
        selectionColor: Color(0x381E90FF),
        selectionHandleColor: AuthReferenceTokens.brand500,
      ),
    );
    return Theme(
      data: light,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: AuthReferenceTokens.surface,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: AuthReferenceTokens.surface,
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
                                  color: AuthReferenceTokens.ink50,
                                  borderRadius: BorderRadius.circular(
                                      AuthReferenceTokens.formBackRadius),
                                ),
                                child: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  size: AuthReferenceTokens.formBackIcon,
                                  color: AuthReferenceTokens.brand500,
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
                        Text(title, style: AuthReferenceTokens.formTitle),
                        const SizedBox(
                            height: AuthReferenceTokens.formHeaderSubtitleGap),
                        Text(subtitle, style: AuthReferenceTokens.formSubtitle),
                      ],
                    ),
                  ),
                  const SizedBox(
                    height: 1,
                    child: ColoredBox(color: AuthReferenceTokens.divider),
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
      ),
    );
  }
}
