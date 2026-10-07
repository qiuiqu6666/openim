import 'package:flutter/material.dart';

/// Keeps the visible thumbnail and its decoded image alive during a flight.
class MediaThumbnailHero extends StatefulWidget {
  const MediaThumbnailHero({super.key, required this.tag, required this.child});

  final Object tag;
  final Widget child;

  /// A shuttle needs its own subtree, without the thumbnail's retention key.
  static Widget flightChildOf(BuildContext heroContext) =>
      heroContext.findAncestorWidgetOfExactType<MediaThumbnailHero>()?.child ??
      (heroContext.widget as Hero).child;

  @override
  State<MediaThumbnailHero> createState() => _MediaThumbnailHeroState();
}

class _MediaThumbnailHeroState extends State<MediaThumbnailHero> {
  final _contentKey = GlobalKey();

  @override
  Widget build(BuildContext context) => Hero(
        tag: widget.tag,
        // Hero changes the placeholder's ancestors at takeoff and landing.
        // Reparent this subtree instead of restarting local file checks.
        child: KeyedSubtree(key: _contentKey, child: widget.child),
        placeholderBuilder: (context, size, child) => SizedBox(
          width: size.width,
          height: size.height,
          child: child,
        ),
      );
}
