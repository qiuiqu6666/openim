import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import 'moments_text.dart';
import 'moments_theme.dart';

class MomentsScaffold extends StatelessWidget {
  const MomentsScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.bottomNavigationBar,
    this.fullBleed = false,
    this.backgroundColor,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? bottomNavigationBar;
  final bool fullBleed;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final dark = momentsDark(context);
    final page = Scaffold(
      backgroundColor: backgroundColor ?? MomentsTheme.background(dark),
      appBar: fullBleed
          ? null
          : GlassAppBar(
              backgroundColor: MomentsTheme.card(dark),
              foregroundColor: MomentsTheme.text(dark),
              centerTitle: true,
              leading: IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                color: MomentsTheme.nav(dark),
              ),
              title: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: MomentsTheme.text(dark))),
              actions: actions,
            ),
      bottomNavigationBar: bottomNavigationBar == null
          ? null
          : Align(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: MomentsLayout.pageMaxWidth),
                child: SizedBox(
                    width: double.infinity, child: bottomNavigationBar),
              ),
            ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: MomentsLayout.pageMaxWidth),
            child: SizedBox(width: double.infinity, child: body),
          ),
        ),
      ),
    );
    return fullBleed
        ? AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light, child: page)
        : page;
  }
}
