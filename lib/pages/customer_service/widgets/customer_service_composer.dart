import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:openim_common/openim_common.dart';

/// Shares the IM composer's appearance while retaining the support transport.
class CustomerServiceComposer extends StatelessWidget {
  const CustomerServiceComposer({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend, onAttach;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      key: const ValueKey('customer-service-composer'),
      decoration: BoxDecoration(
        color: chatComposerSurface(context),
        border: Border(
          top: BorderSide(
            color: chatComposerDivider(context),
            width: ChatComposerTokens.dividerWidth,
          ),
        ),
      ),
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(minHeight: ChatComposerTokens.barHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ChatComposerTokens.horizontalPadding,
            vertical: ChatComposerTokens.verticalPadding,
          ),
          child: Row(children: [
            IconButton(
              key: const ValueKey('customer-service-attach'),
              tooltip: zh ? AppCopy.text('图片或视频') : 'Photo or video',
              onPressed: enabled ? onAttach : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: kMinInteractiveDimension,
                height: kMinInteractiveDimension,
              ),
              icon: SvgPicture.asset(
                'assets/chat/composer/add.svg',
                package: 'openim_common',
                width: ChatComposerTokens.iconSize,
                height: ChatComposerTokens.iconSize,
                colorFilter: ColorFilter.mode(
                  chatComposerForeground(context)
                      .withValues(alpha: enabled ? 1 : .38),
                  BlendMode.srcIn,
                ),
              ),
            ),
            const SizedBox(width: ChatComposerTokens.actionGap),
            Expanded(
              child: TextField(
                key: const ValueKey('customer-service-input'),
                controller: controller,
                enabled: enabled,
                autocorrect: false,
                cursorColor: ChatComposerTokens.cursor(dark: dark),
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                textAlignVertical: TextAlignVertical.center,
                textInputAction: TextInputAction.send,
                onSubmitted: enabled ? (_) => onSend() : null,
                style: chatComposerTextStyle(context),
                decoration: chatComposerInputDecoration(context,
                    hintText:
                        zh ? AppCopy.text('输入您的问题') : 'Type your question'),
              ),
            ),
            const SizedBox(width: ChatComposerTokens.actionGap),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, value, __) => SizedBox(
                height: ChatComposerTokens.inputHeight,
                child: ElevatedButton(
                  key: const ValueKey('customer-service-send'),
                  onPressed:
                      enabled && value.text.trim().isNotEmpty ? onSend : null,
                  style: chatComposerSendButtonStyle(),
                  child: Text(zh ? AppCopy.text('发送') : 'Send',
                      style: const TextStyle(
                        fontSize: ChatComposerTokens.sendFontSize,
                      )),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
