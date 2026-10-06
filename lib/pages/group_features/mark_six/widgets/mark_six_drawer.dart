// Preview geometry adapted from 99chat lottery_drawer.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'package:flutter/material.dart';
import '../data/mark_six_controller.dart';
import '../pages/mark_six_page.dart';
import 'mark_six_latest_card.dart';
import 'mark_six_style.dart';

Future<void> showMarkSixDrawer(
    BuildContext context, MarkSixController controller,
    {double? anchorY, ValueChanged<VoidCallback?>? onDismissChanged}) async {
  if (!controller.current) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  final cardKey = GlobalKey();
  Rect? origin;
  var opening = false;
  final expanded = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭开奖预览',
      barrierColor: Colors.black12,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) {
        final route = ModalRoute.of(context)!;
        onDismissChanged?.call(() {
          if (route.isActive) navigator.removeRoute(route);
        });
        return SafeArea(
            right: false,
            child: CustomSingleChildLayout(
                delegate: _LotteryPreviewPosition(
                    anchorY == null
                        ? null
                        : anchorY - MediaQuery.paddingOf(context).top,
                    MediaQuery.devicePixelRatioOf(context)),
                child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: SizedBox(
                        key: const ValueKey('lottery-latest-preview'),
                        width: (MediaQuery.sizeOf(context).width * .88)
                            .clamp(0.0, 520.0),
                        child: Material(
                            color: Colors.transparent,
                            child: Semantics(
                                key: cardKey,
                                button: true,
                                label: '全屏查看开奖记录',
                                child: InkWell(
                                    key: const ValueKey('lottery-preview-open'),
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () {
                                      if (opening || !controller.current) {
                                        return;
                                      }
                                      final box = cardKey.currentContext
                                          ?.findRenderObject() as RenderBox?;
                                      if (box == null) return;
                                      opening = true;
                                      origin = box.localToGlobal(Offset.zero) &
                                          box.size;
                                      Navigator.of(context).pop(true);
                                    },
                                    child: _LatestPreviewShell(
                                        controller: controller))))))));
      },
      transitionBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(CurvedAnimation(
                  parent: animation, curve: Curves.easeOutCubic)),
          child: child));
  onDismissChanged?.call(null);
  if (!context.mounted ||
      expanded != true ||
      !controller.current ||
      origin == null) {
    return;
  }
  await navigator.push<void>(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, __) {
        final route = ModalRoute.of(context)!;
        onDismissChanged?.call(() {
          if (route.isActive) navigator.removeRoute(route);
        });
        return MarkSixPage(
            featureContext: controller.repository.context,
            controller: controller);
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final size = MediaQuery.sizeOf(context);
        final t = Curves.easeInOutCubic.transform(animation.value);
        final rect = Rect.lerp(origin, Offset.zero & size, t)!;
        return Stack(children: [
          Positioned.fromRect(
              rect: rect,
              child: ClipRRect(
                  key: const ValueKey('lottery-card-expansion'),
                  borderRadius: BorderRadius.circular(16 * (1 - t)),
                  child: Material(
                      color: MarkSixStyle.of(context).surface,
                      child: Stack(children: [
                        OverflowBox(
                            alignment: Alignment.topLeft,
                            minWidth: size.width,
                            maxWidth: size.width,
                            minHeight: size.height,
                            maxHeight: size.height,
                            child: Opacity(opacity: t, child: child)),
                        if (t < 1)
                          IgnorePointer(
                              child: Opacity(
                                  opacity: (1 - t * 2).clamp(0.0, 1.0),
                                  child: SizedBox(
                                      width: double.infinity,
                                      child: MarkSixLatestCard(
                                          controller: controller,
                                          preview: true)))),
                      ]))))
        ]);
      }));
  onDismissChanged?.call(null);
}

class _LatestPreviewShell extends StatefulWidget {
  const _LatestPreviewShell({required this.controller});
  final MarkSixController controller;
  @override
  State<_LatestPreviewShell> createState() => _LatestPreviewShellState();
}

class _LatestPreviewShellState extends State<_LatestPreviewShell> {
  @override
  void initState() {
    super.initState();
    widget.controller.attach();
  }

  @override
  void dispose() {
    widget.controller.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = MarkSixStyle.of(context);
    return Container(
        key: const ValueKey('lottery-preview-card-shell'),
        height: 160,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [style.lotteryPanel, style.lotteryAlt]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: style.lotteryBorder),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x1F17243D),
                  blurRadius: 10,
                  offset: Offset(0, 3))
            ]),
        child: Stack(children: [
          Positioned(
              right: 6,
              bottom: 8,
              child: IgnorePointer(
                  child: ExcludeSemantics(
                      child: Opacity(
                          opacity: style.dark ? .14 : .20,
                          child: Image.asset(
                              '${markSixAssetPath}latest_card_watermark.png',
                              width: 96,
                              height: 96))))),
          Column(children: [
            Expanded(
                child: ListenableBuilder(
                    listenable: widget.controller,
                    builder: (_, __) => LayoutBuilder(
                        builder: (context, constraints) =>
                            SingleChildScrollView(
                                child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                        minHeight: constraints.maxHeight),
                                    child: Center(
                                        child: MarkSixLatestCard(
                                            controller: widget.controller,
                                            preview: true))))))),
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('点击卡片 · 全屏查看开奖记录',
                    style: TextStyle(
                        fontSize: 11,
                        color: style.secondary,
                        fontWeight: FontWeight.w500))),
          ])
        ]));
  }
}

class _LotteryPreviewPosition extends SingleChildLayoutDelegate {
  const _LotteryPreviewPosition(this.anchorY, this.pixelRatio);
  final double? anchorY;
  final double pixelRatio;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();
  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxY = (size.height - childSize.height).clamp(0.0, double.infinity);
    final y =
        ((anchorY ?? size.height * .3) - childSize.height / 2).clamp(0.0, maxY);
    return Offset(size.width - childSize.width,
        ((y * pixelRatio).round() / pixelRatio).clamp(0.0, maxY));
  }

  @override
  bool shouldRelayout(_LotteryPreviewPosition old) =>
      anchorY != old.anchorY || pixelRatio != old.pixelRatio;
}
