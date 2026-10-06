import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth_copy.dart';
import 'auth_reference_tokens.dart';

/// 99chat's auth frame: blue hero, top tabs and a rounded white form surface.
class AuthEntryScaffold extends StatelessWidget {
  const AuthEntryScaffold(
      {super.key,
      required this.greeting,
      required this.accent,
      required this.child,
      this.footer,
      this.contentPadding = AuthReferenceTokens.formPadding,
      this.tabs,
      this.activeTab,
      this.onTabSelected,
      this.onBack,
      this.headerAction});
  final String greeting;
  final String accent;
  final Widget child;
  final Widget? footer;
  final EdgeInsetsGeometry contentPadding;
  final List<String>? tabs;
  final int? activeTab;
  final ValueChanged<int>? onTabSelected;
  final VoidCallback? onBack;
  final Widget? headerAction;

  @override
  Widget build(BuildContext context) {
    final current = Theme.of(context);
    final light = ThemeData(
        brightness: Brightness.light,
        fontFamily: current.textTheme.bodyMedium?.fontFamily,
        colorScheme: ColorScheme.fromSeed(
            seedColor: AuthReferenceTokens.brand500,
            brightness: Brightness.light),
        scaffoldBackgroundColor: Colors.white,
        textSelectionTheme: const TextSelectionThemeData(
            cursorColor: AuthReferenceTokens.brand500,
            selectionColor: Color(0x381E90FF),
            selectionHandleColor: AuthReferenceTokens.brand500));
    return Theme(
        data: light,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
              systemNavigationBarColor: Colors.white,
              systemNavigationBarIconBrightness: Brightness.dark),
          child: Scaffold(
            backgroundColor: AuthReferenceTokens.brand500,
            resizeToAvoidBottomInset: false,
            body: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: LayoutBuilder(
                    builder: (context, constraints) =>
                        constraints.maxWidth >= 900
                            ? _wide(context, constraints)
                            : _mobile(context, constraints))),
          ),
        ));
  }

  Widget _form(BuildContext context) => SingleChildScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom + 24),
        child: child,
      );

  Widget _panel(BuildContext context) => Padding(
      padding: contentPadding,
      child: Column(children: [
        Expanded(child: _form(context)),
        if (footer != null) ...[const SizedBox(height: 18), footer!]
      ]));

  Widget _mobile(BuildContext context, BoxConstraints constraints) {
    final compact = constraints.maxHeight < 560;
    final top = MediaQuery.paddingOf(context).top;
    return Column(children: [
      Stack(children: [
        Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(28, top + 18, 28,
                compact ? 16 : AuthReferenceTokens.heroBottomGap),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (onBack != null) ...[
                _back(),
                SizedBox(height: compact ? 4 : 26)
              ],
              SizedBox(
                  height: compact
                      ? 8
                      : onBack != null
                          ? 12
                          : AuthReferenceTokens.heroTopGap),
              Text(greeting, style: AuthReferenceTokens.hero),
              Text(accent, style: AuthReferenceTokens.hero),
              if (tabs != null && tabs!.isNotEmpty) ...[
                SizedBox(height: compact ? 12 : AuthReferenceTokens.heroTabGap),
                _tabs()
              ],
            ])),
        if (headerAction != null)
          Positioned(top: top + 12, right: 18, child: headerAction!),
      ]),
      Expanded(
          child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(34))),
              child: SafeArea(top: false, child: _panel(context)))),
    ]);
  }

  Widget _wide(BuildContext context, BoxConstraints constraints) => Container(
      color: const Color(0xFFF4F7FB),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: 1120,
            maxHeight: (constraints.maxHeight - 72).clamp(0, 760)),
        child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x140B1220),
                      blurRadius: 28,
                      offset: Offset(0, 12))
                ]),
            child: Row(children: [
              Expanded(
                  flex: 5,
                  child: Container(
                      color: AuthReferenceTokens.brand500,
                      padding: const EdgeInsets.fromLTRB(48, 44, 48, 42),
                      child: Stack(children: [
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (onBack != null) ...[
                                _back(),
                                const SizedBox(height: 44)
                              ] else
                                const SizedBox(height: 28),
                              Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: .18),
                                      borderRadius: BorderRadius.circular(20)),
                                  child: const Icon(Icons.chat_bubble_rounded,
                                      color: Colors.white, size: 34)),
                              const SizedBox(height: 34),
                              Text(greeting,
                                  style: AuthReferenceTokens.hero
                                      .copyWith(fontSize: 34)),
                              const SizedBox(height: 8),
                              Text(accent,
                                  style: AuthReferenceTokens.hero
                                      .copyWith(fontSize: 34)),
                              const SizedBox(height: 22),
                              Text(
                                  authText('多端同步 · 单聊群聊 · 安全通讯',
                                      'Multi-device sync · 1:1 & groups · Secure chat'),
                                  style: TextStyle(
                                      fontSize: 15,
                                      color:
                                          Colors.white.withValues(alpha: .86))),
                              const Spacer(),
                              Wrap(spacing: 10, runSpacing: 10, children: [
                                for (final text in [
                                  authText('多端同步', 'Multi-device sync'),
                                  authText('群组聊天', 'Group chat'),
                                  authText('音视频通话', 'Voice & video')
                                ])
                                  Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 9),
                                      decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: .16),
                                          borderRadius:
                                              BorderRadius.circular(999)),
                                      child: Text(text,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white))),
                              ]),
                            ]),
                        if (headerAction != null)
                          Positioned(top: 0, right: 0, child: headerAction!)
                      ]))),
              Expanded(
                  flex: 6,
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(56, 44, 56, 30),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (tabs != null && tabs!.isNotEmpty)
                              _tabs(wide: true),
                            const SizedBox(height: 30),
                            Expanded(child: _panel(context)),
                          ]))),
            ])),
      ));

  Widget _back() => SizedBox(
      width: AuthReferenceTokens.tapTarget,
      height: AuthReferenceTokens.tapTarget,
      child: IconButton(
          key: const ValueKey('auth-back'),
          tooltip: authText('返回', 'Back'),
          onPressed: onBack,
          style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: .08),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: EdgeInsets.zero),
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 16)));

  Widget _tabs({bool wide = false}) => Wrap(
      spacing: wide ? 30 : 36,
      children: List.generate(tabs!.length, (index) {
        final active = index == (activeTab ?? 0);
        return Semantics(
            selected: active,
            button: true,
            child: InkWell(
                key: ValueKey('auth-tab-$index'),
                onTap:
                    onTabSelected == null ? null : () => onTabSelected!(index),
                child: Container(
                    padding: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                        border: active
                            ? Border(
                                bottom: BorderSide(
                                    width: AuthReferenceTokens.tabUnderline,
                                    color: wide
                                        ? AuthReferenceTokens.brand500
                                        : Colors.white))
                            : null),
                    child: Text(tabs![index],
                        style: TextStyle(
                            fontSize: wide ? 22 : AuthReferenceTokens.tabSize,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w600,
                            color: wide
                                ? active
                                    ? AuthReferenceTokens.ink900
                                    : AuthReferenceTokens.ink400
                                : active
                                    ? Colors.white
                                    : const Color(0xCCFFFFFF))))));
      }));
}
