import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

const _stickerVideoKey = '99chatStickerVideo';

bool isStickerVideoMessage(Message message) {
  if (message.contentType != MessageType.video) return false;
  if (message.exMap[_stickerVideoKey] == true) return true;
  final ex = message.ex;
  if (ex == null || ex.isEmpty) return false;
  try {
    final data = jsonDecode(ex);
    return data is Map && data[_stickerVideoKey] == true;
  } catch (_) {
    return false;
  }
}

void markStickerVideoMessage(Message message) {
  message.exMap = {...message.exMap, _stickerVideoKey: true};
  message.ex = jsonEncode({_stickerVideoKey: true});
}
