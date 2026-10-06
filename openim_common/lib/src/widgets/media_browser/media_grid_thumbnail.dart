import 'dart:io';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'local_media_availability.dart';

/// Uses the small source first and bounds decoded pixels independently of the
/// full-screen gesture viewer's original-quality provider.
class MediaGridThumbnail extends StatelessWidget {
  const MediaGridThumbnail({
    super.key,
    required this.source,
    required this.availability,
  });
  final MediaSource source;
  final LocalMediaAvailability availability;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final width = ImageUtil.decodeDimension(constraints.maxWidth, dpr);
          final height = ImageUtil.decodeDimension(constraints.maxHeight, dpr);
          Widget placeholder({bool failed = false}) {
            final dark = Theme.of(context).brightness == Brightness.dark;
            final zh = Localizations.localeOf(context).languageCode == 'zh';
            return ColoredBox(
              color: AppTokens.surface(dark: dark),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                      failed
                          ? Icons.broken_image_outlined
                          : Icons.image_outlined,
                      color: AppTokens.textSecondary(dark: dark),
                      size: 28),
                  if (failed) ...[
                    const SizedBox(height: 6),
                    Text(zh ? '缩略图不可用' : 'Preview unavailable',
                        style: TextStyle(
                            color: AppTokens.textSecondary(dark: dark),
                            fontSize: 11)),
                  ],
                ]),
              ),
            );
          }

          Widget image(ImageProvider provider,
                  {Widget Function()? onFailure}) =>
              Image(
                image: ResizeImage(provider,
                    width: width,
                    height: height,
                    policy: ResizeImagePolicy.fit),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    onFailure?.call() ?? placeholder(failed: true),
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : placeholder(),
              );

          Widget original() {
            if (!source.isVideo && source.bytes != null) {
              return image(MemoryImage(source.bytes!));
            }
            Widget remote() =>
                !source.isVideo && source.url?.startsWith('http') == true
                    ? image(NetworkImage(source.url!))
                    : placeholder(failed: true);
            final file = source.isVideo ? null : source.file;
            if (file == null) return remote();
            return FutureBuilder<bool>(
              future: availability.exists(file),
              builder: (_, snapshot) => !snapshot.hasData
                  ? placeholder()
                  : snapshot.data!
                      ? image(FileImage(file), onFailure: remote)
                      : remote(),
            );
          }

          final uri = source.thumbnail;
          if (uri.isEmpty) return original();
          if (uri.startsWith('http')) {
            return image(NetworkImage(uri), onFailure: original);
          }
          final file = File(
              uri.startsWith('file://') ? Uri.parse(uri).toFilePath() : uri);
          return FutureBuilder<bool>(
            future: availability.exists(file),
            builder: (_, snapshot) => !snapshot.hasData
                ? placeholder()
                : snapshot.data!
                    ? image(FileImage(file), onFailure: original)
                    : original(),
          );
        },
      );
}
