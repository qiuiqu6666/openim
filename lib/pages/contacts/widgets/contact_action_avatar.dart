import 'package:flutter/material.dart';

/// Source windows in the supplied artwork, preserving the original rendering.
enum ContactActionArtwork {
  newFriend(97, 155, 412),
  groupNotice(617, 155, 412),
  myGroups(1137, 156, 412),
  channel(1660, 155, 412);

  const ContactActionArtwork(this.left, this.top, this.diameter);
  final double left;
  final double top;
  final double diameter;
}

/// One shared asset is decoded by Flutter's image cache for all four entries.
/// The row supplies the accessible label; the artwork is decorative.
class ContactActionAvatar extends StatelessWidget {
  const ContactActionAvatar({
    super.key,
    required this.artwork,
    required this.size,
  });

  final ContactActionArtwork artwork;
  final double size;
  static const asset = 'assets/images/contact_actions_reference.png';
  static const sourceSize = Size(2172, 724);

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: ClipOval(
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox.square(
                dimension: artwork.diameter,
                child: Stack(children: [
                  Positioned(
                    left: -artwork.left,
                    top: -artwork.top,
                    width: sourceSize.width,
                    height: sourceSize.height,
                    child:
                        Image.asset(asset, filterQuality: FilterQuality.medium),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}
