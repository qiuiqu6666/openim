import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:path_provider/path_provider.dart';

/// Local-only chat-background persistence.
///
/// Resolution order mirrors 99chat: conversation override -> global default ->
/// system/default chat background. No backend is involved.
class ChatBackgroundLocalService {
  ChatBackgroundLocalService._();

  static const String globalConversationId = 'global_chat_background';
  static const String colorPrefix = 'color:';
  static const String assetPrefix = 'asset:';
  static const String filePrefix = 'file:';

  static String? direct(String conversationId) {
    final id = conversationId.trim();
    if (id.isEmpty) return null;
    return normalize(DataSp.getChatBackground(id));
  }

  static String? global() => direct(globalConversationId);

  static String? effective(String conversationId) {
    final id = conversationId.trim();
    if (id.isEmpty || id == globalConversationId) return global();
    return direct(id) ?? global();
  }

  static String? normalize(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value.startsWith(colorPrefix) ||
        value.startsWith(assetPrefix) ||
        value.startsWith(filePrefix)) {
      return value;
    }
    // Backward compatibility with the original OpenIM implementation that
    // stored a raw local file path.
    return '$filePrefix$value';
  }

  static Color? colorOf(String? value) {
    final normalized = normalize(value);
    if (normalized == null || !normalized.startsWith(colorPrefix)) return null;
    var hex = normalized.substring(colorPrefix.length).replaceAll('#', '');
    if (hex.length == 6) hex = 'ff$hex';
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }

  static String? assetOf(String? value) {
    final normalized = normalize(value);
    if (normalized == null || !normalized.startsWith(assetPrefix)) return null;
    final asset = normalized.substring(assetPrefix.length).trim();
    return asset.isEmpty ? null : asset;
  }

  static String? fileOf(String? value) {
    final normalized = normalize(value);
    if (normalized == null || !normalized.startsWith(filePrefix)) return null;
    final path = normalized.substring(filePrefix.length).trim();
    return path.isEmpty ? null : path;
  }

  static Future<bool> isUsable(String? value) async {
    final normalized = normalize(value);
    if (normalized == null) return false;
    final file = fileOf(normalized);
    if (file == null) return true;
    try {
      return await File(file).exists();
    } on FileSystemException {
      return false;
    }
  }

  static Future<void> saveValue(String conversationId, String value) async {
    final id = conversationId.trim();
    final normalized = normalize(value);
    if (id.isEmpty || normalized == null) return;
    await _deleteOwnedPreviousFile(id, except: fileOf(normalized));
    final future = DataSp.putChatBackground(id, normalized);
    if (future != null) await future;
  }

  static Future<String> saveGalleryBytes(
    String conversationId,
    Uint8List bytes,
  ) async {
    final id = conversationId.trim();
    if (id.isEmpty) throw ArgumentError('conversationId must not be empty');
    final support = await getApplicationSupportDirectory();
    final dir = Directory(
      '${support.path}${Platform.pathSeparator}chat_backgrounds',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File(
      '${dir.path}/chat_background_${safeId}_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    final value = '$filePrefix${file.path}';
    await saveValue(id, value);
    return value;
  }

  static Future<void> clear(String conversationId) async {
    final id = conversationId.trim();
    if (id.isEmpty) return;
    await _deleteOwnedPreviousFile(id);
    final future = DataSp.clearChatBackground(id);
    if (future != null) await future;
  }

  static Future<void> _deleteOwnedPreviousFile(
    String conversationId, {
    String? except,
  }) async {
    final previous = fileOf(direct(conversationId));
    if (previous == null || previous == except) return;
    final file = File(previous);
    if (!file.parent.path.endsWith(
      '${Platform.pathSeparator}chat_backgrounds',
    )) {
      return;
    }
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Cache cleanup failure must not block changing a local background.
    }
  }
}
