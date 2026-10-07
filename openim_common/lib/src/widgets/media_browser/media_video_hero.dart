import 'package:flutter/material.dart';

import 'media_thumbnail_hero.dart';

/// Flies the poster while keeping the live player out of thumbnail constraints.
class MediaVideoHero extends StatefulWidget {
  const MediaVideoHero({super.key, required this.tag, required this.child});

  final Object tag;
  final Widget child;

  @override
  State<MediaVideoHero> createState() => _MediaVideoHeroState();
}

class _MediaVideoHeroState extends State<MediaVideoHero> {
  final _contentKey = GlobalKey();

  @override
  Widget build(BuildContext context) => Hero(
        tag: widget.tag,
        child: KeyedSubtree(key: _contentKey, child: widget.child),
        placeholderBuilder: (context, size, child) => SizedBox.fromSize(
          size: size,
          child: Offstage(child: TickerMode(enabled: false, child: child)),
        ),
        flightShuttleBuilder: (context, animation, direction, from, to) {
          final thumbnail = direction == HeroFlightDirection.pop ? to : from;
          final thumbnailBox = thumbnail.findRenderObject()! as RenderBox;
          // Scale a fixed poster layout. Copying the player here would create
          // another controller and lay out its controls at bubble width.
          return FittedBox(
            fit: BoxFit.contain,
            child: SizedBox.fromSize(
              size: thumbnailBox.size,
              child: MediaThumbnailHero.flightChildOf(thumbnail),
            ),
          );
        },
      );
}
