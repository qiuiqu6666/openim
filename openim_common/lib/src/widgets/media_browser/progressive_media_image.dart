import 'package:extended_image/extended_image.dart';
import 'package:flutter/widgets.dart';

import 'adaptive_media_image.dart';
import 'media_image_loading.dart';

/// Lower-resolution sources remain visible until the requested image is ready.
/// Failure of a warmup is independent of failure of the requested image.
class ProgressiveMediaImage extends StatelessWidget {
  const ProgressiveMediaImage({
    super.key,
    required this.image,
    required this.previews,
    required this.retryBuilder,
  });

  final ImageProvider image;
  final List<ImageProvider> previews;
  final Widget Function(VoidCallback retry) retryBuilder;

  Widget _preview(int index, bool failed) {
    if (index >= previews.length) {
      return failed ? const SizedBox.expand() : const MediaImageLoading();
    }
    return AdaptiveMediaImage(
      image: previews[index],
      loadStateChanged: (state) =>
          state.extendedImageLoadState == LoadState.completed
              ? null
              : _preview(index + 1, failed),
    );
  }

  @override
  Widget build(BuildContext context) => AdaptiveMediaImage(
        image: image,
        loadStateChanged: (state) {
          if (state.extendedImageLoadState == LoadState.completed) return null;
          final failed = state.extendedImageLoadState == LoadState.failed;
          return Stack(
            fit: StackFit.expand,
            children: [
              // Keep the same preview subtree when loading becomes failed.
              _preview(0, failed),
              if (failed)
                Align(
                  alignment: Alignment.center,
                  child: retryBuilder(() {
                    state.imageProvider.evict();
                    state.reLoadImage();
                  }),
                ),
            ],
          );
        },
      );
}
