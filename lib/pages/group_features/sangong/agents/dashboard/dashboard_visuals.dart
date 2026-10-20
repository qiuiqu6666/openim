import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Visual tokens for the reference team dashboard, resolved for both themes.
class DashboardVisuals {
  DashboardVisuals(BuildContext context) : theme = Theme.of(context);
  final ThemeData theme;
  static const inset = 12.0, gap = 10.0, smallGap = 6.0;
  static const sectionGap = 16.0, radius = 18.0, avatar = 48.0;
  static const metricInset = 8.0, metricGap = 8.0, metricIcon = 20.0;
  static const metricVerticalInset = 16.0;
  static const metricIconInset = 7.0, metricTextGap = 5.0;
  static const badgeInset = 3.0, badgeRadius = 8.0;
  bool get dark => theme.brightness == Brightness.dark;
  Color get surface => theme.colorScheme.surface;
  Color get background => AppTokens.background(dark: dark);
  Color get secondary => theme.colorScheme.onSurfaceVariant;
  Color get soft =>
      Color.alphaBlend(blue.withValues(alpha: dark ? .07 : .035), surface);
  Color get line => theme.colorScheme.outlineVariant.withValues(alpha: .32);
  Color get blue => AppTokens.accent;
  Color get green => dark ? const Color(0xff63dcb0) : const Color(0xff00b384);
  Color get purple => dark ? const Color(0xffb39dff) : const Color(0xff794bff);
  Color get orange => dark ? const Color(0xffffbd69) : const Color(0xffff8a00);
  Color get pink => dark ? const Color(0xffff8db9) : const Color(0xffff4089);
  Color get red => dark ? const Color(0xffff909c) : const Color(0xffff5068);
  TextStyle get title =>
      theme.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800);
  TextStyle get heading => theme.textTheme.titleLarge!
      .copyWith(fontWeight: FontWeight.w700, fontSize: 19);
  TextStyle get label => theme.textTheme.bodyMedium!.copyWith(color: secondary);
  TextStyle get detail => theme.textTheme.bodySmall!.copyWith(color: secondary);
  TextStyle get metricLabel => label.copyWith(fontSize: 13);
  TextStyle get memberName =>
      theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700);
  TextStyle value(bool hero) => theme.textTheme.titleLarge!
      .copyWith(fontWeight: FontWeight.w800, fontSize: hero ? 22 : 19);
  BoxDecoration panel({bool top = false, bool bottom = false}) => BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(top ? radius : 0),
            bottom: Radius.circular(bottom ? radius : 0)),
      );
}

class DashboardMetric extends StatelessWidget {
  const DashboardMetric(
      {super.key,
      required this.label,
      required this.value,
      required this.icon,
      required this.color,
      this.hero = false});
  final String label, value;
  final IconData icon;
  final Color color;
  final bool hero;
  @override
  Widget build(BuildContext context) {
    final t = DashboardVisuals(context);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 22;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: DashboardVisuals.metricInset,
          vertical: DashboardVisuals.metricVerticalInset),
      child: Row(children: [
        ExcludeSemantics(
            child: Container(
          padding: const EdgeInsets.all(DashboardVisuals.metricIconInset),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(DashboardVisuals.badgeRadius),
          ),
          child: Icon(icon, size: DashboardVisuals.metricIcon, color: color),
        )),
        const SizedBox(width: DashboardVisuals.metricGap),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: t.metricLabel),
          const SizedBox(height: DashboardVisuals.metricTextGap),
          if (largeText)
            Text(value, style: t.value(hero))
          else
            FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(value, style: t.value(hero))),
        ])),
      ]),
    );
  }
}
