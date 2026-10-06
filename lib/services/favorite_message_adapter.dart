import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:uuid/uuid.dart';

import 'favorite_models.dart';

/// Describes a source for the server to authorize; never manufactures provenance.
class FavoriteMessageAdapter {
  FavoriteMessageAdapter._();

  static bool canFavorite(Message message, {bool revoked = false}) {
    if (revoked ||
        !_validLocator(message.clientMsgID) ||
        (message.seq ?? 0) <= 0 ||
        message.status != MessageStatus.succeeded ||
        message.attachedInfoElem?.isPrivateChat == true ||
        (message.attachedInfoElem?.burnDuration ?? 0) > 0) {
      return false;
    }
    // Some persisted SDK messages have only the serialized attachedInfo field.
    final serialized = message.attachedInfo;
    if (serialized != null && serialized.trim().isNotEmpty) {
      try {
        final raw = jsonDecode(serialized);
        if (raw is! Map<String, dynamic>) return false;
        final info = AttachedInfoElem.fromJson(raw);
        if (info.isPrivateChat == true || (info.burnDuration ?? 0) > 0) {
          return false;
        }
      } catch (_) {
        return false;
      }
    }
    switch (message.contentType) {
      case MessageType.text:
      case MessageType.atText:
      case MessageType.quote:
      case MessageType.advancedText:
        return readableText(message).trim().isNotEmpty;
      case MessageType.picture:
        return message.pictureElem != null;
      case MessageType.voice:
        return message.soundElem != null;
      case MessageType.video:
        return message.videoElem != null;
      case MessageType.file:
        return message.fileElem != null;
      default:
        // Financial/custom/control, notices and merged protocols require their
        // own server-approved schema; forwarding eligibility is not authority.
        return false;
    }
  }

  static String readableText(Message message) {
    switch (message.contentType) {
      case MessageType.atText:
        return message.atTextElem?.text ?? '';
      case MessageType.quote:
        return message.quoteElem?.text ?? '';
      case MessageType.advancedText:
        return message.advancedTextElem?.text ?? '';
      default:
        return message.textElem?.content ?? '';
    }
  }

  static FavoriteSource sourceForMessage(Message message,
      {required String conversationID}) {
    if (!canFavorite(message) || !_validLocator(conversationID)) {
      throw const FormatException('该消息暂不支持收藏');
    }
    return FavoriteSource(
      conversationID: conversationID,
      clientMsgID: message.clientMsgID!,
      sequence: message.seq,
    );
  }

  static Map<String, dynamic> createRequest(Message message,
          {required String conversationID, String? clientRequestID}) =>
      <String, dynamic>{
        'clientRequestID': clientRequestID ?? const Uuid().v4(),
        'origin': 'message',
        'source':
            sourceForMessage(message, conversationID: conversationID).toJson(),
      };

  static bool _validLocator(String? value) =>
      value != null &&
      value.isNotEmpty &&
      value == value.trim() &&
      value.length <= 512 &&
      !value.contains(RegExp(r'[\r\n\x00]'));
}
