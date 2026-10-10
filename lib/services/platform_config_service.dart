import 'dart:io';
import 'package:dio/dio.dart';
import 'package:openim_common/openim_common.dart';

class PlatformRelease {
  PlatformRelease(Map<String, dynamic> data)
      : latest = (data['latestVersion'] as String? ?? '').trim().isNotEmpty
            ? (data['latestVersion'] as String).trim()
            : (data['version'] as String? ?? '').trim(),
        minimum = (data['minVersion'] as String? ?? '').trim(),
        grayRatio = ((data['grayRatio'] as num? ?? 0).toInt()).clamp(0, 100),
        downloadURL = (data['downloadURL'] as String? ?? '').trim(),
        downloadLink = (data['downloadLink'] as String? ?? '').trim();
  final String latest, minimum, downloadURL, downloadLink;
  final int grayRatio;
  String get installURL => downloadLink.isNotEmpty ? downloadLink : downloadURL;
  String get shareURL => downloadURL.isNotEmpty ? downloadURL : downloadLink;
}

class PlatformConfig {
  PlatformConfig(Map<String, dynamic> data)
      : officialURL = (data['officialURL'] as String? ?? '').trim(),
        email = (data['email'] as String? ?? '').trim(),
        android = PlatformRelease(
            Map<String, dynamic>.from(data['android'] as Map? ?? {})),
        ios = PlatformRelease(
            Map<String, dynamic>.from(data['ios'] as Map? ?? {}));
  final String officialURL, email;
  final PlatformRelease android, ios;
  PlatformRelease get release => Platform.isIOS ? ios : android;
}

class PlatformConfigService {
  static Future<PlatformConfig> fetch({Dio? client}) async {
    // Dedicated public client: no account token or authenticated interceptors.
    final http = client ??
        Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10)));
    try {
      final response = await http.get<Map<String, dynamic>>(
          '${Config.appAuthUrl}/chat/platform',
          options: Options(headers: {'operationID': HttpUtil.operationID}));
      final body = response.data;
      if (body == null || body['errCode'] != 0 || body['data'] is! Map) {
        throw StateError('平台配置获取失败');
      }
      return PlatformConfig(Map<String, dynamic>.from(body['data']));
    } finally {
      if (client == null) http.close();
    }
  }
}

int compareAppVersions(String a, String b) {
  List<int> parts(String value) => value
      .trim()
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split('+')
      .first
      .split('-')
      .first
      .split('.')
      .map((s) => int.tryParse(s) ?? 0)
      .toList();
  final left = parts(a), right = parts(b);
  for (var i = 0;
      i < (left.length > right.length ? left.length : right.length);
      i++) {
    final result = (i < left.length ? left[i] : 0)
        .compareTo(i < right.length ? right[i] : 0);
    if (result != 0) return result;
  }
  // Old configuration without a build number compares the release only.
  // When both sides include a build, a newer build is an actual update.
  int? build(String value) {
    final segments = value.trim().split('+');
    return segments.length == 2 ? int.tryParse(segments.last) : null;
  }

  final leftBuild = build(a), rightBuild = build(b);
  return leftBuild != null && rightBuild != null
      ? leftBuild.compareTo(rightBuild)
      : 0;
}
