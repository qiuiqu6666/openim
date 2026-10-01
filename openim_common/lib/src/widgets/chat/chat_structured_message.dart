import 'dart:convert';
import 'chat_attachment_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatStructuredMessage extends StatelessWidget {
  const ChatStructuredMessage(
      {super.key, required this.message, this.depth = 0});
  final Message message;
  final int depth;

  static String? emojiUrl(Message message) {
    var data = message.faceElem?.data ?? message.customElem?.data;
    if (data == null) return null;
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map) {
        final payload = decoded['data'];
        data = (payload is Map ? payload['url'] : decoded['url']) as String?;
      }
    } catch (_) {}
    final uri = Uri.tryParse(data ?? '');
    return uri != null && ['http', 'https'].contains(uri.scheme) ? data : null;
  }

  Future<void> _openLocation() async {
    final point = message.locationElem;
    final lat = point?.latitude, lng = point?.longitude;
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      IMViews.showToast('sdkInvalidLocation'.tr);
      return;
    }
    try {
      final url = Uri.https('www.google.com', '/maps/search/',
          {'api': '1', 'query': '$lat,$lng'});
      if (!await launchUrl(url, mode: LaunchMode.externalApplication))
        throw StateError('Map unavailable');
    } catch (_) {
      IMViews.showToast('sdkOpenFailed'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (message.contentType == MessageType.customFace || message.isEmojiType) {
      final url = emojiUrl(message);
      return SizedBox(
          width: 100.w,
          height: 100.w,
          child: url == null
              ? Center(
                  child:
                      Text('[${StrRes.emoji}]', style: Styles.ts_0C1C33_17sp))
              : Image.network(url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                      Icons.broken_image_outlined,
                      color: Styles.c_8E9AB0)));
    }
    final merge = message.contentType == MessageType.merger;
    return InkWell(
      onTap: merge
          ? () {
              if (depth >= 8) {
                IMViews.showToast('sdkRecordTooDeep'.tr);
                return;
              }
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      _MergedHistory(message: message, depth: depth + 1)));
            }
          : _openLocation,
      child: SizedBox(
          width: 210.w,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Icon(
                      merge ? Icons.forum_outlined : Icons.location_on_outlined,
                      color: Styles.c_0089FF),
                  8.horizontalSpace,
                  Expanded(
                      child: Text(
                          merge
                              ? (message.mergeElem?.title ??
                                  'sdkMergedHistory'.tr)
                              : (message.locationElem?.description ??
                                  StrRes.toolboxLocation),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Styles.ts_0C1C33_17sp))
                ]),
                6.verticalSpace,
                if (merge) ...[
                  for (final text
                      in (message.mergeElem?.abstractList ?? <String>[])
                          .take(3))
                    Text(text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Styles.ts_8E9AB0_12sp),
                  Text('sdkViewHistory'.tr, style: Styles.ts_0089FF_12sp),
                ] else
                  Text(
                      '${message.locationElem?.latitude ?? ''}, ${message.locationElem?.longitude ?? ''}',
                      style: Styles.ts_8E9AB0_12sp),
              ])),
    );
  }
}

class _MergedHistory extends StatelessWidget {
  const _MergedHistory({required this.message, required this.depth});
  final Message message;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final records = message.mergeElem?.multiMessage ?? <Message>[];
    return Scaffold(
      backgroundColor: Styles.c_FFFFFF,
      appBar: GlassAppBar(
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: Styles.c_0089FF),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(message.mergeElem?.title ?? 'sdkMergedHistory'.tr,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Styles.ts_0C1C33_17sp_semibold),
      ),
      body: records.isEmpty
          ? Center(child: Text('chatSearchEmpty'.tr))
          : ListView.builder(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              itemCount: records.length,
              itemBuilder: (context, index) {
                final item = Message.fromJson(records[index].toJson());
                item.clientMsgID ??= 'merged_$index';
                item.sendTime ??= 0;
                item.isRead ??= false;
                return ChatItemView(
                  message: item,
                  structuredDepth: depth,
                  leftNickname: item.senderNickname,
                  leftFaceUrl: item.senderFaceUrl,
                  rightNickname: item.senderNickname,
                  rightFaceUrl: item.senderFaceUrl,
                  onTapUserProfile: (_) {},
                  onClickItemView: () {
                    if (item.isPictureType || item.isVideoType) {
                      IMUtils.previewMediaFile(context: context, message: item);
                    } else if (item.isFileType) {
                      IMUtils.previewFile(item);
                    }
                  },
                  mediaItemBuilder: (context, media) => GestureDetector(
                    onTap: () => IMUtils.previewMediaFile(context: context, message: media),
                    child: media.isPictureType
                        ? ChatPictureView(
                            isISend: media.sendID == OpenIM.iMManager.userID,
                            message: media)
                        : Stack(alignment: Alignment.center, children: [
                            Image.network(media.videoElem?.snapshotUrl ?? '',
                              width: 180.w, height: 180.w, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => SizedBox(
                                width: 180.w, height: 180.w)),
                            Icon(Icons.play_circle_fill, color: Styles.c_0089FF, size: 40),
                          ]),
                  ),
                );
              },
            ),
    );
  }
}