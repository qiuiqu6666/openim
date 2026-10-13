import 'package:flutter/material.dart';

/// Bounds decoded pixels independently of the server's compressed file size.
class PersonalStickerThumbnail extends StatelessWidget {
  const PersonalStickerThumbnail(this.url,
      {super.key,
      this.width,
      this.height,
      this.fit = BoxFit.cover,
      this.errorBuilder});

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final ratio = MediaQuery.devicePixelRatioOf(context);
        final w = width ?? (box.hasBoundedWidth ? box.maxWidth : 256);
        final h = height ?? (box.hasBoundedHeight ? box.maxHeight : 256);
        return Image(
          image: ResizeImage(NetworkImage(url),
              width: (w * ratio).ceil().clamp(1, 1024).toInt(),
              height: (h * ratio).ceil().clamp(1, 1024).toInt(),
              policy: ResizeImagePolicy.fit),
          width: width,
          height: height,
          fit: fit,
          errorBuilder: errorBuilder,
        );
      });
}
