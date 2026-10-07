import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

import 'media_browser/media_thumbnail_hero.dart';

class HeroWidget extends StatefulWidget {
  const HeroWidget({
    super.key,
    required this.child,
    required this.tag,
    required this.slidePagekey,
    this.slideType = SlideType.onlyImage,
  });
  final Widget child;
  final SlideType slideType;
  final Object tag;
  final GlobalKey<ExtendedImageSlidePageState> slidePagekey;
  @override
  State<HeroWidget> createState() => _HeroWidgetState();
}

class _HeroWidgetState extends State<HeroWidget> {
  RectTween? _rectTween;
  final _contentKey = GlobalKey();
  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: widget.tag,
      // Flutter normally unmounts the destination while the shuttle is flying.
      // Keep its file check, decoded image and gesture state alive so landing
      // cannot briefly replace the picture with its loading placeholder.
      placeholderBuilder: (context, size, child) => SizedBox(
        width: size.width,
        height: size.height,
        child: Offstage(
          child: TickerMode(enabled: false, child: child),
        ),
      ),
      createRectTween: (Rect? begin, Rect? end) {
        _rectTween = RectTween(begin: begin, end: end);
        return _rectTween!;
      },
      flightShuttleBuilder: (BuildContext flightContext,
          Animation<double> animation,
          HeroFlightDirection flightDirection,
          BuildContext fromHeroContext,
          BuildContext toHeroContext) {
        if (_rectTween == null) {
          return widget.child;
        }

        if (flightDirection == HeroFlightDirection.pop) {
          final bool fixTransform = widget.slideType == SlideType.onlyImage &&
              (widget.slidePagekey.currentState!.offset != Offset.zero ||
                  widget.slidePagekey.currentState!.scale != 1.0);

          final toHeroWidget = MediaThumbnailHero.flightChildOf(toHeroContext);
          final content = Stack(
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            children: <Widget>[
              FadeTransition(
                opacity: ReverseAnimation(animation),
                child: UnconstrainedBox(
                  child: SizedBox(
                    width: _rectTween!.begin!.width,
                    height: _rectTween!.begin!.height,
                    child: toHeroWidget,
                  ),
                ),
              ),
              FadeTransition(
                opacity: animation,
                child: widget.child,
              )
            ],
          );

          if (!fixTransform) return content;
          final slidePage = widget.slidePagekey.currentState!;
          return MatrixTransition(
            animation: animation,
            onTransform: (value) {
              final offset = slidePage.offset * value;
              final scale = 1 + (slidePage.scale - 1) * value;
              return Matrix4.translationValues(offset.dx, offset.dy, 0)
                ..scaleByDouble(scale, scale, 1, 1);
            },
            child: content,
          );
        }
        // The shuttle has its own subtree; never duplicate _contentKey here.
        return widget.child;
      },
      child: KeyedSubtree(key: _contentKey, child: widget.child),
    );
  }
}
