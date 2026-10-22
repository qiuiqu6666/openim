import 'chat_background_reference_tokens.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../chat_background_local_service.dart';
import '../../widgets/settings_widgets.dart';

class ChatBackgroundPreview extends StatelessWidget {
  const ChatBackgroundPreview(
      {super.key,
      required this.value,
      required this.allChats,
      required this.hasOverride,
      this.height = ChatBackgroundReferenceTokens.previewHeight,
      this.margin = ChatBackgroundReferenceTokens.sectionMargin});
  final String? value;
  final bool allChats, hasOverride;
  final double? height;
  final EdgeInsetsGeometry margin;
  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final badge = allChats
        ? settingsText(context, zh: '全局默认预览', en: 'Global default preview')
        : hasOverride
            ? settingsText(context, zh: '本聊天专属预览', en: 'This chat preview')
            : settingsText(context, zh: '继承全局默认', en: 'Using global default');

    return Container(
      width: double.infinity,
      height: height == null
          ? null
          : height! * MediaQuery.textScalerOf(context).scale(14) / 14,
      margin: margin,
      decoration: BoxDecoration(
        color: AppTokens.surface(dark: dark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppTokens.border(dark: dark),
            width: ChatBackgroundReferenceTokens.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _backgroundWidget(value, dark),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.04),
                  Colors.black.withValues(alpha: 0.14),
                ],
              ),
            ),
          ),
          Positioned(
            left: AppTokens.s4,
            top: AppTokens.s4,
            child: Container(
              padding: ChatBackgroundReferenceTokens.badgePadding,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  color: AppTokens.onAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Positioned(
            right: AppTokens.s5,
            top: 44,
            child: _bubble(
              text: settingsText(context,
                  zh: '你好，今晚见面聊', en: 'Hi, let’s talk tonight.'),
              self: true,
              dark: dark,
            ),
          ),
          Positioned(
            left: AppTokens.s5,
            bottom: AppTokens.s5,
            child: _bubble(
              text: settingsText(
                context,
                zh: '这里会显示当前聊天背景效果',
                en: 'Preview of the chat background.',
              ),
              self: false,
              dark: dark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _backgroundWidget(String? value, bool dark) {
    final color = ChatBackgroundLocalService.colorOf(value);
    if (color != null) return ColoredBox(color: color);
    final asset = ChatBackgroundLocalService.assetOf(value);
    if (asset != null) {
      return Image.asset(
        asset,
        package: 'openim_common',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _defaultBackground(dark),
      );
    }
    final file = ChatBackgroundLocalService.fileOf(value);
    if (file != null) {
      return Image.file(
        File(file),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _defaultBackground(dark),
      );
    }
    return _defaultBackground(dark);
  }

  Widget _defaultBackground(bool dark) => ColoredBox(
      color: dark
          ? ChatBackgroundReferenceTokens.previewDark
          : ChatBackgroundReferenceTokens.previewLight);

  Widget _bubble({
    required String text,
    required bool self,
    required bool dark,
  }) =>
      Container(
        constraints: const BoxConstraints(
            maxWidth: ChatBackgroundReferenceTokens.bubbleWidth),
        padding: ChatBackgroundReferenceTokens.bubblePadding,
        decoration: BoxDecoration(
          color: self
              ? ChatBackgroundReferenceTokens.bubbleSelf
              : (dark
                  ? ChatBackgroundReferenceTokens.bubblePeerDark
                  : AppTokens.onAccent),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: TextStyle(
            color:
                self ? AppTokens.onAccent : AppTokens.textPrimary(dark: dark),
            fontSize: AppTokens.captionFontSize,
          ),
        ),
      );
}
