import 'dart:typed_data';

/// Contract for actions that will eventually call the real backend.
///
/// UI and navigation are complete in this migration, while the default
/// [StubSettingsService] deliberately performs no remote work.
abstract class SettingsService {
  bool get isBackendAvailable;

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

  Future<void> requestPhoneCode(String phone);

  Future<void> verifyCurrentPhoneCode({
    required String phone,
    required String code,
  });

  Future<void> bindPhone({required String phone, required String code});

  Future<void> setTradePassword(String password);

  Future<void> changeTradePassword({
    required String oldPassword,
    required String newPassword,
  });

  Future<void> clearCache();

  Future<void> testNodes();

  Future<void> selectNode(String nodeId);

  Future<void> submitFeedback({
    required String type,
    required String content,
    required List<SettingsFeedbackAttachment> attachments,
    bool includeDiagnostics = false,
  });

  Future<void> checkForUpdate();
}

class StubSettingsService implements SettingsService {
  const StubSettingsService();

  @override
  bool get isBackendAvailable => false;

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
  Future<void> bindPhone({required String phone, required String code}) =>
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
  Future<void> requestPhoneCode(String phone) => _noop();

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
