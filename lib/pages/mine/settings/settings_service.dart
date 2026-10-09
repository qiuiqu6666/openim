import 'dart:typed_data';
import 'verification_code_result.dart';

/// Contract for actions that will eventually call the real backend.
///
/// UI and navigation are complete in this migration, while the default
/// [StubSettingsService] deliberately performs no remote work.
abstract class SettingsService {
  const SettingsService();
  bool get isBackendAvailable;

  /// Local notification choices work without a remote settings endpoint.
  /// Adapters with a real endpoint can opt into save-before-commit behavior.
  bool get supportsRemoteNotificationSettings => isBackendAvailable;

  bool get isProfileBackendAvailable => isBackendAvailable;
  bool get supportsNicknameCheck => false;
  bool get supportsFriendPermissions => false;
  bool get supportsPresenceVisibility => false;
  Future<Map<String, int>> getFriendPermissions() =>
      Future.error(UnsupportedError('Friend permissions unavailable'));
  Future<void> updateAllowAddFriend(bool allowed) =>
      Future.error(UnsupportedError('Friend permissions unavailable'));
  Future<NicknameCheckResult> checkNickname(String nickname) =>
      Future.error(UnsupportedError('Nickname check unavailable'));
  bool get isSecurityBackendAvailable => isBackendAvailable;
  String get securityPhone => '';
  bool get securitySmsExempt => false;
  String get securityAreaCode => '+86';
  Future<void> refreshSecurity() async {}
  Future<List<Map<String, dynamic>>> getLoginRecords() async => [];
  Future<void> removeDevice(String deviceID) =>
      Future.error(UnsupportedError('Device management unavailable'));
  Future<void> removeOtherDevices() =>
      Future.error(UnsupportedError('Device management unavailable'));
  Future<void> trustDevice(String deviceID, bool trusted) =>
      Future.error(UnsupportedError('Device management unavailable'));
  Future<bool> hasTradePassword() async => false;
  Future<VerificationCodeResult> requestNewPhoneCode(String phone,
          {required String captchaVerifyParam,
          String? invitationCode,
          String? areaCode}) =>
      requestPhoneCode(phone, captchaVerifyParam: captchaVerifyParam);
  Future<void> changePhone(
      {required String phone,
      required String oldCode,
      required String newCode,
      String? areaCode}) async {}
  Future<VerificationCodeResult> requestTradePasswordCode(
          {required String captchaVerifyParam}) async =>
      const VerificationCodeResult(captchaVerified: false, sent: false);
  Future<void> resetTradePassword(
      {required String code, required String password}) async {}

  Future<void> updateNickname(String nickname);

  Future<void> updateAvatar(String localPath);

  Future<void> updateSignature(String signature);

  Future<void> updateGender(int gender);

  Future<void> updateBirthday(int birthMilliseconds);

  Future<void> updateFriendVerification(bool requireVerification);

  Future<void> updateFriendDiscovery({
    bool? qrCode,
    bool? businessCard,
    bool? group,
    bool? phone,
    bool? uid,
    bool? account,
    bool? email,
  });

  Future<void> updateLastSeenScope(String scope);

  Future<void> updateMomentsVisibilityDays(int days);

  Future<void> updateMomentsBlockedViewerIds(List<String> userIds);

  Future<void> updateMomentsHiddenAuthorIds(List<String> userIds);

  Future<void> updateSystemMessageNotification(bool enabled);

  Future<void> updateClosedNotificationPreview(String preview);

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  });

  Future<void> changePasswordWithPhoneCode({
    required String phone,
    required String code,
    required String newPassword,
  });

  Future<VerificationCodeResult> requestPhoneCode(String phone,
      {required String captchaVerifyParam});

  Future<void> verifyCurrentPhoneCode({
    required String phone,
    required String code,
  });

  Future<void> bindPhone(
      {required String phone, required String code, String? areaCode});

  Future<void> setTradePassword(String password);

  Future<void> changeTradePassword({
    required String oldPassword,
    required String newPassword,
  });

  Future<void> clearCache();

  Future<void> testNodes();

  Future<void> selectNode(String nodeId);

  bool get supportsFeedback => false;
  Future<String> createFeedback(
          {required String clientRequestID,
          required String type,
          required String content,
          required List<SettingsFeedbackAttachment> attachments,
          required bool includeSDKLogs}) =>
      Future.error(UnsupportedError('Feedback unavailable'));
  Future<void> uploadFeedbackLogs(String feedbackID, String clientRequestID) =>
      Future.error(UnsupportedError('Feedback logs unavailable'));

  Future<void> submitFeedback({
    required String type,
    required String content,
    required List<SettingsFeedbackAttachment> attachments,
    bool includeDiagnostics = false,
  });

  Future<void> checkForUpdate();
}

class NicknameCheckResult {
  const NicknameCheckResult(
      {required this.occupied, required this.nextUpdateTime});
  final bool occupied;
  final int nextUpdateTime;

  factory NicknameCheckResult.fromJson(Map<String, dynamic> data) {
    final occupied = data['occupied'];
    final next = data['nextUpdateTime'];
    if (occupied is! bool || next is! int || next < 0) {
      throw const FormatException('Invalid nickname check response');
    }
    return NicknameCheckResult(occupied: occupied, nextUpdateTime: next);
  }
}

class StubSettingsService extends SettingsService {
  const StubSettingsService();

  @override
  bool get isBackendAvailable => false;

  @override
  bool get isProfileBackendAvailable => isBackendAvailable;

  Future<void> _noop() async {}

  @override
  Future<void> updateNickname(String nickname) => _noop();

  @override
  Future<void> updateAvatar(String localPath) => _noop();

  @override
  Future<void> updateSignature(String signature) => _noop();

  @override
  Future<void> updateGender(int gender) => _noop();

  @override
  Future<void> updateBirthday(int birthMilliseconds) => _noop();

  @override
  Future<void> updateFriendVerification(bool requireVerification) => _noop();

  @override
  Future<void> updateFriendDiscovery({
    bool? qrCode,
    bool? businessCard,
    bool? group,
    bool? phone,
    bool? uid,
    bool? account,
    bool? email,
  }) =>
      _noop();

  @override
  Future<void> updateLastSeenScope(String scope) => _noop();

  @override
  Future<void> updateMomentsVisibilityDays(int days) => _noop();

  @override
  Future<void> updateMomentsBlockedViewerIds(List<String> userIds) => _noop();

  @override
  Future<void> updateMomentsHiddenAuthorIds(List<String> userIds) => _noop();

  @override
  Future<void> updateSystemMessageNotification(bool enabled) => _noop();

  @override
  Future<void> updateClosedNotificationPreview(String preview) => _noop();

  @override
  Future<void> bindPhone(
          {required String phone, required String code, String? areaCode}) =>
      _noop();

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) =>
      _noop();

  @override
  Future<void> changePasswordWithPhoneCode({
    required String phone,
    required String code,
    required String newPassword,
  }) =>
      _noop();

  @override
  Future<void> checkForUpdate() => _noop();

  @override
  Future<void> clearCache() => _noop();

  @override
  Future<VerificationCodeResult> requestPhoneCode(String phone,
          {required String captchaVerifyParam}) async =>
      const VerificationCodeResult(captchaVerified: false, sent: false);

  @override
  Future<void> verifyCurrentPhoneCode({
    required String phone,
    required String code,
  }) =>
      _noop();

  @override
  Future<void> setTradePassword(String password) => _noop();

  @override
  Future<void> changeTradePassword({
    required String oldPassword,
    required String newPassword,
  }) =>
      _noop();

  @override
  Future<void> submitFeedback({
    required String type,
    required String content,
    required List<SettingsFeedbackAttachment> attachments,
    bool includeDiagnostics = false,
  }) =>
      _noop();

  @override
  Future<void> testNodes() => _noop();

  @override
  Future<void> selectNode(String nodeId) => _noop();
}

class SettingsFeedbackAttachment {
  const SettingsFeedbackAttachment({
    required this.filename,
    required this.bytes,
  });

  final String filename;
  final Uint8List bytes;
}
