import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide FormData, MultipartFile;
import 'package:uuid/uuid.dart';
import '../../../routes/app_navigator.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:path/path.dart' as p;
import '../../../core/controller/im_controller.dart';
import 'settings_service.dart';
import 'verification_code_result.dart';

/// Profile and account security use the current Chat service.
class OpenIMProfileService extends StubSettingsService {
  OpenIMProfileService(this.controller);
  final IMController controller;
  @override
  bool get supportsFriendPermissions => true;
  @override
  bool get supportsPresenceVisibility => true;
  @override
  Future<Map<String, int>> getFriendPermissions() async {
    final info = await Apis.queryMyFullInfo();
    if (info == null) throw StateError('Friend permissions unavailable');
    return {
      'allowAddFriend': info.allowAddFriend ?? 1,
      'allowAddByQRCode': info.allowAddByQRCode ?? 1,
      'allowAddByCard': info.allowAddByCard ?? 1,
      'allowAddByGroup': info.allowAddByGroup ?? 1,
      'allowAddByPhone': info.allowAddByPhone ?? 1,
      'allowAddByUserID': info.allowAddByUserID ?? 1,
      'allowAddByAccount': info.allowAddByAccount ?? 1,
      'allowAddByEmail': info.allowAddByEmail ?? 1,
    };
  }

  @override
  Future<void> updateAllowAddFriend(bool allowed) async {
    await Apis.updateFriendAddPermission(
        userID: OpenIM.iMManager.userID,
        field: 'allowAddFriend',
        value: allowed ? 1 : 0);
    if (!controller.isClosed) {
      controller.userInfo
          .update((user) => user?.allowAddFriend = allowed ? 1 : 0);
    }
  }

  @override
  Future<void> updateFriendDiscovery(
      {bool? qrCode,
      bool? businessCard,
      bool? group,
      bool? phone,
      bool? uid,
      bool? account,
      bool? email}) async {
    final updates = {
      'allowAddByQRCode': qrCode,
      'allowAddByCard': businessCard,
      'allowAddByGroup': group,
      'allowAddByPhone': phone,
      'allowAddByUserID': uid,
      'allowAddByAccount': account,
      'allowAddByEmail': email
    };
    for (final entry in updates.entries) {
      if (entry.value != null) {
        await Apis.updateFriendAddPermission(
            userID: OpenIM.iMManager.userID,
            field: entry.key,
            value: entry.value! ? 1 : 2);
      }
    }
  }

  @override
  bool get isProfileBackendAvailable => true;

  @override
  bool get supportsNicknameCheck => true;
  @override
  Future<NicknameCheckResult> checkNickname(String nickname) async =>
      NicknameCheckResult.fromJson(await Apis.checkNickname(nickname));

  @override
  bool get isSecurityBackendAvailable => true;
  @override
  String get securityPhone => controller.userInfo.value.phoneNumber ?? '';
  @override
  String get securityAreaCode {
    final code = controller.userInfo.value.areaCode ?? '';
    return code.isEmpty ? '+86' : (code.startsWith('+') ? code : '+$code');
  }

  @override
  Future<void> refreshSecurity() async {
    final info = await Apis.queryMyFullInfo();
    if (info == null) throw StateError('Could not load account');
    if (controller.isClosed) return;
    controller.userInfo.update((user) {
      user?.phoneNumber = info.phoneNumber;
      user?.areaCode = info.areaCode;
    });
  }

  @override
  bool get supportsFeedback => true;
  @override
  Future<String> createFeedback(
      {required String clientRequestID,
      required String type,
      required String content,
      required List<SettingsFeedbackAttachment> attachments,
      required bool includeSDKLogs}) async {
    var deviceName = '';
    var version = '';
    try {
      final info = await DeviceInfoPlugin().deviceInfo;
      if (info is AndroidDeviceInfo) {
        deviceName = '${info.manufacturer} ${info.model}';
      }
      if (info is IosDeviceInfo) deviceName = info.name;
      if (info is WindowsDeviceInfo) deviceName = info.computerName;
    } catch (_) {}
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    final platform = kIsWeb
        ? 'Web'
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => 'Android',
            TargetPlatform.iOS => 'iOS',
            TargetPlatform.windows => 'Windows',
            TargetPlatform.macOS => 'macOS',
            TargetPlatform.linux => 'Linux',
            _ => 'unknown',
          };
    final form = FormData.fromMap({
      'payload': jsonEncode({
        'clientRequestID': clientRequestID,
        'type': type,
        'content': content.trim(),
        'includeSDKLogs': includeSDKLogs,
        'deviceID': DataSp.getDeviceID(),
        'platform': platform,
        'deviceName': deviceName,
        'appVersion': version,
      })
    });
    for (final attachment in attachments) {
      form.files.add(MapEntry(
          'screenshots',
          MultipartFile.fromBytes(attachment.bytes,
              filename: attachment.filename)));
    }
    final response = await dio.post<Map<String, dynamic>>(
        '${Config.appAuthUrl}/feedback/create',
        data: form,
        options: Options(
            headers: {
              'token': DataSp.chatToken,
              'operationID': const Uuid().v4()
            },
            sendTimeout: const Duration(seconds: 60),
            receiveTimeout: const Duration(seconds: 60)));
    final resp = ApiResp.fromJson(response.data ?? {});
    if (resp.errCode != 0) {
      if (resp.errCode == 20049 &&
          resp.data is Map &&
          resp.data['retryAfter'] is int) {
        throw (20049, 'retryAfter:${resp.data["retryAfter"]}');
      }
      throw (resp.errCode, resp.errDlt.isNotEmpty ? resp.errDlt : resp.errMsg);
    }
    final id = resp.data is Map ? resp.data['feedbackID'] : null;
    if (id is! String || !id.startsWith('fb_')) {
      throw const FormatException('Invalid feedback response');
    }
    return id;
  }

  @override
  Future<void> uploadFeedbackLogs(
      String feedbackID, String clientRequestID) async {
    await OpenIM.iMManager.uploadLogs(
        line: 10000,
        ex: jsonEncode({
          'biz': 'feedback',
          'feedbackID': feedbackID,
          'clientRequestID': clientRequestID
        }));
  }

  Future<dynamic> _security(String path,
      {String method = 'POST', Map<String, dynamic>? data}) async {
    final response = await dio.request<Map<String, dynamic>>(
      '${Config.appAuthUrl}$path',
      data: data,
      options: Options(
          method: method,
          headers: {
            'token': DataSp.chatToken,
            'operationID': const Uuid().v4(),
            'Content-Type': 'application/json',
          },
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30)),
    );
    final body = response.data;
    if (body == null) throw StateError('Empty response');
    final resp = ApiResp.fromJson(body);
    if (resp.errCode != 0) {
      throw (resp.errCode, resp.errDlt.isNotEmpty ? resp.errDlt : resp.errMsg);
    }
    return resp.data;
  }

  Future<void> _changeLoginPassword(Map<String, dynamic> data) async {
    await _security('/account/password/change', data: {
      'userID': OpenIM.iMManager.userID,
      ...data,
    });
    IMViews.showToast(
      (Get.locale ?? Get.deviceLocale)?.languageCode == 'zh'
          ? '登录密码修改成功，请重新登录'
          : 'Login password changed successfully. Please sign in again.',
      duration: const Duration(seconds: 2),
    );
    await DataSp.removeLoginCertificate();
    PushController.logout();
    try {
      await controller.logout();
    } finally {
      AppNavigator.startLogin();
    }
  }

  @override
  Future<void> changePassword(
          {required String oldPassword, required String newPassword}) =>
      _changeLoginPassword({
        'currentPassword': IMUtils.generateMD5(oldPassword),
        'newPassword': IMUtils.generateMD5(newPassword)
      });
  @override
  Future<void> changePasswordWithPhoneCode(
          {required String phone,
          required String code,
          required String newPassword}) =>
      _changeLoginPassword({
        'verifyCode': code,
        'newPassword': IMUtils.generateMD5(newPassword)
      });
  @override
  Future<VerificationCodeResult> requestPhoneCode(String phone,
      {required String captchaVerifyParam}) async {
    return VerificationCodeResult.fromJson(
        await _security('/account/code/send', data: {
      'areaCode': securityAreaCode,
      'phoneNumber': phone,
      'usedFor': 2,
      'captchaVerifyParam': captchaVerifyParam,
    }));
  }

  @override
  Future<VerificationCodeResult> requestNewPhoneCode(String phone,
      {required String captchaVerifyParam,
      String? invitationCode,
      String? areaCode}) async {
    return VerificationCodeResult.fromJson(
        await _security('/account/code/send', data: {
      'areaCode': areaCode ?? securityAreaCode,
      'phoneNumber': phone,
      'usedFor': 1,
      'captchaVerifyParam': captchaVerifyParam,
      if (invitationCode != null && invitationCode.isNotEmpty)
        'invitationCode': invitationCode
    }));
  }

  @override
  Future<void> bindPhone(
      {required String phone, required String code, String? areaCode}) async {
    await _security('/account/phone/bind', data: {
      'areaCode': areaCode ?? securityAreaCode,
      'phoneNumber': phone,
      'verifyCode': code
    });
    if (!controller.isClosed) {
      controller.userInfo.update((user) {
        user?.phoneNumber = phone;
        user?.areaCode = areaCode ?? securityAreaCode;
      });
    }
  }

  @override
  Future<void> changePhone(
      {required String phone,
      required String oldCode,
      required String newCode,
      String? areaCode}) async {
    await _security('/account/phone/change', data: {
      'areaCode': areaCode ?? securityAreaCode,
      'phoneNumber': phone,
      'oldVerifyCode': oldCode,
      'newVerifyCode': newCode
    });
    if (!controller.isClosed) {
      controller.userInfo.update((user) {
        user?.phoneNumber = phone;
        user?.areaCode = areaCode ?? securityAreaCode;
      });
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getLoginRecords() async {
    final data = await _security('/account/login_records', data: {});
    return (data['records'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  @override
  Future<void> removeDevice(String deviceID) async {
    await _security('/account/device/remove', data: {'deviceID': deviceID});
  }

  @override
  Future<void> removeOtherDevices() async {
    await _security('/account/device/remove_others', data: {});
  }

  @override
  Future<void> trustDevice(String deviceID, bool trusted) async {
    await _security('/account/device/trust',
        data: {'deviceID': deviceID, 'trusted': trusted});
  }

  @override
  Future<bool> hasTradePassword() async =>
      (await _security('/chat/fund/pay-password', method: 'GET'))['set'] ==
      true;
  @override
  Future<void> setTradePassword(String password) async {
    await _security('/chat/fund/pay-password',
        method: 'PUT', data: {'password': password});
  }

  @override
  Future<void> changeTradePassword(
      {required String oldPassword, required String newPassword}) async {
    await _security('/chat/fund/pay-password',
        method: 'PUT',
        data: {'currentPassword': oldPassword, 'password': newPassword});
  }

  @override
  Future<VerificationCodeResult> requestTradePasswordCode(
      {required String captchaVerifyParam}) async {
    return VerificationCodeResult.fromJson(await _security(
        '/chat/fund/pay-password/code',
        data: {'captchaVerifyParam': captchaVerifyParam}));
  }

  @override
  Future<void> resetTradePassword(
      {required String code, required String password}) async {
    await _security('/chat/fund/pay-password/reset',
        data: {'verifyCode': code, 'password': password});
  }

  static String signatureFromEx(String? ex) {
    try {
      final value = jsonDecode(ex ?? '{}');
      return value is Map && value['signature'] is String
          ? value['signature'] as String
          : '';
    } catch (_) {
      return '';
    }
  }

  Future<void> refresh() async {
    final info = await Apis.queryMyFullInfo();
    final sdkInfo = await OpenIM.iMManager.userManager.getSelfUserInfo();
    if (info == null || controller.isClosed) return;
    controller.userInfo.update((user) {
      user?.nickname = info.nickname;
      user?.faceURL = info.faceURL;
      user?.gender = info.gender;
      user?.birth = info.birth;
      user?.phoneNumber = info.phoneNumber;
      user?.areaCode = info.areaCode;
      user?.ex = sdkInfo.ex;
    });
  }

  @override
  Future<void> updateNickname(String nickname) async {
    await Apis.updateUserInfo(
        userID: OpenIM.iMManager.userID,
        nickname: nickname,
        showErrorToast: false);
    if (!controller.isClosed) {
      controller.userInfo.update((user) => user?.nickname = nickname);
    }
  }

  @override
  Future<void> updateAvatar(String localPath) async {
    final result = await OpenIM.iMManager.uploadFile(
        id: const Uuid().v4(),
        filePath: localPath,
        fileName: p.basename(localPath));
    final data = result is String ? jsonDecode(result) : result;
    final url = data is Map ? data['url'] : null;
    if (url is! String || !IMUtils.isUrlValid(url)) {
      throw StateError('Invalid avatar URL');
    }
    await Apis.updateUserInfo(userID: OpenIM.iMManager.userID, faceURL: url);
    if (!controller.isClosed) {
      controller.userInfo.update((user) => user?.faceURL = url);
    }
  }

  @override
  Future<void> updateGender(int gender) async {
    await Apis.updateUserInfo(userID: OpenIM.iMManager.userID, gender: gender);
    if (!controller.isClosed) {
      controller.userInfo.update((user) => user?.gender = gender);
    }
  }

  @override
  Future<void> updateBirthday(int birthMilliseconds) async {
    await Apis.updateUserInfo(
        userID: OpenIM.iMManager.userID, birth: birthMilliseconds);
    if (!controller.isClosed) {
      controller.userInfo.update((user) => user?.birth = birthMilliseconds);
    }
  }

  @override
  Future<void> updateSignature(String signature) async {
    final current = await OpenIM.iMManager.userManager.getSelfUserInfo();
    final ex = signatureEx(current.ex, signature);
    await OpenIM.iMManager.userManager.setSelfInfo(ex: ex);
    if (!controller.isClosed) {
      controller.userInfo.update((user) => user?.ex = ex);
    }
  }

  static String signatureEx(String? current, String signature) {
    // Preserve other extension fields; reject unknown formats without replacing them.
    final decoded =
        jsonDecode(current == null || current.isEmpty ? '{}' : current);
    final fields = Map<String, dynamic>.from(decoded as Map);
    fields['signature'] = signature;
    return jsonEncode(fields);
  }
}
