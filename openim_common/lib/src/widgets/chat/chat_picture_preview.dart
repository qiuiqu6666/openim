import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class ChatPicturePreview extends StatelessWidget {
  ChatPicturePreview({
    Key? key,
    this.currentIndex = 0,
    this.images = const [],
    this.heroTag,
    this.onTap,
    this.onLongPress,
  })  : controller = images.length > 1
            ? ExtendedPageController(initialPage: currentIndex, pageSpacing: 50)
            : null,
        super(key: key);
  final int currentIndex;
  final List<MediaSource> images;
  final String? heroTag;
  final Function()? onTap;
  final Function(String url)? onLongPress;
  final ExtendedPageController? controller;
  final GlobalKey<ExtendedImageSlidePageState> slidePagekey =
      GlobalKey<ExtendedImageSlidePageState>();
  @override
  Widget build(BuildContext context) {
    return ExtendedImageSlidePage(
      key: slidePagekey,
      slideAxis: SlideAxis.vertical,
      slidePageBackgroundHandler: (offset, pageSize) =>
          defaultSlidePageBackgroundHandler(
        color: Colors.black,
        offset: offset,
        pageSize: pageSize,
      ),
      child: MetaHero(
        heroTag: heroTag,
        onTap: onTap ?? () => Get.back(),
        onLongPress: () {
          if (images.isEmpty) return;
          final index = controller?.page?.round() ?? 0;
          onLongPress?.call(images[index].url!);
        },
        child: _childView,
      ),
    );
  }

  Widget get _childView {
    return images.length == 1 ? _networkGestureImage(images[0]) : _pageView;
  }

  Widget get _pageView => ExtendedImageGesturePageView.builder(
        controller: controller,
        onPageChanged: (int index) {},
        itemCount: images.length,
        itemBuilder: (BuildContext context, int index) {
          return _networkGestureImage(images.elementAt(index));
        },
      );

  Widget _networkGestureImage(MediaSource source) => AdaptiveMediaImage(
        image: ExtendedNetworkImageProvider(source.url ?? source.thumbnail),
        clearMemoryCacheWhenDispose: true,
        loadStateChanged: (ExtendedImageState state) {
          switch (state.extendedImageLoadState) {
            case LoadState.loading:
              {
                if (source.url?.isVideoFileName == true) {
                  return null;
                }
                final ImageChunkEvent? loadingProgress = state.loadingProgress;
                final double? progress =
                    loadingProgress?.expectedTotalBytes != null
                        ? loadingProgress!.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null;

                return SizedBox(
                  width: 15.0,
                  height: 15.0,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Styles.c_0089FF,
                      strokeWidth: 1.5,
                      value: progress ?? 0,
                    ),
                  ),
                );
              }
            case LoadState.completed:
              return null;
            case LoadState.failed:
              state.imageProvider.evict();
              return ImageRes.pictureError.toImage;
          }
        },
      );
}

class MetaHero extends StatelessWidget {
  const MetaHero({
    Key? key,
    required this.heroTag,
    required this.child,
    this.onTap,
    this.onLongPress,
  }) : super(key: key);
  final Widget child;
  final String? heroTag;
  final Function()? onTap;
  final Function()? onLongPress;

  @override
  Widget build(BuildContext context) {
    final view = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      onLongPress: onLongPress,
      child: child,
    );
    return heroTag == null ? view : Hero(tag: heroTag!, child: view);
  }
}
