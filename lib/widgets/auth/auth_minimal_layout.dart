import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth_reference_tokens.dart';
import 'auth_copy.dart';

/// Shared reference layout; short screens and the keyboard scroll as one form.
class AuthMinimalLayout extends StatelessWidget {
  const AuthMinimalLayout(
      {super.key,
      required this.child,
      required this.footer,
      this.header,
      this.onBack});
  final Widget child;
  final Widget footer;
  final Widget? header;
  final VoidCallback? onBack;
  static bool of(BuildContext context) =>
      context.findAncestorWidgetOfExactType<AuthMinimalLayout>() != null;

  @override
  Widget build(BuildContext context) {
    final dark = AuthReferenceTokens.isDark(context);
    final surface =
        AuthReferenceTokens.color(context, AuthReferenceTokens.surface);
    // Keyboard resizing must not switch the form to the short-screen layout.
    // Measure before SafeArea removes padding; scroll only obscured fields.
    final media = MediaQuery.of(context);
    final compact = media.size.height - media.viewPadding.vertical < 600;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: surface),
      child: Scaffold(
        backgroundColor: surface,
        body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
          return GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Center(
                      child: ConstrainedBox(
                          constraints: BoxConstraints(
                              minHeight: constraints.maxHeight, maxWidth: 480),
                          child: IntrinsicHeight(
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal:
                                          AuthReferenceTokens.minimalInset),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(children: [
                                          if (onBack != null)
                                            TextButton.icon(
                                                onPressed: onBack,
                                                style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      AuthReferenceTokens.color(
                                                          context,
                                                          AuthReferenceTokens
                                                              .brand500),
                                                  minimumSize:
                                                      const Size(48, 48),
                                                  textStyle: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w400),
                                                ),
                                                icon: const Icon(
                                                    Icons.arrow_back_ios_new,
                                                    size: 20),
                                                label: Text.rich(TextSpan(
                                                  children: [
                                                    TextSpan(
                                                      text: authText('已有账户？',
                                                          'Already have an account? '),
                                                      style: TextStyle(
                                                        color: AuthReferenceTokens
                                                            .color(
                                                                context,
                                                                AuthReferenceTokens
                                                                    .ink400),
                                                      ),
                                                    ),
                                                    TextSpan(
                                                        text: authText(
                                                            '去登录', 'Log in')),
                                                  ],
                                                ))),
                                          const Spacer(),
                                          if (header != null) header!,
                                        ]),
                                        SizedBox(
                                            height: compact
                                                ? 12
                                                : AuthReferenceTokens
                                                    .minimalLogoTop),
                                        Center(
                                            child: ClipOval(
                                                child: Image.asset(
                                                    'assets/img/99chat_logo.png',
                                                    width: AuthReferenceTokens
                                                        .minimalLogoSize,
                                                    height: AuthReferenceTokens
                                                        .minimalLogoSize,
                                                    fit: BoxFit.cover,
                                                    semanticLabel: '99Chat'))),
                                        SizedBox(
                                            height: compact
                                                ? AuthReferenceTokens
                                                    .minimalLogoBottomCompact
                                                : AuthReferenceTokens
                                                    .minimalLogoBottom),
                                        child,
                                        const SizedBox(
                                            height:
                                                AuthReferenceTokens.buttonGap),
                                        const Spacer(),
                                        footer,
                                        const SizedBox(
                                            height:
                                                AuthReferenceTokens.buttonGap),
                                      ])))))));
        })),
      ),
    );
  }
}
