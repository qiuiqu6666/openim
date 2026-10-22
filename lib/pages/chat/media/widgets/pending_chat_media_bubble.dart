import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../preparation/pending_chat_media.dart';

/// A thumbnail is optional; rendering the outgoing bubble never waits on IO.
class PendingChatMediaBubble extends StatefulWidget {
  const PendingChatMediaBubble(
      {super.key, required this.pending, this.isChannel = false});
  final PendingChatMedia pending;
  final bool isChannel;

  @override
  State<PendingChatMediaBubble> createState() => _PendingChatMediaBubbleState();
}

class _PendingChatMediaBubbleState extends State<PendingChatMediaBubble> {
  late final Future<Uint8List?> _thumbnail = _loadThumbnail();

  Future<Uint8List?> _loadThumbnail() async {
    try {
      return await widget.pending.asset
          .thumbnailDataWithSize(const ThumbnailSize(320, 320))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.pending.asset;
    final video = asset.type == AssetType.video;
    final width = video
        ? videoWidth
        : (asset.width >= asset.height ? 120.w * 1.2 : pictureWidth);
    final ratio = asset.width > 0 && asset.height > 0
        ? (video
            ? (asset.width / asset.height).clamp(0.5, 2.0)
            : (asset.width / asset.height).clamp(1 / 1.8, double.infinity))
        : (video ? 0.75 : 1.0);
    final displayWidth = !video && asset.width > 0 && asset.width < width
        ? asset.width.toDouble()
        : width;
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHigh,
      child: Center(
          child: Icon(video ? Icons.videocam_outlined : Icons.image_outlined,
              color: colors.onSurfaceVariant)),
    );
    return Semantics(
      label: 'chatMediaPreparing'.trParams({'count': '1'}),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTokens.s4),
        padding: EdgeInsets.symmetric(horizontal: 10.w),
        child: Center(
            child: ChatItemContainer(
          id: widget.pending.id,
          isISend: true,
          isBubbleBg: false,
          mediaOverlay: true,
          avatarSize: 36,
          alignLeft: widget.isChannel,
          showAvatar: !widget.isChannel,
          showLeftNickname: false,
          hasRead: false,
          showReadStatus: false,
          isSending: true,
          centerSendingStatus: video,
          isSendFailed: false,
          rightNickname: OpenIM.iMManager.userInfo.nickname,
          rightFaceUrl: OpenIM.iMManager.userInfo.faceURL,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(ChatBubbleTokens.radius),
            child: SizedBox(
              width: displayWidth,
              height: displayWidth / ratio,
              child: FutureBuilder<Uint8List?>(
                future: _thumbnail,
                builder: (context, snapshot) => snapshot.data == null
                    ? placeholder
                    : Image.memory(snapshot.data!,
                        fit: BoxFit.cover,
                        excludeFromSemantics: true,
                        errorBuilder: (_, __, ___) => placeholder),
              ),
            ),
          ),
        )),
      ),
    );
  }
}
