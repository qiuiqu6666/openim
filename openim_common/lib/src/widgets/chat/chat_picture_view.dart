import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:path_provider/path_provider.dart';

import 'picture/chat_picture_quality.dart';

class ChatPictureView extends StatefulWidget {
  const ChatPictureView({
    super.key,
    required this.message,
    required this.isISend,
    this.maxDisplayWidth,
    this.maxDisplayHeight,
  });
  final bool isISend;
  final Message message;
  final double? maxDisplayWidth;
  final double? maxDisplayHeight;

  @override
  State<ChatPictureView> createState() => _ChatPictureViewState();
}

class _ChatPictureViewState extends State<ChatPictureView> {
  static const _longImageAspectRatio = 1 / 1.8;

  String? _inputPath;
  String? _sourcePath;
  String? _sourceUrl;
  String? _snapshotUrl;
  String? _messageID;
  bool _localPathValid = false;
  bool _resolvingLocalPath = false;
  int _pathGeneration = 0;

  @override
  void initState() {
    super.initState();
    _updateSources();
  }

  @override
  void didUpdateWidget(covariant ChatPictureView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateSources(force: oldWidget.isISend != widget.isISend);
  }

  void _updateSources({bool force = false}) {
    final picture = widget.message.pictureElem;
    _sourceUrl = IMUtils.isNotNullEmptyStr(picture?.bigPicture?.url)
        ? picture?.bigPicture?.url
        : picture?.sourcePicture?.url;
    _snapshotUrl = ChatPicturePreviewMetadata.topCrop(widget.message)?.url ??
        picture?.snapshotPicture?.url;
    final path = picture?.sourcePath;
    final messageID = widget.message.clientMsgID;
    if (!force && path == _inputPath && messageID == _messageID) return;
    _inputPath = path;
    _messageID = messageID;
    _sourcePath = path;
    _localPathValid = false;
    _resolvingLocalPath = widget.isISend && path != null && path.isNotEmpty;
    final generation = ++_pathGeneration;
    if (widget.isISend && path != null && path.isNotEmpty) {
      unawaited(_resolveLocalPath(path, generation));
    }
  }

  Future<void> _resolveLocalPath(String path, int generation) async {
    var resolved = path;
    var exists = false;
    try {
      if (Platform.isIOS && path.contains('/Library/Caches/')) {
        final directory = await getApplicationCacheDirectory();
        resolved = directory.path + path.split('/Library/Caches').last;
      }
      exists = await File(resolved).exists();
    } catch (_) {
      // A missing local attachment can still use the remote thumbnail.
    }
    if (!mounted || generation != _pathGeneration) return;
    setState(() {
      _sourcePath = resolved;
      _localPathValid = exists;
      _resolvingLocalPath = false;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, constraints) => _buildPicture(context, constraints));

  Widget _buildPicture(BuildContext context, BoxConstraints constraints) {
    final picture = widget.message.pictureElem;
    final topPreview = ChatPicturePreviewMetadata.topCrop(widget.message);
    final sourceSize = ChatPictureQuality.sourceSize(picture);
    final width = sourceSize.width;
    final height = sourceSize.height;
    final isLongImage = height >= width / _longImageAspectRatio;
    // Square and landscape attachments need room for their content; keep portrait/long
    // images compact and preserve explicit sizing used by conversation peeks.
    final limit = (widget.maxDisplayWidth ??
            (width >= height ? 120.w : pictureWidth) *
                (isLongImage ? 1.0 : 1.2))
        .clamp(0.0, constraints.maxWidth);
    var displayWidth = width < limit ? width : limit;
    var displayHeight = displayWidth * height / width;
    // Choose the visible top crop before fitting the bubble's height. Fitting
    // the entire long image first collapses its width to an unreadable strip.
    if (displayHeight > displayWidth / _longImageAspectRatio) {
      displayHeight = displayWidth / _longImageAspectRatio;
    }
    final heightLimit = widget.maxDisplayHeight;
    if (heightLimit != null && displayHeight > heightLimit) {
      displayWidth *= heightLimit / displayHeight;
      displayHeight = heightLimit;
    }
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final decodeSize = ChatPictureQuality.decodeSize(
        source: sourceSize,
        displayWidth: displayWidth,
        devicePixelRatio: pixelRatio);
    final cacheWidth = decodeSize.width.toInt();
    final cacheHeight = decodeSize.height.toInt();
    final cropped = displayWidth * height / width > displayHeight + 1;
    final alignment = cropped ? Alignment.topCenter : Alignment.center;
    final thumbnailURL =
        IMUtils.isNotNullEmptyStr(_snapshotUrl) ? _snapshotUrl : _sourceUrl;
    // Never silently upgrade a failed bubble preview to the full attachment.
    final remoteURL = topPreview?.url ?? thumbnailURL;
    String? small(String original) {
      final resized =
          OpenIMMediaUrl.thumbnail(original, width: 640, height: 640);
      return resized == original ? null : resized;
    }

    final urls = <String>{
      if (remoteURL != null && remoteURL.trim().isNotEmpty)
        if (topPreview != null ||
            (remoteURL != picture?.sourcePicture?.url &&
                remoteURL != picture?.bigPicture?.url))
          remoteURL
        else if (small(remoteURL) case final String resized)
          resized,
      if (topPreview != null)
        if (picture?.sourcePicture?.url case final String original)
          if (small(original) case final String resized) resized,
    }.toList();

    Widget? remote([int index = 0]) {
      if (index >= urls.length) return null;
      final previewSize = topPreview != null && urls[index] == topPreview.url
          ? ChatPictureQuality.decodeSize(
              source: Size(
                  topPreview.width!.toDouble(), topPreview.height!.toDouble()),
              displayWidth: displayWidth,
              devicePixelRatio: pixelRatio)
          : null;
      return ImageUtil.networkImage(
        url: urls[index],
        width: displayWidth,
        height: displayHeight,
        cacheWidth: previewSize?.width.toInt() ?? cacheWidth,
        cacheHeight: previewSize?.height.toInt() ?? cacheHeight,
        resizePolicy: ResizeImagePolicy.fit,
        cacheRawData: false,
        fit: BoxFit.fitWidth,
        alignment: alignment,
        errorWidget: remote(index + 1),
      );
    }

    final child = topPreview != null
        ? remote()
        : widget.isISend && _localPathValid
            ? ImageUtil.fileImage(
                file: File(_sourcePath!),
                width: displayWidth,
                height: displayHeight,
                cacheWidth: cacheWidth,
                cacheHeight: cacheHeight,
                resizePolicy: ResizeImagePolicy.fit,
                cacheRawData: false,
                fit: BoxFit.fitWidth,
                alignment: alignment,
                errorWidget: remote(),
              )
            : _resolvingLocalPath
                ? null
                : remote();
    return ClipRRect(
      borderRadius: BorderRadius.circular(ChatBubbleTokens.radius),
      child: SizedBox(
        width: displayWidth,
        height: displayHeight,
        child: child,
      ),
    );
  }
}
