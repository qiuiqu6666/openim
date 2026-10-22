import 'package:flutter/material.dart';

import '../mark_six/widgets/mark_six_drawer.dart';
import '../models/group_feature_context.dart';
import 'bingo_page.dart';
import 'bingo_controller.dart';
import 'bingo_live_card.dart';

Future<void> showBingoDrawer(
    BuildContext context, GroupFeatureContext featureContext,
    {double? anchorY, ValueChanged<VoidCallback?>? onDismissChanged}) async {
  if (!bingoContextCurrent(featureContext)) return;
  final controller =
      BingoController(current: () => bingoContextCurrent(featureContext));
  try {
    var opening = false;
    TransitionRoute<dynamic>? previewRoute;
    final expanded = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭宾果开奖预览',
      barrierColor: Colors.black12,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, _, __) {
        final route = ModalRoute.of(dialogContext)!;
        previewRoute = route;
        onDismissChanged?.call(() {
          if (route.isActive) Navigator.of(dialogContext).removeRoute(route);
        });
        return SafeArea(
          right: false,
          child: CustomSingleChildLayout(
            delegate: LotteryPreviewPosition(
                anchorY == null
                    ? null
                    : anchorY - MediaQuery.paddingOf(dialogContext).top,
                MediaQuery.devicePixelRatioOf(dialogContext)),
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: SizedBox(
                key: const ValueKey('bingo-latest-preview'),
                width: (MediaQuery.sizeOf(dialogContext).width * .88)
                    .clamp(0.0, 520.0),
                child: Material(
                  color: Colors.transparent,
                  child: Semantics(
                    button: true,
                    label: '全屏查看宾果开奖记录',
                    child: InkWell(
                      key: const ValueKey('bingo-preview-open'),
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        if (opening || !controller.current()) {
                          return;
                        }
                        opening = true;
                        Navigator.of(dialogContext).pop(true);
                      },
                      child:
                          BingoLiveCard(controller: controller, preview: true),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
    // pop completes before the reverse transition; keep data/listeners alive
    // until the preview is actually removed from the overlay.
    await previewRoute?.completed;
    onDismissChanged?.call(null);
    if (expanded == true && context.mounted && controller.current()) {
      await BingoPage.open(context, featureContext,
          controller: controller, onDismissChanged: onDismissChanged);
    }
  } finally {
    onDismissChanged?.call(null);
    controller.dispose();
  }
}
