import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_entry_loading_tokens.dart';

/// Presentation only: shares the real bubble geometry without inventing SDK
/// messages, avatars, text, or readable message identities.
class ChatEntrySkeleton extends StatefulWidget {
  const ChatEntrySkeleton({
    super.key,
    required this.isGroup,
    this.latestOutgoing = false,
    this.latestIsMedia = false,
  });

  final bool isGroup;
  final bool latestOutgoing;
  final bool latestIsMedia;

  @override
  State<ChatEntrySkeleton> createState() => _ChatEntrySkeletonState();
}

class _ChatEntrySkeletonState extends State<ChatEntrySkeleton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
      vsync: this, duration: ChatEntryLoadingTokens.pulseDuration);
  late final _opacity = _pulse
      .drive(Tween(begin: ChatEntryLoadingTokens.minPulseOpacity, end: 1.0));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animate && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!animate) {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'chatHistoryLoading'.tr,
        child: ExcludeSemantics(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: FadeTransition(
                opacity: _opacity,
                child: LayoutBuilder(builder: (context, constraints) {
                  final count = (constraints.maxHeight /
                          ChatEntryLoadingTokens.rowEstimate)
                      .ceil()
                      .clamp(3, ChatEntryLoadingTokens.maxRows);
                  return ClipRect(
                    child: SingleChildScrollView(
                      reverse: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.only(top: AppTokens.s4),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        for (var i = 0; i < count; i++) ...[
                          if (i == 0 || i == count - 3)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppTokens.s3),
                              child: _Bone(
                                  width: ChatEntryLoadingTokens.dateWidth,
                                  height: ChatBubbleTokens.metadataFontSize),
                            ),
                          _SkeletonRow(
                            outgoing: i == count - 1
                                ? widget.latestOutgoing
                                : !widget.isGroup && i % 3 == 1,
                            group: widget.isGroup,
                            lines: i % 3 + 1,
                            media: i == count - 1 && widget.latestIsMedia,
                          ),
                        ],
                      ]),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      );
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow(
      {required this.outgoing,
      required this.group,
      required this.lines,
      required this.media});
  final bool outgoing;
  final bool group;
  final int lines;
  final bool media;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(ChatEntryLoadingTokens.rowInset.w, 0,
            ChatEntryLoadingTokens.rowInset.w, AppTokens.s4),
        child: LayoutBuilder(builder: (context, constraints) {
          final avatar = ChatEntryLoadingTokens.avatarExtent.w;
          final gap = ChatEntryLoadingTokens.avatarGap.w;
          final available =
              constraints.maxWidth - (outgoing ? 0 : avatar + gap);
          final maxBubble = ChatBubbleTokens.maxWidth(constraints.maxWidth);
          final width = (maxBubble * (media ? 1 : [.64, .92, .82][lines - 1]))
              .clamp(0.0, available);
          final lineHeight = (MediaQuery.textScalerOf(context)
                      .scale(ChatBubbleTokens.textFontSize) *
                  ChatEntryLoadingTokens.lineHeightRatio)
              .clamp(ChatEntryLoadingTokens.minLineHeight,
                  ChatEntryLoadingTokens.maxLineHeight);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment:
                outgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!outgoing) ...[
                _Bone(width: avatar, height: avatar, circle: true),
                SizedBox(width: gap),
              ],
              Flexible(
                  child: Column(
                crossAxisAlignment: outgoing
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (group && !outgoing) ...[
                    _Bone(
                        width: ChatEntryLoadingTokens.nameWidth.clamp(0, width),
                        height: lineHeight),
                    const SizedBox(height: AppTokens.s2),
                  ],
                  SizedBox(
                      width: width,
                      child: ChatBubble(
                        backgroundColor:
                            ChatEntryLoadingTokens.bubbleFill(context),
                        bubbleType:
                            outgoing ? BubbleType.send : BubbleType.receiver,
                        child: LayoutBuilder(
                            builder: (context, bubble) => Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (media)
                                      AspectRatio(
                                          aspectRatio: ChatEntryLoadingTokens
                                              .mediaAspectRatio,
                                          child: _Bone(
                                              width: bubble.maxWidth,
                                              height: double.infinity))
                                    else
                                      for (var line = 0;
                                          line < lines;
                                          line++) ...[
                                        if (line != 0)
                                          const SizedBox(height: AppTokens.s3),
                                        _Bone(
                                            width: bubble.maxWidth *
                                                (line == lines - 1 ? .66 : 1),
                                            height: lineHeight),
                                      ],
                                    const SizedBox(
                                        height: ChatBubbleTokens
                                            .metadataVerticalGap),
                                    Align(
                                        alignment: Alignment.centerRight,
                                        child: _Bone(
                                            width: ChatEntryLoadingTokens
                                                .timeWidth
                                                .clamp(0, bubble.maxWidth),
                                            height: ChatBubbleTokens
                                                    .metadataFontSize *
                                                ChatEntryLoadingTokens
                                                    .lineHeightRatio)),
                                  ],
                                )),
                      )),
                ],
              )),
            ],
          );
        }),
      );
}

class _Bone extends StatelessWidget {
  const _Bone({required this.width, required this.height, this.circle = false});
  final double width;
  final double height;
  final bool circle;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
            decoration: BoxDecoration(
          color: ChatEntryLoadingTokens.fill(context),
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : ChatEntryLoadingTokens.lineRadius,
        )),
      );
}
