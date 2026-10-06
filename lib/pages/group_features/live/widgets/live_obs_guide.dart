import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'live_style.dart';

/// 99chat's showGroupLiveObsGuideSheet, using its unmodified tutorial artwork.
Future<void> showLiveObsGuide(BuildContext context, {String? hint}) {
  final size = MediaQuery.sizeOf(context);
  final nativeDesktop = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);
  final desktop = nativeDesktop ||
      size.width > 900 ||
      (kIsWeb && size.width > size.height * 1.1);
  if (desktop) {
    return showDialog<void>(
        context: context,
        barrierColor: LiveStyle.screen.withValues(alpha: .28),
        builder: (_) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(AppTokens.s7),
            child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: LiveStyle.guideDesktopWidth,
                    maxHeight:
                        size.height * LiveStyle.guideDesktopHeightFactor),
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(LiveStyle.guideRadius),
                    child: const Material(
                        color: Colors.transparent,
                        child: LiveObsGuideSheet())))));
  }
  return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LiveObsGuideSheet());
}

class LiveObsGuideSheet extends StatelessWidget {
  const LiveObsGuideSheet({super.key});

  @override
  Widget build(BuildContext context) => Container(
      constraints: BoxConstraints(
          maxHeight:
              MediaQuery.heightOf(context) * LiveStyle.guideHeightFactor),
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(LiveStyle.guideRadius)),
          image: DecorationImage(
              image: AssetImage(LiveStyle.backgroundAsset), fit: BoxFit.cover)),
      child: SafeArea(
          top: false,
          child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppTokens.s5, AppTokens.s3, AppTokens.s5, AppTokens.s5),
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Center(
                        child: Container(
                            width: LiveStyle.guideHandleWidth,
                            height: LiveStyle.guideHandleHeight,
                            decoration: BoxDecoration(
                                color: LiveStyle.guideHandle(context),
                                borderRadius: BorderRadius.circular(
                                    LiveStyle.guideHandleHeight / 2)))),
                    const SizedBox(height: AppTokens.s4),
                    AspectRatio(
                        aspectRatio: LiveStyle.guideImageAspect,
                        child: Image.asset(LiveStyle.guideAsset,
                            width: double.infinity,
                            fit: BoxFit.contain,
                            semanticLabel:
                                '直播教程：下载芯象，填写完整推流地址，设置推荐参数，开始与结束直播。')),
                    const SizedBox(height: AppTokens.s5),
                    LivePrimaryButton(
                        label: switch (
                            Localizations.localeOf(context).languageCode) {
                          'en' => 'Got it',
                          'ja' => '了解',
                          'ko' => '확인',
                          _ => '我知道了'
                        },
                        height: LiveStyle.guideButtonHeight,
                        radius: LiveStyle.guideButtonRadius,
                        onPressed: () => Navigator.pop(context))
                  ])))));
}
