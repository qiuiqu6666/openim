import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../mine/settings/widgets/settings_widgets.dart';

/// Keeps one scrollable mounted while results fade into a stable viewport.
class FavoritePickerContent extends StatefulWidget {
  const FavoritePickerContent({
    super.key,
    required this.revision,
    required this.loading,
    required this.child,
  });

  final Object revision;
  final bool loading;
  final Widget child;

  @override
  State<FavoritePickerContent> createState() => _FavoritePickerContentState();
}

class _FavoritePickerContentState extends State<FavoritePickerContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: FavoritePickerTokens.contentTransitionDuration,
    value: 1,
  );
  late final CurvedAnimation _opacity = CurvedAnimation(
    parent: _controller,
    curve: FavoritePickerTokens.contentTransitionCurve,
  );
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant FavoritePickerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading) {
      _controller
        ..stop()
        ..value = 1;
    } else if (_reduceMotion) {
      _controller
        ..stop()
        ..value = 1;
    } else if (oldWidget.loading || widget.revision != oldWidget.revision) {
      // Replace any in-flight fade; results never wait on animation completion.
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _opacity.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            ignoring: widget.loading,
            child: FadeTransition(opacity: _opacity, child: widget.child),
          ),
          if (widget.loading)
            Center(
              child: CircularProgressIndicator(
                key: const ValueKey('favorites-loading'),
                semanticsLabel: settingsText(context,
                    zh: '正在加载收藏', en: 'Loading favorites'),
              ),
            ),
        ],
      );
}
