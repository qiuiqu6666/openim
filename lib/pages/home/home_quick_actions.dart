// Adapted from 99chat's home_quick_action_tile.dart and home_page.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache License 2.0).
// Changes: accept existing OpenIM actions and use the current app theme/tokens.
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Existing business actions supplied by the page that owns navigation.
class HomeQuickAction {
  const HomeQuickAction({
    required this.id,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.enabled = true,
  });

  final String id;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;
}

/// Reference-specific popup tokens; shared dimensions reuse [AppTokens].
class HomeQuickActionTokens {
  HomeQuickActionTokens._();

  static const Color menuDark = Color(0xFF202228);
  static const Color borderDark = Color(0xFF383A40);
  static const Color borderLight = Color(0xFFE9EAEE);
  static const Color dividerLight = Color(0xFFF0F1F4);
  static const Color iconSurfaceLight = Color(0xFFEAF4FF);
  static const Color iconSurfaceDark = Color(0xFF203B56);
  static const Color titleLight = Color(0xFF101522);
  static const Color subtitleLight = Color(0xFF7B8190);
  static const Color subtitleDark = Color(0xFFA7ABB6);
  static const Color icon = Color(0xFF0088FF);
  static const Color chevron = Color(0xFF828898);
  static const Color shadow = Color(0x260E2345);
  static const double minWidth = 200;
  static const double maxWidth = 224;
  static const double widthFraction = .56;
  static const double heightFraction = .65;
  static const double iconBoxSize = 30;
  static const double iconSize = 21;
  static const double iconRadius = 10;
  static const double iconGap = 9;
  static const double titleHeight = 1.2;
  static const double subtitleSize = 10;
  static const double subtitleHeight = 1.4;
  static const double subtitleGap = 3;
  static const double topPadding = 10;
  static const double anchorGap = 2;
  static const double arrowHeight = 8;
  static const double arrowHalfWidth = 6;
  static const double borderWidth = .8;
  static const double chevronWidth = 7;
  static const double elevation = 12;
}

/// Match the reference's logical-pixel sizing, including safe-area/keyboard.
BoxConstraints homeQuickMenuConstraints(MediaQueryData media) {
  final availableWidth =
      (media.size.width - media.padding.horizontal - AppTokens.s7)
          .clamp(0.0, double.infinity);
  final preferredWidth =
      (media.size.shortestSide * HomeQuickActionTokens.widthFraction).clamp(
    HomeQuickActionTokens.minWidth,
    HomeQuickActionTokens.maxWidth,
  );
  final width = preferredWidth.clamp(0.0, availableWidth);
  final height = (media.size.height -
          media.padding.vertical -
          media.viewInsets.bottom -
          AppTokens.s7)
      .clamp(0.0, double.infinity);
  return BoxConstraints(
    minWidth: width,
    maxWidth: width,
    maxHeight: height * HomeQuickActionTokens.heightFraction,
  );
}

/// Opens the 99chat quick menu directly below its plus button.
Future<void> showHomeQuickActions({
  required BuildContext context,
  required GlobalKey anchor,
  required List<HomeQuickAction> actions,
}) async {
  if (actions.isEmpty || !context.mounted) return;
  final button = anchor.currentContext?.findRenderObject();
  final overlay = Overlay.of(context).context.findRenderObject();
  if (button is! RenderBox || overlay is! RenderBox || !button.attached) {
    return;
  }
  final offset = button.localToGlobal(Offset.zero, ancestor: overlay);
  final media = MediaQuery.of(context);
  final constraints =
      homeQuickMenuConstraints(media.copyWith(size: overlay.size));
  final rightInset = media.padding.right + AppTokens.s3;
  final left = overlay.size.width - constraints.maxWidth - rightInset;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final selected = await showMenu<String>(
    context: context,
    color: dark ? HomeQuickActionTokens.menuDark : AppTokens.surfaceLight,
    elevation: HomeQuickActionTokens.elevation,
    shadowColor: HomeQuickActionTokens.shadow,
    surfaceTintColor: Colors.transparent,
    menuPadding: const EdgeInsets.only(
      top: HomeQuickActionTokens.topPadding,
      bottom: AppTokens.s2,
    ),
    constraints: constraints,
    shape: HomeQuickMenuShape(
      arrowX: offset.dx + button.size.width / 2 - left,
      borderColor: dark
          ? HomeQuickActionTokens.borderDark
          : HomeQuickActionTokens.borderLight,
    ),
    position: RelativeRect.fromLTRB(
      left,
      offset.dy + button.size.height + HomeQuickActionTokens.anchorGap,
      rightInset,
      0,
    ),
    items: [
      for (var index = 0; index < actions.length; index++)
        PopupMenuItem<String>(
          value: actions[index].id,
          enabled: actions[index].enabled && actions[index].onTap != null,
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
          child: HomeQuickActionTile(
            action: actions[index],
            divider: index < actions.length - 1,
          ),
        ),
    ],
  );
  if (!context.mounted || selected == null) return;
  for (final action in actions) {
    if (action.id == selected && action.enabled) {
      action.onTap?.call();
      return;
    }
  }
}

class HomeQuickActionTile extends StatelessWidget {
  const HomeQuickActionTile({
    required this.action,
    this.divider = true,
    super.key,
  });

  final HomeQuickAction action;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Opacity(
      opacity: action.enabled && action.onTap != null ? 1 : .45,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.s3),
        decoration: BoxDecoration(
          border: divider
              ? Border(
                  bottom: BorderSide(
                    color: dark
                        ? HomeQuickActionTokens.borderDark
                        : HomeQuickActionTokens.dividerLight,
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: HomeQuickActionTokens.iconBoxSize,
              height: HomeQuickActionTokens.iconBoxSize,
              decoration: BoxDecoration(
                color: dark
                    ? HomeQuickActionTokens.iconSurfaceDark
                    : HomeQuickActionTokens.iconSurfaceLight,
                borderRadius:
                    BorderRadius.circular(HomeQuickActionTokens.iconRadius),
              ),
              child: Center(
                child: SizedBox.square(
                  dimension: HomeQuickActionTokens.iconSize,
                  child: CustomPaint(painter: _QuickActionPainter(action.id)),
                ),
              ),
            ),
            const SizedBox(width: HomeQuickActionTokens.iconGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action.title,
                    style: TextStyle(
                      color: dark
                          ? AppTokens.onAccent
                          : HomeQuickActionTokens.titleLight,
                      fontSize: AppTokens.captionFontSize,
                      height: HomeQuickActionTokens.titleHeight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: HomeQuickActionTokens.subtitleGap),
                  Text(
                    action.subtitle,
                    style: TextStyle(
                      color: dark
                          ? HomeQuickActionTokens.subtitleDark
                          : HomeQuickActionTokens.subtitleLight,
                      fontSize: HomeQuickActionTokens.subtitleSize,
                      height: HomeQuickActionTokens.subtitleHeight,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTokens.s3),
            const SizedBox(
              width: HomeQuickActionTokens.chevronWidth,
              height: AppTokens.s4,
              child: CustomPaint(painter: _QuickChevronPainter()),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionPainter extends CustomPainter {
  const _QuickActionPainter(this.id);
  final String id;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 36, size.height / 36);
    final fill = Paint()..color = HomeQuickActionTokens.icon;
    final line = Paint()
      ..color = fill.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (id == 'addFriend' || id == 'searchAdd') {
      canvas.drawCircle(const Offset(13, 10), 6, fill);
      canvas.drawPath(
        Path()
          ..moveTo(2, 29)
          ..cubicTo(2, 22, 8, 18, 16, 19)
          ..cubicTo(13, 23, 13, 27, 15, 30)
          ..lineTo(4, 30)
          ..quadraticBezierTo(2, 30, 2, 29),
        fill,
      );
      canvas.drawCircle(const Offset(23, 25), 5.5, line);
      canvas.drawLine(const Offset(27, 29), const Offset(32, 34), line);
    } else if (id == 'createGroup' || id == 'addGroup') {
      canvas.drawCircle(const Offset(12, 11), 5.6, fill);
      canvas.drawCircle(const Offset(25, 13), 4.8, fill);
      canvas.drawPath(
        Path()
          ..moveTo(1.2, 29)
          ..cubicTo(1.2, 17, 23, 17, 23, 29)
          ..quadraticBezierTo(23, 31, 21, 31)
          ..lineTo(3.2, 31)
          ..quadraticBezierTo(1.2, 31, 1.2, 29),
        fill,
      );
      canvas.drawPath(
        Path()
          ..moveTo(23, 21)
          ..cubicTo(30, 19.5, 34, 24, 34, 29)
          ..quadraticBezierTo(34, 30, 32, 30)
          ..lineTo(25, 30)
          ..cubicTo(26, 27, 25, 24, 23, 21),
        fill,
      );
    } else if (id == 'createChannel') {
      canvas.drawPath(
        Path()
          ..moveTo(5, 14)
          ..lineTo(12, 14)
          ..lineTo(29, 6)
          ..lineTo(29, 30)
          ..lineTo(12, 22)
          ..lineTo(5, 22)
          ..close(),
        line,
      );
      canvas.drawLine(const Offset(12, 14), const Offset(12, 22), line);
      canvas.drawLine(const Offset(12, 24), const Offset(15, 32), line);
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(4, 11)
          ..lineTo(4, 7)
          ..quadraticBezierTo(4, 4, 7, 4)
          ..lineTo(11, 4)
          ..moveTo(25, 4)
          ..lineTo(29, 4)
          ..quadraticBezierTo(32, 4, 32, 7)
          ..lineTo(32, 11)
          ..moveTo(32, 25)
          ..lineTo(32, 29)
          ..quadraticBezierTo(32, 32, 29, 32)
          ..lineTo(25, 32)
          ..moveTo(11, 32)
          ..lineTo(7, 32)
          ..quadraticBezierTo(4, 32, 4, 29)
          ..lineTo(4, 25)
          ..moveTo(7.5, 18)
          ..lineTo(28.5, 18),
        line,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_QuickActionPainter oldDelegate) => oldDelegate.id != id;
}

class _QuickChevronPainter extends CustomPainter {
  const _QuickChevronPainter();

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
        Path()
          ..moveTo(1, 1)
          ..lineTo(size.width - 1, size.height / 2)
          ..lineTo(1, size.height - 1),
        Paint()
          ..color = HomeQuickActionTokens.chevron
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

  @override
  bool shouldRepaint(_QuickChevronPainter oldDelegate) => false;
}

class HomeQuickMenuShape extends ShapeBorder {
  const HomeQuickMenuShape({required this.arrowX, required this.borderColor});

  final double arrowX;
  final Color borderColor;

  @override
  EdgeInsetsGeometry get dimensions =>
      const EdgeInsets.only(top: HomeQuickActionTokens.arrowHeight);

  @override
  ShapeBorder scale(double t) => this;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final edge = (rect.width / 2).clamp(0.0, AppTokens.s3);
    final x = arrowX.clamp(edge, rect.width - edge) + rect.left;
    final card = Rect.fromLTRB(
      rect.left,
      rect.top + HomeQuickActionTokens.arrowHeight,
      rect.right,
      rect.bottom,
    );
    return Path.combine(
      PathOperation.union,
      Path()
        ..addRRect(RRect.fromRectAndRadius(
            card, const Radius.circular(AppTokens.rMd))),
      Path()
        ..moveTo(x - HomeQuickActionTokens.arrowHalfWidth, card.top + 1)
        ..lineTo(x, rect.top)
        ..lineTo(x + HomeQuickActionTokens.arrowHalfWidth, card.top + 1)
        ..close(),
    );
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) =>
      canvas.drawPath(
        getOuterPath(rect),
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = HomeQuickActionTokens.borderWidth,
      );
}
