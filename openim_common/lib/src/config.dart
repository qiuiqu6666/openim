import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:openim_common/openim_common.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class Config {
  static Future init(Function() runApp,
      {Future<void> Function()? prepareNetwork,
      void Function(Object)? onInitError}) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final path = (await getApplicationDocumentsDirectory()).path;
      cachePath = '$path/';
      await DataSp.init();
      await Hive.initFlutter(path);
      MediaKit.ensureInitialized();
      await prepareNetwork?.call();
      HttpUtil.init();
    } catch (error) {
      if (onInitError != null) {
        onInitError(error);
        return;
      }
    }

    runApp();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    final packageInfo = await PackageInfo.fromPlatform();
    _appName = packageInfo.appName;
  }

  static late String _appName;

  static late String cachePath;
  static RuntimeNetworkRoute? _runtimeNetworkRoute;

  static final networkRouteRevision = ValueNotifier<int>(0);

  static void useRuntimeNetworkRoute(RuntimeNetworkRoute? route) {
    _runtimeNetworkRoute = route;
    networkRouteRevision.value++;
  }

  static const customerServiceOriginUrl =
      'http://lhins-14l2mj2j.3w3hbb07j0xz.eo.dnse5.com:8815';
  static String? get customerServiceForwardUrl =>
      _runtimeNetworkRoute?.customerServiceUrl ??
      DataSp.getServerConfig()?['customerServiceUrl'];

  static const uiW = 375.0;
  static const uiH = 812.0;

  static const double textScaleFactor = 1.0;

  static const discoverPageURL = 'discover';
  static const allowSendMsgNotFriend = '1';
  // amap key
  static const webKey = 'webKey';
  static const webServerKey = 'webServerKey';
  static const locationHost = 'http://location.your-domain';

  static OfflinePushInfo get offlinePushInfo => OfflinePushInfo(
        title: _appName,
        desc: StrRes.offlineMessage,
        iOSBadgeCount: true,
        iOSPushSound: 'default',
      );

  static const friendScheme = "io.openim.app/addFriend/";
  static const groupScheme = "https://99chat.vip?group=";

  static const _host = '99chatapi.99chat.vip';

  static String get serverIp {
    String? ip;
    var server = DataSp.getServerConfig();
    if (null != server) {
      ip = server['serverIP'];
    }
    return ip == null || ip == '129.226.192.93' || ip == '127.0.0.1'
        ? _host
        : ip;
  }

  static String get appAuthUrl {
    if (_runtimeNetworkRoute case final route?) return route.authUrl;
    String? url;
    var server = DataSp.getServerConfig();
    if (null != server) {
      url = server['authUrl'];
    }
    return _currentEndpoint(url, 'https://99chatapi.99chat.vip',
        retired: 'http://127.0.0.1:10008',
        previous: 'http://129.226.192.93:10008');
  }

  static String get imApiUrl {
    if (_runtimeNetworkRoute case final route?) return route.apiUrl;
    String? url;
    var server = DataSp.getServerConfig();
    if (null != server) {
      url = server['apiUrl'];
    }
    return _currentEndpoint(url, 'https://99imapi.99chat.vip',
        retired: 'http://127.0.0.1:10002',
        previous: 'http://129.226.192.93:10002');
  }

  static String get imWsUrl {
    if (_runtimeNetworkRoute case final route?) return route.wsUrl;
    String? url;
    var server = DataSp.getServerConfig();
    if (null != server) {
      url = server['wsUrl'];
    }
    return _currentEndpoint(url, 'wss://websocket.99chat.vip',
        retired: 'ws://127.0.0.1:10001', previous: 'ws://129.226.192.93:10001');
  }

  // Migrate saved built-in routes without replacing custom deployments.
  static String _currentEndpoint(String? saved, String current,
      {required String retired, String? previous}) {
    final value = saved?.trim().replaceFirst(RegExp(r'/+$'), '');
    if (value == null ||
        value.isEmpty ||
        value == retired ||
        value == previous) {
      return current;
    }
    return value;
  }

  static int get logLevel {
    final saved = DataSp.getServerConfig()?['logLevel'];
    final parsed = int.tryParse(saved?.toString() ?? '');
    final fallback = kDebugMode ? 5 : 4;
    final level =
        parsed != null && parsed >= 0 && parsed <= 6 ? parsed : fallback;
    // OpenIM core 3.8.3: 3=Warn, 4=Info, 5=Debug, 6=DebugWithSQL.
    // Keep Info diagnostics in production, but disable Debug/SQL output even
    // when a previous installation persisted a verbose setting.
    return !kDebugMode && level > 4 ? 4 : level;
  }

  static String get callingUrl => appAuthUrl;

  static bool get logStandardOutput => kDebugMode;
}
