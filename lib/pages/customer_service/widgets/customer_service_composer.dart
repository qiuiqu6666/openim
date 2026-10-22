import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../customer_service_tokens.dart';

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
    return DecoratedBox(
      key: const ValueKey('customer-service-composer'),
      decoration: BoxDecoration(
        color: CustomerServiceTokens.surface(context),
        border: Border(
            top: BorderSide(color: CustomerServiceTokens.border(context))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s2, vertical: AppTokens.s2),
        child: Row(children: [
          IconButton(
            key: const ValueKey('customer-service-attach'),
            tooltip: zh ? AppCopy.text('图片或视频') : 'Photo or video',
            onPressed: enabled ? onAttach : null,
            color: CustomerServiceTokens.text(context),
            constraints: const BoxConstraints.tightFor(
                width: kMinInteractiveDimension,
                height: kMinInteractiveDimension),
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: AppTokens.s2),
          Expanded(
            child: TextField(
              key: const ValueKey('customer-service-input'),
              controller: controller,
              enabled: enabled,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              textAlignVertical: TextAlignVertical.center,
              textInputAction: TextInputAction.send,
              onSubmitted: enabled ? (_) => onSend() : null,
              style: TextStyle(
                  color: CustomerServiceTokens.text(context),
                  fontSize: CustomerServiceTokens.faqFontSize,
                  height: CustomerServiceTokens.answerLineHeight),
              decoration: InputDecoration(
                constraints:
                    const BoxConstraints(minHeight: kMinInteractiveDimension),
                hintText: zh ? AppCopy.text('输入您的问题') : 'Type your question',
                hintStyle: TextStyle(
                    color: CustomerServiceTokens.secondaryText(context),
                    fontSize: CustomerServiceTokens.faqFontSize),
                isDense: false,
                visualDensity: VisualDensity.standard,
                filled: true,
                fillColor: CustomerServiceTokens.background(context),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.s4, vertical: AppTokens.s3),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.rMd),
                    borderSide: BorderSide(
                        color: CustomerServiceTokens.border(context))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.rMd),
                    borderSide: BorderSide(
                        color: CustomerServiceTokens.border(context))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.rMd),
                    borderSide:
                        const BorderSide(color: CustomerServiceTokens.blue)),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s2),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) => IconButton.filled(
              key: const ValueKey('customer-service-send'),
              tooltip: zh ? AppCopy.text('发送') : 'Send',
              onPressed:
                  enabled && value.text.trim().isNotEmpty ? onSend : null,
              style: IconButton.styleFrom(
                fixedSize: const Size.square(kMinInteractiveDimension),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTokens.rMd)),
                backgroundColor: CustomerServiceTokens.blue,
                foregroundColor: AppTokens.onAccent,
              ),
              icon: const Icon(Icons.send_rounded, size: AppTokens.chevronSize),
            ),
          ),
        ]),
      ),
    );
  }
}
