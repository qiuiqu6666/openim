import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:sprintf/sprintf.dart';
import 'package:uuid/uuid.dart';

class DataSp {
  static const _loginCertificate = 'loginCertificate';
  static const _loginAccount = 'loginAccount';
  static const _server = "server";
  static const _ip = 'ip';
  static const _deviceID = 'deviceID';
  static const _ignoreUpdate = 'ignoreUpdate';
  static const _language = "language";
  static const _groupApplication = "%s_groupApplication";
  static const _friendApplication = "%s_friendApplication";

  static const _screenPassword = '%s_screenPassword';
  static const _enabledBiometric = '%s_enabledBiometric';
  static const _enabledBiometricPay = '%s_enabledBiometricPay';
  static const _chatFontSizeFactor = '%s_chatFontSizeFactor';
  static const _chatBackground = '%s_chatBackground_%s';
  static const _loginType = 'loginType';
  static const _meetingInProgress = '%_meetingInProgress';

  DataSp._();

  static init() async {
    await SpUtil().init();
  }

  static String getKey(String key, {String key2 = ""}) {
    return sprintf(key, [OpenIM.iMManager.userID, key2]);
  }

  static String? get imToken => getLoginCertificate()?.imToken;

  static String? get chatToken => getLoginCertificate()?.chatToken;

  static String? get userID => getLoginCertificate()?.userID;

  static Future<bool>? putLoginCertificate(LoginCertificate lc) {
    return SpUtil().putObject(_loginCertificate, lc);
  }

  static Future<bool>? putLoginAccount(Map map) {
    return SpUtil().putObject(_loginAccount, map);
  }

  static LoginCertificate? getLoginCertificate() {
    return SpUtil()
        .getObj(_loginCertificate, (v) => LoginCertificate.fromJson(v.cast()));
  }

  static Future<bool>? removeLoginCertificate() {
    return SpUtil().remove(_loginCertificate);
  }

  static Map? getLoginAccount() {
    return SpUtil().getObject(_loginAccount);
  }

  static Future<bool>? putServerConfig(Map<String, String> config) {
    return SpUtil().putObject(_server, config);
  }

  static Map? getServerConfig() {
    return SpUtil().getObject(_server);
  }

  static Future<bool>? putServerIP(String ip) {
    return SpUtil().putString(ip, ip);
  }

  static String? getServerIP() {
    return SpUtil().getString(_ip);
  }

  static String getDeviceID() {
    String id = SpUtil().getString(_deviceID) ?? '';
    if (id.isEmpty) {
      id = const Uuid().v4();
      SpUtil().putString(_deviceID, id);
    }
    return id;
  }

  static Future<String>? _loginDeviceIDRepair;

  /// Login requires a durable UUID. Repair legacy values before freezing an
  /// attempt, then reuse the same identity for its password and SMS requests.
  static Future<String> ensureLoginDeviceID() async {
    final pending = _loginDeviceIDRepair;
    if (pending != null) return pending;
    final value = SpUtil().getDynamic(_deviceID);
    if (value is String &&
        RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$')
            .hasMatch(value)) {
      return value;
    }
    final repair = () async {
      final id = const Uuid().v4();
      if (await SpUtil().putString(_deviceID, id) != true) {
        throw StateError('Device identity could not be stored');
      }
      return id;
    }();
    _loginDeviceIDRepair = repair;
    try {
      return await repair;
    } finally {
      if (identical(_loginDeviceIDRepair, repair)) _loginDeviceIDRepair = null;
    }
  }

  static Future<bool>? putIgnoreVersion(String version) {
    return SpUtil().putString(_ignoreUpdate, version);
  }

  static String? getIgnoreVersion() {
    return SpUtil().getString(_ignoreUpdate);
  }

  static Future<bool>? putLanguage(int index) {
    return SpUtil().putInt(_language, index);
  }

  static int? getLanguage() {
    // Older installations may have stored this preference as a string.
    // Read the raw value so a stale type cannot prevent the app from building.
    final value = SpUtil().getDynamic(_language);
    final index = value is int
        ? value
        : value is String
            ? int.tryParse(value.trim())
            : null;
    return index != null && index >= 0 && index <= 2 ? index : 0;
  }

  static Future<bool>? putHaveReadUnHandleGroupApplication(
      List<String> idList) {
    return SpUtil().putStringList(getKey(_groupApplication), idList);
  }

  static Future<bool>? putHaveReadUnHandleFriendApplication(
      List<String> idList) {
    return SpUtil().putStringList(getKey(_friendApplication), idList);
  }

  static List<String>? getHaveReadUnHandleGroupApplication() {
    return SpUtil().getStringList(getKey(_groupApplication), defValue: []);
  }

  static List<String>? getHaveReadUnHandleFriendApplication() {
    return SpUtil().getStringList(getKey(_friendApplication), defValue: []);
  }

  static Future<bool>? putLockScreenPassword(String password) {
    return SpUtil().putString(getKey(_screenPassword), password);
  }

  static Future<bool>? clearLockScreenPassword() {
    return SpUtil().remove(getKey(_screenPassword));
  }

  static String? getLockScreenPassword() {
    return SpUtil().getString(getKey(_screenPassword), defValue: null);
  }

  static Future<bool>? openBiometric() {
    return SpUtil().putBool(getKey(_enabledBiometric), true);
  }

  static bool? isEnabledBiometric() {
    return SpUtil().getBool(getKey(_enabledBiometric), defValue: null);
  }

  static bool isEnabledBiometricPay({String? accountID}) =>
      SpUtil().getBool(
          sprintf(_enabledBiometricPay, [accountID ?? OpenIM.iMManager.userID]),
          defValue: false) ??
      false;

  static Future<bool>? setBiometricPay(bool enabled, {String? accountID}) =>
      SpUtil().putBool(
          sprintf(_enabledBiometricPay, [accountID ?? OpenIM.iMManager.userID]),
          enabled);

  static Map? getBiometricSettings(String accountID) =>
      SpUtil().getObject('${accountID}_biometricSettings');

  static Future<bool>? putBiometricSettings(
          String accountID, Map<String, dynamic> settings) =>
      SpUtil().putObject('${accountID}_biometricSettings', settings);

  static Future<bool>? closeBiometric() {
    return SpUtil().remove(getKey(_enabledBiometric));
  }

  static Future<bool>? putChatFontSizeFactor(double factor) {
    return SpUtil().putDouble(getKey(_chatFontSizeFactor), factor);
  }

  static double getChatFontSizeFactor() {
    return SpUtil().getDouble(
      getKey(_chatFontSizeFactor),
      defValue: Config.textScaleFactor,
    )!;
  }

  static Future<bool>? putChatBackground(String toUid, String path) {
    return SpUtil().putString(getKey(_chatBackground, key2: toUid), path);
  }

  static String? getChatBackground(String toUid) {
    return SpUtil().getString(getKey(_chatBackground, key2: toUid));
  }

  static Future<bool>? clearChatBackground(String toUid) {
    return SpUtil().remove(getKey(_chatBackground, key2: toUid));
  }

  static Future<bool>? putLoginType(int type) {
    return SpUtil().putInt(_loginType, type);
  }

  static int getLoginType() {
    return SpUtil().getInt(_loginType) ?? 0;
  }

  static Future<bool>? putMeetingInProgress(String meetingID) {
    return SpUtil().putString(getKey(_meetingInProgress), meetingID);
  }

  static String? getMeetingInProgress() {
    return SpUtil().getString(
      getKey(_meetingInProgress),
    );
  }

  static Future<bool>? removeMeetingInProgress() {
    return SpUtil().remove(getKey(_meetingInProgress));
  }
}
