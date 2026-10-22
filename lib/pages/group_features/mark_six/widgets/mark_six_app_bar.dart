import 'package:openim_common/localization.dart';
// Brand navigation geometry adapted from 99chat settings/test_page.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'package:flutter/material.dart';
import 'mark_six_style.dart';

AppBar markSixLotteryAppBar(BuildContext context,
    {String title = '京东微信红包', String? subtitle = '极速六合彩'}) {
  final style = MarkSixStyle.of(context);
  return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 60,
      leadingWidth: 64,
      titleSpacing: 0,
      centerTitle: true,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      backgroundColor: style.dark ? style.surface : const Color(0xFFF4F9FF),
      flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: style.dark
                      ? [style.surface, style.surface]
                      : const [Color(0xFFF7FAFF), Color(0xFFEAF3FF)]),
              border: Border(
                  bottom: BorderSide(
                      color: style.dark
                          ? style.divider
                          : const Color(0xFFE8F0FC))))),
      leading: Navigator.of(context).canPop()
          ? IconButton(
              tooltip: '返回',
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 24),
              color: const Color(0xFF1976F3),
              onPressed: () => Navigator.of(context).pop())
          : null,
      title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(AppCopy.text(title),
                style: TextStyle(
                    color: style.text,
                    fontSize: 18,
                    height: 1.12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .4)),
            if (subtitle != null) ...[
              const SizedBox(height: 1),
              Text(AppCopy.text(subtitle),
                  style: TextStyle(
                      color: style.dark
                          ? style.secondary
                          : const Color(0xFF74839B),
                      fontSize: 12,
                      height: 1.15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: .7)),
            ],
          ])));
}
