import 'package:dio/dio.dart';
import 'package:openim_common/openim_common.dart';

import 'apns_push_service.dart';

final apnsPush = ApnsPushService(
  currentSession: () {
    final userID = DataSp.userID;
    final credential = DataSp.imToken;
    if (userID == null || credential == null || credential.isEmpty) return null;
    return (userID: userID, credential: credential, endpoint: Config.imApiUrl);
  },
  deviceID: DataSp.ensureLoginDeviceID,
  request: (endpoint, credential, action, data) async {
    await HttpUtil.post('$endpoint/third/$action',
        data: data,
        showErrorToast: false,
        options: Options(
          headers: {'token': credential},
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ));
  },
  onError: (error) => Logger.print(
      'APNs registration unavailable: ${error.runtimeType}',
      onlyConsole: true),
);
