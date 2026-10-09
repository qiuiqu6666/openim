import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/notifications/message_notification_preferences.dart';
import '../../../core/notifications/legacy_notification_preferences.dart';
import '../../../core/notifications/message_notification_sound.dart';
import '../../chat/calling/preferences/call_notification_preferences.dart';

/// Settings presentation state for migrated 99chat surfaces.
///
/// Purely local preferences are restored per account through [SpUtil]. Values
/// that belong to a remote 99chat settings API stay draft-only until that API is
/// integrated, so the UI never presents an unconfirmed server change as saved.
class SettingsDraftStore extends ChangeNotifier {
  SettingsDraftStore() : ownerUserId = _currentOwner() {
    _hydrateLocalSettings();
    _legacySeedValue =
        SpUtil().getDynamic(legacyNotificationSeedKey(ownerUserId));
    _notificationSubscription =
        MessageNotificationPreferences.changes.listen((owner) {
      if (isCurrentAccount && owner == ownerUserId) {
        final seed =
            SpUtil().getDynamic(legacyNotificationSeedKey(ownerUserId));
        if (seed == _legacySeedValue) return;
        _legacySeedValue = seed;
        _hydrateNotificationPreferences();
        notifyListeners();
      }
    });
  }

  StreamSubscription<String>? _notificationSubscription;
  Object? _legacySeedValue;
  final String ownerUserId;
  bool _disposed = false;
  bool get isCurrentAccount => !_disposed && ownerUserId == _currentOwner();

  static String _currentOwner() {
    final owner = DataSp.userID?.trim() ?? '';
    return owner.isEmpty ? 'anonymous' : owner;
  }

  String _localKey(String name) => '99chat_settings_${ownerUserId}_$name';

  @override
  void dispose() {
    _disposed = true;
    unawaited(_notificationSubscription?.cancel());
    super.dispose();
  }

  void _hydrateLocalSettings() {
    final sp = SpUtil();
    showOnlineStatus =
        sp.getBool(_localKey('show_online_status'), defValue: true) ?? true;
    readReceipts =
        sp.getBool(_localKey('read_receipts'), defValue: true) ?? true;
    quickAnswer =
        sp.getBool(_localKey('notify_quick_answer'), defValue: true) ?? true;
    notificationQuickReply =
        sp.getBool(_localKey('notify_quick_reply'), defValue: true) ?? true;
    _hydrateNotificationPreferences();
    messageSoundEnabled =
        sp.getBool(_localKey('message_sound_enabled'), defValue: true) ?? true;
    messageSound = MessageNotificationSoundIds.normalizedId(
        sp.getString(_localKey('message_sound'), defValue: 'preview000') ??
            'preview000');
    callRingtoneEnabled =
        sp.getBool(_localKey('call_ringtone_enabled'), defValue: true) ?? true;
    vibration = sp.getBool(_localKey('vibration'), defValue: true) ?? true;
  }

  void _hydrateNotificationPreferences() {
    final notificationPreferences =
        MessageNotificationPreferences.read(ownerUserId);
    notifyWhenOpen = notificationPreferences.notifyWhenOpen;
    notifyWhenClosed = notificationPreferences.notifyWhenClosed;
    closedNotificationPreview = notificationPreferences.closedPreview.name;
    openedNotificationPreview = notificationPreferences.openedPreview.name;
  }

  void _putBool(String name, bool value) {
    SpUtil().putBool(_localKey(name), value);
  }

  void _putString(String name, String value) {
    SpUtil().putString(_localKey(name), value);
  }

  bool _profileNicknameDirty = false;
  bool _profileSignatureDirty = false;
  String profileNickname = '';
  String profileSignature = '';

  bool requireFriendVerification = true;
  bool allowAddFriend = true;
  bool friendPermissionsLoaded = false;
  void syncFriendPermissions(Map<String, int> data) {
    allowAddFriend = data['allowAddFriend'] == 1;
    allowQrCode = data['allowAddByQRCode'] != 2;
    allowBusinessCard = data['allowAddByCard'] != 2;
    allowGroup = data['allowAddByGroup'] != 2;
    allowPhone = data['allowAddByPhone'] != 2;
    allowUid = data['allowAddByUserID'] != 2;
    allowAccount = data['allowAddByAccount'] != 2;
    allowEmail = data['allowAddByEmail'] != 2;
    friendPermissionsLoaded = true;
    notifyListeners();
  }

  void setAllowAddFriend(bool value) {
    allowAddFriend = value;
    notifyListeners();
  }

  bool allowQrCode = true;
  bool allowBusinessCard = true;
  bool allowGroup = true;
  bool allowPhone = true;
  bool allowUid = true;
  bool allowAccount = true;
  bool allowEmail = true;
  String lastSeenScope = 'all';
  bool showOnlineStatus = true;
  bool readReceipts = true;

  int momentsVisibilityDays = 0;
  final Map<String, SettingsContactDraft> momentsHiddenFrom =
      <String, SettingsContactDraft>{};
  final Map<String, SettingsContactDraft> momentsHiddenBy =
      <String, SettingsContactDraft>{};

  bool biometricPay = false;
  int fontSizeIndex = 1;

  bool notifyWhenClosed = true;
  bool callNotifyWhenClosed = true;
  bool quickAnswer = true;
  bool notificationQuickReply = true;
  String closedNotificationPreview = 'detail';
  bool notifyWhenOpen = true;
  String openedNotificationPreview = 'detail';
  bool messageSoundEnabled = true;
  String messageSound = 'preview000';
  bool callRingtoneEnabled = true;
  String callRingtone = 'default';
  bool vibration = true;

  String chatBackgroundId = 'default';
  Uint8List? chatBackgroundImageBytes;
  Uint8List? profileAvatarPreviewBytes;

  String? selectedNodeId;
  DateTime? nodeLastTestAt;

  void seedProfile({required String nickname, String signature = ''}) {
    final nextNickname = nickname;
    final nextSignature = signature.trim();

    // The OpenIM profile arrives asynchronously. Keep following each server
    // field independently until the user edits that specific field locally.
    // Editing a bio must not freeze a still-loading nickname (and vice versa).
    if (!_profileNicknameDirty && nextNickname.isNotEmpty) {
      profileNickname = nextNickname;
    }
    if (!_profileSignatureDirty && nextSignature.isNotEmpty) {
      profileSignature = nextSignature;
    }
  }

  void setProfileNickname(String value) {
    final next = value;
    _profileNicknameDirty = true;
    if (profileNickname == next) return;
    profileNickname = next;
    notifyListeners();
  }

  void setProfileSignature(String value) {
    final next = value.trim();
    _profileSignatureDirty = true;
    if (profileSignature == next) return;
    profileSignature = next;
    notifyListeners();
  }

  /// Apply confirmed SDK data, including a signature cleared on another device.
  void syncProfileSignature(String value) {
    _profileSignatureDirty = false;
    final next = value.trim();
    if (profileSignature == next) return;
    profileSignature = next;
    notifyListeners();
  }

  void setRequireFriendVerification(bool value) {
    if (requireFriendVerification == value) return;
    requireFriendVerification = value;
    notifyListeners();
  }

  void setShowOnlineStatus(bool value) {
    if (showOnlineStatus == value) return;
    showOnlineStatus = value;
    FriendDisplayPreferences.setOnlineStatus(value);
    notifyListeners();
  }

  void setReadReceipts(bool value) {
    if (readReceipts == value) return;
    readReceipts = value;
    FriendDisplayPreferences.setReadReceipts(value);
    notifyListeners();
  }

  void setFriendDiscovery({
    bool? qrCode,
    bool? businessCard,
    bool? group,
    bool? phone,
    bool? uid,
    bool? account,
    bool? email,
  }) {
    if (qrCode != null) allowQrCode = qrCode;
    if (businessCard != null) allowBusinessCard = businessCard;
    if (group != null) allowGroup = group;
    if (phone != null) allowPhone = phone;
    if (uid != null) allowUid = uid;
    if (account != null) allowAccount = account;
    if (email != null) allowEmail = email;
    notifyListeners();
  }

  void setLastSeenScope(String value) {
    if (lastSeenScope == value) return;
    lastSeenScope = value;
    notifyListeners();
  }

  void setMomentsVisibilityDays(int value) {
    if (momentsVisibilityDays == value) return;
    momentsVisibilityDays = value;
    notifyListeners();
  }

  void replaceMomentsHiddenFrom(Iterable<SettingsContactDraft> contacts) {
    momentsHiddenFrom
      ..clear()
      ..addEntries(contacts.map((item) => MapEntry(item.userId, item)));
    notifyListeners();
  }

  void replaceMomentsHiddenBy(Iterable<SettingsContactDraft> contacts) {
    momentsHiddenBy
      ..clear()
      ..addEntries(contacts.map((item) => MapEntry(item.userId, item)));
    notifyListeners();
  }

  void removeMomentsHiddenFrom(String userId) {
    if (momentsHiddenFrom.remove(userId) != null) notifyListeners();
  }

  void removeMomentsHiddenBy(String userId) {
    if (momentsHiddenBy.remove(userId) != null) notifyListeners();
  }

  void setBiometricPay(bool value) {
    if (biometricPay == value) return;
    biometricPay = value;
    notifyListeners();
  }

  void setFontSizeIndex(int value) {
    final next = value.clamp(0, 3);
    if (fontSizeIndex == next) return;
    fontSizeIndex = next;
    notifyListeners();
  }

  void updateNotifications({
    bool? closed,
    bool? callClosed,
    bool? quickAnswer,
    bool? notificationQuickReply,
    String? closedPreview,
    bool? opened,
    String? openedPreview,
    bool? messageSoundEnabled,
    String? messageSound,
    bool? callRingtoneEnabled,
    String? callRingtone,
    bool? vibration,
  }) {
    if (!isCurrentAccount) return;
    if (closed != null) {
      notifyWhenClosed = closed;
      _putBool('notify_when_closed', closed);
    }
    if (callClosed != null) callNotifyWhenClosed = callClosed;
    if (quickAnswer != null) {
      this.quickAnswer = quickAnswer;
      _putBool('notify_quick_answer', quickAnswer);
    }
    if (notificationQuickReply != null) {
      this.notificationQuickReply = notificationQuickReply;
      _putBool('notify_quick_reply', notificationQuickReply);
    }
    if (closedPreview != null) {
      closedNotificationPreview = closedPreview;
      _putString('notify_closed_preview', closedPreview);
    }
    if (opened != null) {
      notifyWhenOpen = opened;
      _putBool('notify_when_open', opened);
    }
    if (openedPreview != null) {
      openedNotificationPreview = openedPreview;
      _putString('notify_open_preview', openedPreview);
    }
    if (messageSoundEnabled != null) {
      this.messageSoundEnabled = messageSoundEnabled;
      _putBool('message_sound_enabled', messageSoundEnabled);
    }
    if (messageSound != null) {
      this.messageSound =
          MessageNotificationSoundIds.normalizedId(messageSound);
      _putString('message_sound', this.messageSound);
    }
    if (callRingtoneEnabled != null) {
      this.callRingtoneEnabled = callRingtoneEnabled;
      _putBool('call_ringtone_enabled', callRingtoneEnabled);
    }
    if (callRingtone != null) this.callRingtone = callRingtone;
    if (vibration != null) {
      this.vibration = vibration;
      _putBool('vibration', vibration);
    }
    if (closed != null ||
        opened != null ||
        closedPreview != null ||
        openedPreview != null ||
        notificationQuickReply != null ||
        messageSoundEnabled != null ||
        messageSound != null ||
        vibration != null) {
      MessageNotificationPreferences.notifyChanged(ownerUserId);
    }
    if (quickAnswer != null || callRingtoneEnabled != null) {
      CallNotificationPreferences.notifyChanged(ownerUserId);
    }
    notifyListeners();
  }

  void setChatBackground(String value) {
    if (chatBackgroundId == value && chatBackgroundImageBytes == null) return;
    chatBackgroundId = value;
    chatBackgroundImageBytes = null;
    notifyListeners();
  }

  void setChatBackgroundGallery(Uint8List bytes) {
    chatBackgroundId = 'gallery';
    chatBackgroundImageBytes = bytes;
    notifyListeners();
  }

  void resetChatBackground() {
    if (chatBackgroundId == 'default' && chatBackgroundImageBytes == null) {
      return;
    }
    chatBackgroundId = 'default';
    chatBackgroundImageBytes = null;
    notifyListeners();
  }

  void setProfileAvatarPreview(Uint8List bytes) {
    profileAvatarPreviewBytes = bytes;
    notifyListeners();
  }

  void clearProfileAvatarPreview() {
    if (profileAvatarPreviewBytes == null) return;
    profileAvatarPreviewBytes = null;
    notifyListeners();
  }

  void selectNode(String? value) {
    if (selectedNodeId == value) return;
    selectedNodeId = value;
    notifyListeners();
  }

  void markNodeTested() {
    nodeLastTestAt = DateTime.now();
    notifyListeners();
  }
}

@immutable
class SettingsContactDraft {
  const SettingsContactDraft({
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final String avatarUrl;
}
