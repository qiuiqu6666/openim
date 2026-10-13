import 'package:openim_common/openim_common.dart' show Config;

class GameShieldRule {
  const GameShieldRule(this.appId, {this.groupName = ''});
  final String appId, groupName;
  bool get configured => appId.trim().isNotEmpty;
}

class GameShieldSettings {
  const GameShieldSettings(
      {this.enabled = false,
      this.licenseToken = '',
      this.auth = const GameShieldRule(''),
      this.imApi = const GameShieldRule(''),
      this.imWs = const GameShieldRule(''),
      this.customerService = const GameShieldRule(''),
      this.customerServiceBaseUrl = Config.customerServiceOriginUrl});
  final bool enabled;
  final String licenseToken;
  final GameShieldRule auth, imApi, imWs, customerService;
  final String customerServiceBaseUrl;

  static const environment = GameShieldSettings(
    enabled: bool.fromEnvironment('GAMESHIELD_ENABLED'),
    licenseToken: String.fromEnvironment('GAMESHIELD_TOKEN'),
    auth: GameShieldRule(String.fromEnvironment('GAMESHIELD_AUTH_APP_ID'),
        groupName: String.fromEnvironment('GAMESHIELD_AUTH_GROUP')),
    imApi: GameShieldRule(String.fromEnvironment('GAMESHIELD_IM_API_APP_ID'),
        groupName: String.fromEnvironment('GAMESHIELD_IM_API_GROUP')),
    imWs: GameShieldRule(String.fromEnvironment('GAMESHIELD_IM_WS_APP_ID'),
        groupName: String.fromEnvironment('GAMESHIELD_IM_WS_GROUP')),
    customerService: GameShieldRule(
        String.fromEnvironment('GAMESHIELD_CUSTOMER_SERVICE_APP_ID'),
        groupName: String.fromEnvironment('GAMESHIELD_CUSTOMER_SERVICE_GROUP')),
    customerServiceBaseUrl: String.fromEnvironment('CUSTOMER_SERVICE_BASE_URL',
        defaultValue: Config.customerServiceOriginUrl),
  );
}
