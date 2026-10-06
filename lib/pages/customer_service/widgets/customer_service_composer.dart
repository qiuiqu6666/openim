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
    return LiquidGlassSurface(
      surface: NavigationGlassSurface.bottom,
      tint: CustomerServiceTokens.surface(context),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s3),
        child: Row(children: [
          IconButton(
            key: const ValueKey('customer-service-attach'),
            tooltip: zh ? '图片或视频' : 'Photo or video',
            onPressed: enabled ? onAttach : null,
            color: CustomerServiceTokens.text(context),
            icon: const Icon(Icons.add_rounded),
          ),
          Expanded(
            child: TextField(
              key: const ValueKey('customer-service-input'),
              controller: controller,
              enabled: enabled,
              textInputAction: TextInputAction.send,
              onSubmitted: enabled ? (_) => onSend() : null,
              style: TextStyle(
                  color: CustomerServiceTokens.text(context),
                  fontSize: CustomerServiceTokens.faqFontSize),
              decoration: InputDecoration(
                hintText: zh ? '请输入您的问题，将会转接人工在线客服' : 'Type your question',
                hintStyle: TextStyle(
                    color: CustomerServiceTokens.secondaryText(context),
                    fontSize: CustomerServiceTokens.faqFontSize),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.s4, vertical: AppTokens.s4),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.rPill),
                    borderSide: BorderSide(
                        color: CustomerServiceTokens.border(context))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.rPill),
                    borderSide: BorderSide(
                        color: CustomerServiceTokens.border(context))),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s2),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) => IconButton.filled(
              key: const ValueKey('customer-service-send'),
              tooltip: zh ? '发送' : 'Send',
              onPressed:
                  enabled && value.text.trim().isNotEmpty ? onSend : null,
              style: IconButton.styleFrom(
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
