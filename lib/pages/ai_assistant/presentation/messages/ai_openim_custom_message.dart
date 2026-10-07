import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../localization/ai_assistant_i18n.dart';
import '../../theme/ai_palette.dart';

/// Shared, passive presentation of assistant tool messages.
CustomTypeInfo? buildAiOpenIMCustomMessage(
    BuildContext context, Message message) {
  final custom = message.customElem;
  if (custom == null || !['image', 'groupCard'].contains(custom.description)) {
    return null;
  }
  dynamic data = custom.data;
  try {
    data = jsonDecode(custom.data ?? '');
  } on FormatException {
    // The image prompt is also allowed to be a plain string.
  }
  if (data is String) {
    try {
      data = jsonDecode(data);
    } on FormatException {
      // Keep the prompt string.
    }
  }
  final i18n = AiAssistantI18n.of(context);
  final isImage = custom.description == 'image';
  final title = isImage
      ? i18n.t(zhHans: '生成图片', en: 'Generate image')
      : i18n.t(zhHans: '总结群聊', en: 'Summarize group chat');
  final detail = isImage
      ? (data is Map ? data['prompt']?.toString() ?? '' : data.toString())
      : (data is Map
          ? (data['groupName'] ?? data['groupID'] ?? '').toString()
          : '');
  final dark = Theme.of(context).brightness == Brightness.dark;
  return CustomTypeInfo(Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(isImage ? Icons.image_outlined : Icons.notes_outlined,
            size: AiMetrics.dimension18, color: AiPalette.brand(dark)),
        const SizedBox(width: AiMetrics.space8),
        Flexible(
            child: Text(title,
                style: TextStyle(
                    color: AiPalette.primary(dark),
                    fontSize: AiMetrics.font14,
                    fontWeight: FontWeight.w600))),
      ]),
      if (detail.isNotEmpty) ...[
        const SizedBox(height: AiMetrics.space8),
        Text(detail,
            style: TextStyle(
                color: AiPalette.primary(dark),
                fontSize: AiMetrics.font14,
                height: AiMetrics.textLineHeight)),
      ],
    ],
  ));
}
