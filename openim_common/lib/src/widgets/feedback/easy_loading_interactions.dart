import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';

/// Keep loading modal by default; toast calls explicitly use a non-modal mask.
void configureEasyLoadingInteractions() {
  EasyLoading.instance
    ..userInteractions = null
    ..maskType = EasyLoadingMaskType.clear
    ..animationStyle = EasyLoadingAnimationStyle.custom
    ..customAnimation = _FeedbackOpacityAnimation();
}

class _FeedbackOpacityAnimation extends EasyLoadingAnimation {
  @override
  Widget buildWidget(
    Widget child,
    AnimationController controller,
    AlignmentGeometry alignment,
  ) =>
      // EasyLoading's mask controls modality. Its painted content must also
      // pass hits through, including while a toast is fading in or out.
      IgnorePointer(
        child: Opacity(
          opacity: controller.value,
          child: Builder(builder: (context) {
            final media = MediaQuery.of(context);
            final safe = media.viewPadding;
            final keyboard = media.viewInsets;
            return Padding(
              // Both values are measured from the screen edge. Taking their
              // maximum avoids adding the safe area to the keyboard twice.
              padding: EdgeInsets.fromLTRB(
                math.max(safe.left, keyboard.left),
                math.max(safe.top, keyboard.top),
                math.max(safe.right, keyboard.right),
                math.max(safe.bottom, keyboard.bottom),
              ),
              child: LayoutBuilder(builder: (context, constraints) {
                final width = math.max(0.0, constraints.maxWidth);
                return Align(
                  alignment: alignment,
                  child: FittedBox(
                    key: const ValueKey('global-feedback-content'),
                    fit: BoxFit.scaleDown,
                    alignment: alignment,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: width),
                      // The library's Column has no Flexible children. Allow
                      // its natural height before fitting it into a short
                      // viewport, rather than imposing an overflowing height.
                      child: DefaultTextStyle.merge(
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        child: child,
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
        ),
      );
}
