import 'package:flutter/material.dart';

typedef AppNetworkImageErrorBuilder = Widget Function(
  BuildContext context,
  String url,
  Object error,
);

class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
    this.memCacheHeight,
    this.errorWidget,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final AppNetworkImageErrorBuilder? errorWidget;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: memCacheWidth,
      cacheHeight: memCacheHeight,
      gaplessPlayback: true,
      errorBuilder: errorWidget == null
          ? null
          : (context, error, stackTrace) => errorWidget!(context, url, error),
    );
  }
}
