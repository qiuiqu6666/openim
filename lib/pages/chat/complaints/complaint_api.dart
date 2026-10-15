import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../mine/settings/settings_service.dart';

enum ComplaintReason {
  spam('垃圾信息', 'Spam'),
  harassment('骚扰辱骂', 'Harassment'),
  fraud('诈骗', 'Fraud'),
  pornography('色情低俗', 'Pornography'),
  violence('暴力威胁', 'Violence / Threats'),
  illegal('违法违规', 'Illegal activity'),
  other('其他', 'Other');

  const ComplaintReason(this.zh, this.en);
  final String zh, en;
}

class ComplaintApi {
  ComplaintApi({Dio? client})
      : _client = client ?? dio,
        _owner = OpenIM.iMManager.userID,
        _token = DataSp.chatToken;
  final Dio _client;
  final String _owner;
  final String? _token;
  bool get isActive =>
      _owner == OpenIM.iMManager.userID &&
      _token != null &&
      _token == DataSp.chatToken;

  Future<String> submit(
      {required String requestID,
      required String reportedUserID,
      required ComplaintReason reason,
      required String content,
      required List<SettingsFeedbackAttachment> attachments,
      String? groupID}) async {
    if (!isActive) throw StateError('Account session changed');
    if (attachments.length > 5 || content.characters.length > 2000) {
      throw ArgumentError('Invalid complaint');
    }
    var version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    final form = FormData.fromMap({
      'payload': jsonEncode({
        'clientRequestID': requestID,
        'reportedUserID': reportedUserID,
        'groupID': groupID ?? '',
        'reason': reason.name,
        'content': content.trim(),
        'clientVersion': version,
      })
    });
    for (final file in attachments) {
      if (file.bytes.isEmpty || file.bytes.length > 10 * 1024 * 1024) {
        throw ArgumentError('Invalid screenshot');
      }
      form.files.add(MapEntry('screenshots',
          MultipartFile.fromBytes(file.bytes, filename: file.filename)));
    }
    if (!isActive) throw StateError('Account session changed');
    final response = await _client.post<Map<String, dynamic>>(
        '${Config.appAuthUrl}/complaints/${groupID == null ? 'c2c' : 'group'}',
        data: form,
        options: Options(
            headers: {'token': _token, 'operationID': requestID},
            sendTimeout: const Duration(seconds: 60),
            receiveTimeout: const Duration(seconds: 60)));
    if (!isActive) throw StateError('Account session changed');
    final result = ApiResp.fromJson(response.data ?? {});
    if (result.errCode != 0) throw (result.errCode, result.errMsg);
    final id = result.data is Map ? result.data['complaintID'] : null;
    if (id is! String || !id.startsWith('cp_')) {
      throw const FormatException('Invalid complaint response');
    }
    return id;
  }
}
