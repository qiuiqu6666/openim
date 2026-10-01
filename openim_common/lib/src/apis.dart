import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class Apis {
  static Options get imTokenOptions =>
      Options(headers: {'token': DataSp.imToken});

  static Options get chatTokenOptions =>
      Options(headers: {'token': DataSp.chatToken});

  static StreamController kickoffController = StreamController<int>.broadcast();

  static void _kickoff(int? errCode) {
    if (errCode == 1501 ||
        errCode == 1503 ||
        errCode == 1504 ||
        errCode == 1505) {
      kickoffController.sink.add(errCode);
    }
  }

  static Future<LoginCertificate> login({
    String? areaCode,
    String? phoneNumber,
    String? account,
    String? email,
    String? password,
    String? verificationCode,
  }) async {
    try {
      var data = await HttpUtil.post(Urls.login, data: {
        "areaCode": areaCode,
        'account': account,
        'phoneNumber': phoneNumber,
        'email': email,
        'password': null != password ? IMUtils.generateMD5(password) : null,
        'platform': IMUtils.getPlatform(),
        'verifyCode': verificationCode,
      });
      final cert = LoginCertificate.fromJson(data!);

      return cert;
    } catch (e, s) {
      _catchErrorHelper(e, s);

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
  }) async {
    try {
      var data = await HttpUtil.post(Urls.register, data: {
        'deviceID': DataSp.getDeviceID(),
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
      _catchErrorHelper(e, s);

      return Future.error(e);
    }
  }

  static Future<dynamic> resetPassword({
    String? areaCode,
    String? phoneNumber,
    String? email,
    required String password,
    required String verificationCode,
  }) async {
    try {
      return HttpUtil.post(
        Urls.resetPwd,
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
      _catchErrorHelper(e, s);
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

      return await HttpUtil.post(
        Urls.updateUserInfo,
        data: {
          ...param,
          'platform': IMUtils.getPlatform(),
        },
        options: chatTokenOptions,
      );
    } catch (e, s) {
      if (e is (int, String?)) _catchErrorHelper(e, s);
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
      await save({'value': value});
    } catch (error) {
      // Older deployments parse these fields as integers. Only retry that
      // specific format error; other failures must reach the caller.
      if (error is! (int, String) ||
          error.$1 != 1001 ||
          !error.$2.contains('strconv.ParseInt')) {
        rethrow;
      }
      await save(value);
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
    required List<String> userIDList,
  }) async {
    try {
      final data = await HttpUtil.post(
        Urls.getUsersFullInfo,
        data: {
          'pagination': {'pageNumber': pageNumber, 'showNumber': showNumber},
          'userIDs': userIDList,
          'platform': IMUtils.getPlatform(),
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
    String? invitationCode,
  }) async {
    return HttpUtil.post(
      Urls.getVerificationCode,
      data: {
        "areaCode": areaCode,
        "phoneNumber": phoneNumber,
        "email": email,
        'usedFor': usedFor,
        'invitationCode': invitationCode
      },
    ).then((value) {
      IMViews.showToast(StrRes.sentSuccessfully);
      return true;
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
  }) {
    return HttpUtil.post(
      Urls.checkVerificationCode,
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
      final errCode = e.$1;
      final errMsg = e.$2;
      _kickoff(errCode);

      Logger.print('e:$errCode s:$errMsg');
    } else {
      _catchError(e, s);
    }
  }

  static void _catchError(Object e, StackTrace s, {bool forceBack = true}) {
    IMViews.showToast(e.toString());

    if (forceBack) {
      DataSp.removeLoginCertificate();
      Get.offAllNamed('/login');
    }
  }
}
