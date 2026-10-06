import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class ImageUtil {
  ImageUtil._();

  static const _package = "openim_common";

  static Widget assetImage(
    String res, {
    double? width,
    double? height,
    BoxFit? fit,
    Color? color,
  }) =>
      Image.asset(
        res,
        width: width,
        height: height,
        fit: fit,
        color: color,
        package: _package,
      );

  static Widget networkImage({
    required String url,
    double? width,
    double? height,
    int? cacheWidth,
    int? cacheHeight,
    ResizeImagePolicy resizePolicy = ResizeImagePolicy.exact,
    bool cacheRawData = true,
    BoxFit? fit,
    bool loadProgress = true,
    bool clearMemoryCacheWhenDispose = false,
    bool lowMemory = false,
    Widget? errorWidget,
    Widget? loadingWidget,
    BorderRadius? borderRadius,
  }) =>
      ExtendedImage(
        image: _resizeProvider(
          ExtendedNetworkImageProvider(
              OpenIMMediaUrl.resolve(url, imApiUrl: Config.imApiUrl),
              cache: true,
              cacheRawData: cacheRawData),
          _calculateCacheWidth(width, cacheWidth, lowMemory),
          _calculateCacheHeight(height, cacheHeight, lowMemory),
          resizePolicy,
          cacheRawData,
        ),
        gaplessPlayback: true,
        width: width,
        height: height,
        fit: fit,
        borderRadius: borderRadius,
        enableLoadState: true,
        clearMemoryCacheWhenDispose: clearMemoryCacheWhenDispose,
        handleLoadingProgress: true,
        clearMemoryCacheIfFailed: true,
        loadStateChanged: (ExtendedImageState state) {
          switch (state.extendedImageLoadState) {
            case LoadState.loading:
              {
                if (loadingWidget != null) return loadingWidget;
                final ImageChunkEvent? loadingProgress = state.loadingProgress;
                final double? progress =
                    loadingProgress?.expectedTotalBytes != null
                        ? loadingProgress!.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null;

                return SizedBox(
                  width: 15.0,
                  height: 15.0,
                  child: loadProgress
                      ? Center(
                          child: SizedBox(
                            width: 15.0,
                            height: 15.0,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              value: progress,
                            ),
                          ),
                        )
                      : null,
                );
              }
            case LoadState.completed:
              return null;
            case LoadState.failed:
              state.imageProvider.evict();
              return errorWidget ??
                  (ImageRes.pictureError.toImage
                    ..width = width
                    ..height = height);
          }
        },
      );

  static Widget fileImage({
    required File file,
    double? width,
    double? height,
    int? cacheWidth,
    int? cacheHeight,
    ResizeImagePolicy resizePolicy = ResizeImagePolicy.exact,
    bool cacheRawData = true,
    BoxFit? fit,
    bool loadProgress = true,
    bool clearMemoryCacheWhenDispose = false,
    bool lowMemory = false,
    Widget? errorWidget,
    BorderRadius? borderRadius,
  }) =>
      ExtendedImage(
        image: _resizeProvider(
          ExtendedFileImageProvider(file, cacheRawData: cacheRawData),
          _calculateCacheWidth(width, cacheWidth, lowMemory),
          _calculateCacheHeight(height, cacheHeight, lowMemory),
          resizePolicy,
          cacheRawData,
        ),
        width: width,
        height: height,
        fit: fit,
        borderRadius: borderRadius,
        enableLoadState: true,
        clearMemoryCacheWhenDispose: clearMemoryCacheWhenDispose,
        clearMemoryCacheIfFailed: true,
        loadStateChanged: (ExtendedImageState state) {
          switch (state.extendedImageLoadState) {
            case LoadState.loading:
              {
                final ImageChunkEvent? loadingProgress = state.loadingProgress;
                final double? progress =
                    loadingProgress?.expectedTotalBytes != null
                        ? loadingProgress!.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null;

                return SizedBox(
                  width: 15.0,
                  height: 15.0,
                  child: loadProgress
                      ? Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            value: progress,
                          ),
                        )
                      : null,
                );
              }
            case LoadState.completed:
              return null;
            case LoadState.failed:
              state.imageProvider.evict();
              return errorWidget ?? ImageRes.pictureError.toImage;
          }
        },
      );

  /// Decode bounds use physical pixels; full-screen previews opt out by default.
  static int? decodeDimension(double? logicalSize, double devicePixelRatio) {
    if (logicalSize == null || !logicalSize.isFinite || logicalSize <= 0) {
      return null;
    }
    final ratio = devicePixelRatio.isFinite && devicePixelRatio > 0
        ? devicePixelRatio
        : 1.0;
    final pixels = logicalSize * ratio;
    return pixels.isFinite ? pixels.ceil() : null;
  }

  static ImageProvider _resizeProvider(
    ImageProvider provider,
    int? width,
    int? height,
    ResizeImagePolicy policy,
    bool cacheRawData,
  ) =>
      width == null && height == null
          ? provider
          : ExtendedResizeImage(provider,
              width: width,
              height: height,
              maxBytes: null,
              policy: policy,
              cacheRawData: cacheRawData);

  static int? _calculateCacheWidth(
    double? width,
    int? cacheWidth,
    bool lowMemory,
  ) {
    if (null != cacheWidth) return cacheWidth;
    if (!lowMemory) return null;
    final maxW = .6.sw;
    return (width == null ? maxW : (width < maxW ? width : maxW)).toInt();
  }

  static int? _calculateCacheHeight(
    double? height,
    int? cacheHeight,
    bool lowMemory,
  ) {
    if (null != cacheHeight) return cacheHeight;
    if (!lowMemory) return null;
    final maxH = .6.sh;
    return (height == null ? maxH : (height < maxH ? height : maxH)).toInt();
  }
}
