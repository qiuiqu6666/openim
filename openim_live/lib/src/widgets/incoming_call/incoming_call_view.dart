import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../models/call_types.dart';
import '../call_surface/call_full_screen_surface.dart';
import '../live_button.dart';
import 'incoming_call_background.dart';
import 'incoming_call_tokens.dart';

/// The 99chat full-screen invitation chrome. Session, deadline, permissions and
/// signaling remain owned by SignalState / SingleCallSession.
class IncomingCallView extends StatefulWidget {
  const IncomingCallView({
    super.key,
    required this.userID,
    this.userInfo,
    required this.callType,
    this.onAccept,
    this.onReject,
    this.onMinimize,
  });

  final String userID;
  final UserInfo? userInfo;
  final CallType callType;
  final VoidCallback? onAccept, onReject, onMinimize;

  @override
  State<IncomingCallView> createState() => _IncomingCallViewState();
}

class _IncomingCallViewState extends State<IncomingCallView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry;
  late final CurvedAnimation _opacity;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: IncomingCallTokens.enterDuration,
    )..forward();
    _opacity = CurvedAnimation(parent: _entry, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _opacity.dispose();
    _entry.dispose();
    super.dispose();
  }

  String _hint(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final video = widget.callType == CallType.video;
    if (locale.languageCode == 'zh') {
      final traditional = locale.scriptCode == 'Hant' ||
          locale.countryCode == 'TW' ||
          locale.countryCode == 'HK';
      if (traditional) return video ? '邀請你視訊通話' : '邀請你語音通話';
      return video ? '邀请你视频通话' : '邀请你语音通话';
    }
    return video
        ? 'Invites you to a video call'
        : 'Invites you to a voice call';
  }

  @override
  Widget build(BuildContext context) => ContactNameBuilder(
        userID: widget.userInfo?.userID ?? widget.userID,
        nickname: widget.userInfo?.nickname,
        fallbackRemark: widget.userInfo?.remark,
        builder: _build,
      );

  Widget _build(BuildContext context, String name) {
    final padding = MediaQuery.paddingOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    final bottom = math.max(IncomingCallTokens.actionBottom, padding.bottom);
    // Keep the reference positions on normal phones. Short/landscape screens
    // and large text get a scrollable canvas rather than overlapping actions.
    final minHeight = math.max(
      (IncomingCallTokens.avatarSize +
              IncomingCallTokens.nameGap +
              scaler.scale(IncomingCallTokens.nameStyle.fontSize!) * 2.4 +
              IncomingCallTokens.sideInset) *
          2.4,
      (bottom +
              IncomingCallTokens.actionIconSize +
              IncomingCallTokens.actionGap +
              scaler.scale(IncomingCallTokens.actionStyle.fontSize!) * 2.5 +
              IncomingCallTokens.sideInset) *
          3,
    );
    return Stack(fit: StackFit.expand, children: [
      IncomingCallBackground(
        faceURL: widget.userInfo?.faceURL,
        isVideo: widget.callType == CallType.video,
      ),
      FadeTransition(
        opacity: MediaQuery.disableAnimationsOf(context)
            ? const AlwaysStoppedAnimation(1)
            : _opacity,
        child: LayoutBuilder(builder: (context, constraints) {
          final height = math.max(constraints.maxHeight, minHeight);
          return SingleChildScrollView(
            child: SizedBox(
              height: height,
              child: Stack(children: [
                Positioned(
                  left: IncomingCallTokens.minimizeLeft,
                  top: math.max(IncomingCallTokens.minimizeTop, padding.top),
                  child: IconButton(
                    tooltip:
                        Localizations.localeOf(context).languageCode == 'zh'
                            ? '最小化'
                            : 'Minimize',
                    onPressed: widget.onMinimize,
                    padding: const EdgeInsets.all(
                        IncomingCallTokens.minimizePadding),
                    constraints:
                        const BoxConstraints.tightFor(width: 44, height: 44),
                    icon: ImageUtil.assetImage(ImageRes.liveMinimize,
                        width: IncomingCallTokens.minimizeIconSize,
                        height: IncomingCallTokens.minimizeIconSize),
                  ),
                ),
                Positioned(
                  top: height / 4,
                  left: IncomingCallTokens.sideInset,
                  right: IncomingCallTokens.sideInset,
                  child: Column(children: [
                    AvatarView(
                      width: IncomingCallTokens.avatarSize,
                      height: IncomingCallTokens.avatarSize,
                      url: widget.userInfo?.faceURL,
                      text: name,
                    ),
                    const SizedBox(height: IncomingCallTokens.nameGap),
                    Text(name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: IncomingCallTokens.nameStyle),
                  ]),
                ),
                Positioned(
                  top: height * 2 / 3,
                  left: IncomingCallTokens.sideInset,
                  right: IncomingCallTokens.sideInset,
                  child: Text(_hint(context),
                      textAlign: TextAlign.center,
                      style: IncomingCallTokens.hintStyle),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottom,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _action(
                          StrRes.hangUp, ImageRes.liveHangUp, widget.onReject),
                      _action(
                          StrRes.pickUp, ImageRes.livePicUp, widget.onAccept),
                    ],
                  ),
                ),
              ]),
            ),
          );
        }),
      ),
    ]);
  }

  Widget _action(String label, String icon, VoidCallback? onTap) => LiveButton(
        text: label,
        icon: icon,
        onTap: onTap,
        foreground: CallSurfaceTokens.foreground,
        iconSize: IncomingCallTokens.actionIconSize,
        labelWidth: IncomingCallTokens.actionWidth,
        labelStyle: IncomingCallTokens.actionStyle,
        labelSpacing: IncomingCallTokens.actionGap,
        contentPadding: EdgeInsets.zero,
      );
}
