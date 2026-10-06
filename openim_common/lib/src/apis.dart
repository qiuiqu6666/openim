import 'dart:async';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

class Apis {
  static Future<String> createFriendGrant(Map<String, String> input) async {
    final data = await HttpUtil.post('${Config.appAuthUrl}/chat/friend-grants',
        data: input,
        options: chatTokenOptions..contentType = Headers.jsonContentType,
        showErrorToast: false);
    final grant = data['friendGrant'];
    if (grant is! String || grant.isEmpty) {
      throw StateError('Missing friend grant');
    }
    return grant;
  }

  static Future<void> applyFriendGrant(
      {required String grant, required String message}) async {
    await HttpUtil.post('${Config.appAuthUrl}/chat/friend-apply',
        data: {'friendGrant': grant, 'message': message},
        options: chatTokenOptions..contentType = Headers.jsonContentType,
        showErrorToast: false);
  }

  static Future<String> createFriendInvite(FriendAddSource source,
      {String? targetUserID}) async {
    if (!{FriendAddSource.qrcode, FriendAddSource.link, FriendAddSource.card}
        .contains(source)) {
      throw ArgumentError('Invalid invite source');
    }
    final data = await HttpUtil.post('${Config.appAuthUrl}/chat/friend-invites',
        data: {
          'source': source.name,
          if (source == FriendAddSource.card) 'targetUserID': targetUserID
        },
        options: chatTokenOptions..contentType = Headers.jsonContentType,
        showErrorToast: false);
    final code = data['inviteCode'];
    if (code is! String || code.isEmpty) {
      throw StateError('Missing invite code');
    }
    return code;
  }

  static Options get imTokenOptions =>
      Options(headers: {'token': DataSp.imToken});

  static Options get chatTokenOptions =>
      Options(headers: {'token': DataSp.chatToken});

  static StreamController kickoffController = StreamController<int>.broadcast();

  static Future<Map<String, String>> _deviceMetadata(
      {bool validateLoginDeviceID = false}) async {
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
      final package = await PackageInfo.fromPlatform();
      version = package.buildNumber.isEmpty
          ? package.version
          : '${package.version}+${package.buildNumber}';
    } catch (_) {}
    return {
      'deviceID': validateLoginDeviceID
          ? await DataSp.ensureLoginDeviceID()
          : DataSp.getDeviceID(),
      'deviceName': deviceName,
      'version': version
    };
  }

  static Future<LoginCertificate> login({
    String? areaCode,
    String? phoneNumber,
    String? account,
    String? email,
    String? password,
    String? verificationCode,
    bool Function()? isCurrent,
    bool showErrorToast = true,
  }) async {
    final request = await prepareLoginRequest(
      areaCode: areaCode,
      phoneNumber: phoneNumber,
      account: account,
      email: email,
      password: password,
      verificationCode: verificationCode,
    );
    return loginWithRequest(request,
        isCurrent: isCurrent, showErrorToast: showErrorToast);
  }

  /// Freeze the existing OpenIM identity and MD5 password with this device.
  /// The map belongs to one attempt and must remain in memory only.
  static Future<Map<String, dynamic>> prepareLoginRequest({
    String? areaCode,
    String? phoneNumber,
    String? account,
    String? email,
    String? password,
    String? verificationCode,
  }) async {
    final identities = <String, String>{
      if (phoneNumber != null && phoneNumber.trim().isNotEmpty)
        'phoneNumber': phoneNumber.trim(),
      if (account != null && account.trim().isNotEmpty)
        'account': account.trim(),
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
    };
    if (identities.length != 1) {
      throw const FormatException('Exactly one login identity is required');
    }
    final metadata = await _deviceMetadata(validateLoginDeviceID: true);
    return Map<String, dynamic>.unmodifiable({
      ...metadata,
      if (areaCode != null) 'areaCode': areaCode,
      ...identities,
      if (password != null) 'password': IMUtils.generateMD5(password),
      'platform': IMUtils.getPlatform(),
      if (verificationCode != null) 'verifyCode': verificationCode,
    });
  }

  /// Submit a frozen login payload, adding an SMS proof only at its owner.
  /// Neither business errors nor incomplete credentials can become a login.
  static Future<LoginCertificate> loginWithRequest(
    Map<String, dynamic> request, {
    bool Function()? isCurrent,
    bool showErrorToast = true,
  }) async {
    try {
      if (isCurrent != null && !isCurrent()) {
        throw StateError('Login attempt is no longer current');
      }
      final data = await HttpUtil.post(Urls.login,
          showErrorToast: showErrorToast,
          withoutToken: true,
          requestOperationID: const Uuid().v4(),
          options: Options(contentType: Headers.jsonContentType),
          data: Map<String, dynamic>.from(request));
      if (data is! Map ||
          ['userID', 'chatToken', 'imToken'].any((key) =>
              data[key] is! String || (data[key] as String).trim().isEmpty)) {
        throw const FormatException('Incomplete login credentials');
      }
      return LoginCertificate.fromJson(Map<String, dynamic>.from(data));
    } catch (e, s) {
      if (isCurrent == null) {
        _catchErrorHelper(e, s);
      } else if (isCurrent()) {
        // A scoped login owns its feedback and navigation. Never let an old
        // request clear credentials belonging to a later route/session.
        Logger.print('Login request failed: ${e.runtimeType}');
      }

      return Future.error(e);
    }
  }

  static Future<LoginCertificate> register({
    required String nickname,
    required String password,
    String? faceURL,
    String? areaCode,
    String? phoneNumber,
    String? email,
    String? account,
    int birth = 0,
    int gender = 1,
    required String verificationCode,
    String? invitationCode,
    bool showErrorToast = true,
  }) async {
    try {
      var data = await HttpUtil.post(Urls.register,
          showErrorToast: showErrorToast,
          data: {
            ...await _deviceMetadata(),
            'verifyCode': verificationCode,
            'platform': IMUtils.getPlatform(),
            'invitationCode': invitationCode,
            'autoLogin': true,
            'user': {
              "nickname": nickname,
              "faceURL": faceURL,
              'birth': birth,
              'gender': gender,
              'email': email,
              "areaCode": areaCode,
              'phoneNumber': phoneNumber,
              'account': account,
              'password': IMUtils.generateMD5(password),
            },
          });

      final cert = LoginCertificate.fromJson(data!);

      return cert;
    } catch (e, s) {
      // Authentication requests own their UI and must not clear another session
      // just because a transport failure occurred.
      Logger.print('Registration request failed: ${e.runtimeType}');
      return Future.error(e, s);
    }
  }

  static Future<dynamic> resetPassword({
    String? areaCode,
    String? phoneNumber,
    String? email,
    required String password,
    required String verificationCode,
    bool showErrorToast = true,
  }) async {
    try {
      return await HttpUtil.post(
        Urls.resetPwd,
        showErrorToast: showErrorToast,
        data: {
          "areaCode": areaCode,
          'phoneNumber': phoneNumber,
          'email': email,
          'password': IMUtils.generateMD5(password),
          'verifyCode': verificationCode,
          'platform': IMUtils.getPlatform(),
        },
        options: chatTokenOptions,
      );
    } catch (e, s) {
      Logger.print('Password reset request failed: ${e.runtimeType}');
      return Future.error(e, s);
    }
  }

  static Future<bool> changePassword({
    required String userID,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await HttpUtil.post(
        Urls.changePwd,
        data: {
          "userID": userID,
          'currentPassword': IMUtils.generateMD5(currentPassword),
          'newPassword': IMUtils.generateMD5(newPassword),
          'platform': IMUtils.getPlatform(),
        },
        options: chatTokenOptions,
      );
      return true;
    } catch (e, s) {
      _catchErrorHelper(e, s);

      return false;
    }
  }

  static Future<bool> changePasswordOfB({
    required String newPassword,
  }) async {
    try {
      await HttpUtil.post(
        Urls.resetPwd,
        data: {
          'password': IMUtils.generateMD5(newPassword),
          'platform': IMUtils.getPlatform(),
        },
        options: chatTokenOptions,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> checkNickname(String nickname) async {
    final data = await HttpUtil.post(
      '${Config.appAuthUrl}/user/nickname/check',
      data: {'nickname': nickname},
      options: chatTokenOptions,
      showErrorToast: false,
    );
    if (data is! Map) {
      throw const FormatException('Invalid nickname check response');
    }
    return Map<String, dynamic>.from(data);
  }

  static Future<dynamic> updateUserInfo({
    required String userID,
    String? account,
    String? phoneNumber,
    String? areaCode,
    String? email,
    String? nickname,
    String? faceURL,
    int? gender,
    int? birth,
    int? level,
    int? allowAddFriend,
    int? allowBeep,
    int? allowVibration,
    bool showErrorToast = true,
    bool Function()? isCurrent,
  }) async {
    try {
      Map<String, dynamic> param = {'userID': userID};
      void put(String key, dynamic value) {
        if (null != value) {
          param[key] = value;
        }
      }

      put('account', account);
      put('phoneNumber', phoneNumber);
      put('areaCode', areaCode);
      put('email', email);
      if (nickname != null) param['nickname'] = {'value': nickname};
      put('faceURL', faceURL);
      put('gender', gender);
      put('gender', gender);
      put('level', level);
      put('birth', birth);
      put('allowAddFriend', allowAddFriend);
      put('allowBeep', allowBeep);
      put('allowVibration', allowVibration);

      Future<dynamic> save() => HttpUtil.post(
            Urls.updateUserInfo,
            data: {...param, 'platform': IMUtils.getPlatform()},
            options: chatTokenOptions,
            showErrorToast: false,
          );
      try {
        return await save();
      } catch (error) {
        // Older deployments bind nickname as a string instead of StringValue.
        // Retry only a binding error: the first request never reached a write.
        if (nickname == null ||
            error is! (int, String?) ||
            error.$1 != 1001 ||
            !(error.$2 ?? '').contains(
                'cannot unmarshal object into Go value of type string')) {
          rethrow;
        }
        param['nickname'] = nickname;
        return await save();
      }
    } catch (e, s) {
      if (showErrorToast &&
          (isCurrent?.call() ?? true) &&
          e is (int, String?)) {
        final reason = HttpUtil.businessErrorMessage(ApiResp.fromJson({
          'errCode': e.$1,
          'errDlt': e.$2 ?? '',
        }));
        IMViews.showToast(reason);
      }
      if (e is (int, String?) && (isCurrent?.call() ?? true)) {
        _catchErrorHelper(e, s);
      }
      rethrow;
    }
  }

  /// Update one friend discovery permission without changing the other settings.
  static Future<void> updateFriendAddPermission({
    required String userID,
    required String field,
    required int value,
  }) async {
    const fields = {
      'allowAddByUserID',
      'allowAddByAccount',
      'allowAddByPhone',
      'allowAddByEmail',
      'allowAddByQRCode',
      'allowAddByGroup',
      'allowAddByCard',
    };
    if ((field == 'allowAddFriend' && value != 0 && value != 1) ||
        (field != 'allowAddFriend' &&
            (!fields.contains(field) || (value != 1 && value != 2)))) {
      throw ArgumentError('Invalid friend add permission');
    }
    Future<void> save(dynamic fieldValue) async {
      await HttpUtil.post(
        Urls.updateUserInfo,
        data: {
          'userID': userID,
          field: fieldValue,
          'platform': IMUtils.getPlatform(),
        },
        options: chatTokenOptions,
        showErrorToast: false,
      );
    }

    if (field == 'allowAddFriend') {
      await save(value);
      return;
    }

    try {
      await save(value);
    } catch (error) {
      // Older deployments require wrapper objects. Only retry that
      // specific format error; other failures must reach the caller.
      if (error is! (int, String) ||
          error.$1 != 1001 ||
          !error.$2.contains('cannot unmarshal number')) {
        rethrow;
      }
      await save({'value': value});
      final refreshed = await getUserFullInfo(userIDList: [userID]);
      if (refreshed == null || refreshed.isEmpty) {
        throw StateError('Could not verify friend add permission');
      }
      final current = refreshed.first.toJson()[field];
      if (current != value) {
        throw StateError('Friend add permission was not saved by the server');
      }
    }
  }

  static Future<List<FriendInfo>> searchFriendInfo(
    String keyword, {
    int pageNumber = 1,
    int showNumber = 10,
    bool showErrorToast = true,
  }) async {
    try {
      final data = await HttpUtil.post(
        Urls.searchFriendInfo,
        data: {
          'pagination': {'pageNumber': pageNumber, 'showNumber': showNumber},
          'keyword': keyword,
        },
        options: chatTokenOptions,
        showErrorToast: showErrorToast,
      );
      if (data['users'] is List) {
        return (data['users'] as List)
            .map((e) => FriendInfo.fromJson(e))
            .toList();
      }
      return [];
    } catch (e, s) {
      _catchErrorHelper(e, s);

      rethrow;
    }
  }

  static Future<List<UserFullInfo>?> getUserFullInfo({
    int pageNumber = 0,
    int showNumber = 10,
    bool showErrorToast = true,
    required List<String> userIDList,
  }) async {
    final requestOptions = chatTokenOptions;
    try {
      final data = await HttpUtil.post(
        Urls.getUsersFullInfo,
        data: {
          'pagination': {'pageNumber': pageNumber, 'showNumber': showNumber},
          'userIDs': userIDList,
          'platform': IMUtils.getPlatform(),
        },
        options: requestOptions,
        showErrorToast: showErrorToast,
      );
      if (data['users'] is List) {
        return (data['users'] as List)
            .map((e) => UserFullInfo.fromJson(e))
            .toList();
      }
      return null;
    } catch (e, s) {
      if (showErrorToast) {
        _catchErrorHelper(e, s);
      }

      return showErrorToast ? [] : null;
    }
  }

  static Future<List<UserFullInfo>?> searchUserFullInfo({
    required String content,
    int? way,
    int pageNumber = 1,
    int showNumber = 10,
  }) async {
    try {
      final data = await HttpUtil.post(
        Urls.searchUserFullInfo,
        data: {
          'pagination': {'pageNumber': pageNumber, 'showNumber': showNumber},
          'keyword': content,
          if (way != null) 'way': way,
        },
        options: chatTokenOptions,
      );
      if (data['users'] is List) {
        return (data['users'] as List)
            .map((e) => UserFullInfo.fromJson(e))
            .toList();
      }
      return null;
    } catch (e, s) {
      _catchErrorHelper(e, s);

      return [];
    }
  }

  static Future<UserFullInfo?> queryMyFullInfo() async {
    final list = await Apis.getUserFullInfo(
      userIDList: [OpenIM.iMManager.userID],
    );
    return list?.firstOrNull;
  }

  static Future<bool> requestVerificationCode({
    String? areaCode,
    String? phoneNumber,
    String? email,
    required int usedFor,
    required String captchaVerifyParam,
    String? invitationCode,
  }) async {
    return HttpUtil.post(
      Urls.getVerificationCode,
      data: {
        "areaCode": areaCode,
        "phoneNumber": phoneNumber,
        "email": email,
        'usedFor': usedFor,
        'invitationCode': invitationCode,
        'captchaVerifyParam': captchaVerifyParam
      },
    ).then((value) {
      final sent = value is Map &&
          value['captchaVerifyResult'] == true &&
          value['bizResult'] == true;
      IMViews.showToast(sent ? StrRes.sentSuccessfully : StrRes.sendFailed);
      return sent;
    }).catchError((e, s) {
      _catchErrorHelper(e, s);

      return false;
    });
  }

  static Future<SignalingCertificate> getTokenForRTC(
      String roomID, String userID) async {
    return HttpUtil.post(
      Urls.getTokenForRTC,
      data: {
        "room": roomID,
        "identity": userID,
      },
      options: chatTokenOptions,
    ).then((value) {
      final signaling = SignalingCertificate.fromJson(value)..roomID = roomID;
      return signaling;
    }).catchError((e, s) {
      _catchErrorHelper(e, s);

      throw e;
    });
  }

  static Future<dynamic> checkVerificationCode({
    String? areaCode,
    String? phoneNumber,
    String? email,
    required String verificationCode,
    required int usedFor,
    String? invitationCode,
    bool showErrorToast = true,
  }) {
    return HttpUtil.post(
      Urls.checkVerificationCode,
      showErrorToast: showErrorToast,
      data: {
        "phoneNumber": phoneNumber,
        "areaCode": areaCode,
        "email": email,
        "verifyCode": verificationCode,
        "usedFor": usedFor,
        'invitationCode': invitationCode
      },
    );
  }

  static Future<UpgradeInfoV2> checkUpgradeV2() {
    return dio.post<Map<String, dynamic>>(
      'https://www.pgyer.com/apiv2/app/check',
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
      ),
      data: {
        '_api_key': '',
        'appKey': '',
      },
    ).then((resp) {
      Map<String, dynamic> map = resp.data!;
      if (map['code'] == 0) {
        return UpgradeInfoV2.fromJson(map['data']);
      }
      return Future.error(map);
    });
  }

  static Future<Map<String, dynamic>> getClientConfig() async {
    return {
      'discoverPageURL': Config.discoverPageURL,
      'allowSendMsgNotFriend': Config.allowSendMsgNotFriend
    };
  }

  static void _catchErrorHelper(Object e, StackTrace s) {
    if (e is (int, String?)) {
      Logger.print('API request failed: errCode=${e.$1}');
    } else {
      // HttpUtil owns localized feedback. Network failures do not expire a
      // session; authenticated business errors go through its token guard.
      Logger.print('API request failed: ${e.runtimeType}');
    }
  }
}
