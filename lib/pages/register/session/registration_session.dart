import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/im_controller.dart';

/// Completes signup using the existing account store and SDK session owner.
class RegistrationSession {
  RegistrationSession({required this.imLogic, required this.isActive})
      : _owner = (DataSp.userID, DataSp.chatToken, DataSp.imToken);

  final IMController imLogic;
  final bool Function() isActive;
  (String?, String?, String?) _owner;

  bool get isCurrent =>
      isActive() &&
      !imLogic.isClosed &&
      (DataSp.userID, DataSp.chatToken, DataSp.imToken) == _owner;

  Future<bool> finish(
    LoginCertificate certificate, {
    required String areaCode,
    String? phoneNumber,
    String? email,
  }) async {
    if (!isCurrent ||
        certificate.userID.isEmpty ||
        IMUtils.emptyStrToNull(certificate.chatToken) == null ||
        IMUtils.emptyStrToNull(certificate.imToken) == null) {
      return false;
    }
    _owner = (certificate.userID, certificate.chatToken, certificate.imToken);
    await DataSp.putLoginCertificate(certificate);
    if (!isCurrent) return false;
    await DataSp.putLoginAccount({
      'areaCode': areaCode,
      'phoneNumber': phoneNumber,
      'email': email,
    });
    if (!isCurrent) return false;
    await DataSp.putLoginType(email != null ? 1 : 0);
    if (!isCurrent) return false;
    await imLogic.login(certificate.userID, certificate.imToken);
    if (!isCurrent) return false;
    PushController.login(
      certificate.userID,
      onTokenRefresh: (token) {
        if (OpenIM.iMManager.userID != certificate.userID ||
            DataSp.imToken != certificate.imToken) {
          return;
        }
        OpenIM.iMManager.updateFcmToken(
          fcmToken: token,
          expireTime: DateTime.now()
              .add(const Duration(days: 90))
              .millisecondsSinceEpoch,
        );
      },
    );
    return isCurrent;
  }
}
