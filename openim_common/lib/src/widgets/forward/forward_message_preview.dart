import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'forward_dialog_tokens.dart';

class ForwardMessagePreview extends StatelessWidget {
  const ForwardMessagePreview({super.key, required this.data});
  final ForwardPreviewData data;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final secondary = AppTokens.textSecondary(dark: dark);
    final body = TextStyle(
        color: AppTokens.textPrimary(dark: dark),
        fontSize: AppTokens.secondaryFontSize,
        height: 1.45);
    Widget text(String value, {bool muted = false, int lines = 3}) =>
        Text(value,
            maxLines: lines,
            overflow: TextOverflow.ellipsis,
            style: muted
                ? body.copyWith(
                    color: secondary, fontSize: AppTokens.captionFontSize)
                : body);
    Widget details() => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              text(data.title),
              if (data.subtitle.isNotEmpty) ...[
                const SizedBox(height: AppTokens.s2),
                text(data.subtitle, muted: true, lines: 2),
              ],
            ]);
    Widget icon(IconData icon, {Color? color}) => Icon(icon,
        size: ForwardDialogTokens.avatar, color: color ?? AppTokens.accent);
    Widget row(Widget leading) => Row(children: [
          leading,
          const SizedBox(width: AppTokens.s4),
          Expanded(child: details()),
        ]);
    final content = switch (data.kind) {
      ForwardPreviewKind.picture ||
      ForwardPreviewKind.video ||
      ForwardPreviewKind.sticker =>
        row(SizedBox(
            width: ForwardDialogTokens.thumbnail,
            height: ForwardDialogTokens.thumbnail,
            child: Stack(fit: StackFit.expand, children: [
              _ForwardThumbnail(data: data),
              if (data.kind == ForwardPreviewKind.video) ...[
                const Center(
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: ForwardDialogTokens.videoScrim,
                            shape: BoxShape.circle),
                        child: Icon(Icons.play_arrow_rounded,
                            color: AppTokens.onAccent,
                            size: ForwardDialogTokens.avatar))),
                if (data.duration != null && data.duration! >= 0)
                  Positioned(
                      right: AppTokens.s2,
                      bottom: AppTokens.s2,
                      child: DecoratedBox(
                          decoration: const BoxDecoration(
                              color: ForwardDialogTokens.videoScrim),
                          child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppTokens.s2),
                              child: Text(_duration(data.duration!),
                                  style: const TextStyle(
                                      color: AppTokens.onAccent,
                                      fontSize: AppTokens.captionFontSize))))),
              ],
            ]))),
      ForwardPreviewKind.file => row(icon(Icons.insert_drive_file_outlined)),
      ForwardPreviewKind.card => row(AvatarView(
          url: data.imageUrl,
          text: data.title,
          width: ForwardDialogTokens.avatar,
          height: ForwardDialogTokens.avatar,
          isCircle: false,
          borderRadius: BorderRadius.circular(AppTokens.rSm))),
      // Location messages currently contain coordinates and a description, no
      // map thumbnail. Show their actual data rather than a fictitious map.
      ForwardPreviewKind.location => row(icon(Icons.location_on_outlined)),
      ForwardPreviewKind.voice => Row(children: [
          icon(Icons.graphic_eq_rounded, color: ForwardDialogTokens.send),
          const SizedBox(width: AppTokens.s4),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                text(data.duration != null && data.duration! >= 0
                    ? '${data.duration}″'
                    : data.title),
                text('[${data.title}]', muted: true),
              ])),
        ]),
      ForwardPreviewKind.record || ForwardPreviewKind.batch => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              text(data.title, lines: 2),
              const SizedBox(height: AppTokens.s3),
              for (final line in data.lines) text(line, muted: true, lines: 1),
              const SizedBox(height: AppTokens.s3),
              Divider(height: 1, color: AppTokens.border(dark: dark)),
              const SizedBox(height: AppTokens.s3),
              text(
                  data.count == null
                      ? StrRes.chatRecord
                      : 'forwardPreviewCount'
                          .trParams({'count': '${data.count}'}),
                  muted: true),
            ]),
      ForwardPreviewKind.text => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              text(data.title, lines: 4),
              if (data.subtitle.isNotEmpty) ...[
                const SizedBox(height: AppTokens.s3),
                Container(
                    padding: const EdgeInsets.only(left: AppTokens.s3),
                    decoration: BoxDecoration(
                        border: Border(
                            left: BorderSide(color: secondary, width: 2))),
                    child: text(data.subtitle, muted: true, lines: 2)),
              ],
            ]),
    };
    return Container(
      key: const ValueKey('forward-message-preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.s4),
      decoration: BoxDecoration(
          color: AppTokens.surfaceAlt(dark: dark),
          borderRadius: BorderRadius.circular(AppTokens.rSm)),
      child: content,
    );
  }

  static String _duration(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _ForwardThumbnail extends StatelessWidget {
  const _ForwardThumbnail({required this.data});
  final ForwardPreviewData data;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
        child: Icon(
            data.kind == ForwardPreviewKind.video
                ? Icons.videocam_outlined
                : data.kind == ForwardPreviewKind.sticker
                    ? Icons.emoji_emotions_outlined
                    : Icons.image_outlined,
            color: AppTokens.textSecondary(
                dark: Theme.of(context).brightness == Brightness.dark),
            size: ForwardDialogTokens.avatar));
    final fit =
        data.kind == ForwardPreviewKind.sticker ? BoxFit.contain : BoxFit.cover;
    Widget remote() {
      final uri = Uri.tryParse(data.imageUrl ?? '');
      if (uri == null ||
          !['https', 'http'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        return fallback;
      }
      return ImageUtil.networkImage(
          url: data.imageUrl!,
          width: ForwardDialogTokens.thumbnail,
          height: ForwardDialogTokens.thumbnail,
          fit: fit,
          cacheWidth: ForwardDialogTokens.thumbnailCacheSize,
          cacheHeight: ForwardDialogTokens.thumbnailCacheSize,
          resizePolicy: ResizeImagePolicy.fit,
          loadingWidget: fallback,
          errorWidget: fallback);
    }

    final path = data.imagePath;
    // FileImage resolves asynchronously; missing sender-local paths fall back
    // to the remote thumbnail without synchronous filesystem calls in build.
    final image = path == null || path.trim().isEmpty
        ? remote()
        : Image(
            image: ResizeImage(FileImage(File(path)),
                width: ForwardDialogTokens.thumbnailCacheSize,
                height: ForwardDialogTokens.thumbnailCacheSize,
                policy: ResizeImagePolicy.fit),
            fit: fit,
            errorBuilder: (_, __, ___) => remote());
    return ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.rSm),
        child: Semantics(label: data.title, image: true, child: image));
  }
}
