import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
  static const _longImageAspectRatio = 3 / 5;
  static const _longImageHeightRatio = 3.0;

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
    _snapshotUrl =
        picture?.snapshotPicture?.url?.adjustThumbnailAbsoluteString(960);
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
    final sourceSize = ChatPictureQuality.sourceSize(picture);
    final width = sourceSize.width;
    final height = sourceSize.height;
    final limit = (widget.maxDisplayWidth ?? pictureWidth)
        .clamp(0.0, constraints.maxWidth);
    var displayWidth = width < limit ? width : limit;
    var displayHeight = displayWidth * height / width;
    // Choose the visible top crop before fitting the bubble's height. Fitting
    // the entire long image first collapses its width to an unreadable strip.
    if (height / width > _longImageHeightRatio) {
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
    final remoteURL = cropped
        ? ChatPictureQuality.croppedSource(picture, decodeSize) ?? thumbnailURL
        : thumbnailURL;

    Widget? fallback() =>
        IMUtils.isNotNullEmptyStr(thumbnailURL) && thumbnailURL != remoteURL
            ? ImageUtil.networkImage(
                url: thumbnailURL!,
                width: displayWidth,
                height: displayHeight,
                cacheWidth: cacheWidth,
                cacheHeight: cacheHeight,
                resizePolicy: ResizeImagePolicy.fit,
                cacheRawData: false,
                fit: BoxFit.fitWidth,
                alignment: alignment,
              )
            : null;

    Widget? remote() => IMUtils.isNotNullEmptyStr(remoteURL)
        ? ImageUtil.networkImage(
            url: remoteURL!,
            width: displayWidth,
            height: displayHeight,
            cacheWidth: cacheWidth,
            cacheHeight: cacheHeight,
            resizePolicy: ResizeImagePolicy.fit,
            cacheRawData: false,
            fit: BoxFit.fitWidth,
            alignment: alignment,
            loadingWidget: fallback(),
            errorWidget: fallback(),
          )
        : null;

    final child = widget.isISend && _localPathValid
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
      borderRadius: borderRadius(widget.isISend),
      child: SizedBox(
        width: displayWidth,
        height: displayHeight,
        child: child,
      ),
    );
  }
}
