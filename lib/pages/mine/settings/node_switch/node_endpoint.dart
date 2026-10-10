import 'package:openim_common/openim_common.dart';

/// The same effective addresses used by business requests and SDK startup.
class NodeEndpoint {
  const NodeEndpoint(
      {required this.chatApi, required this.imApi, required this.imWs});
  factory NodeEndpoint.current() => NodeEndpoint(
      chatApi: Config.appAuthUrl, imApi: Config.imApiUrl, imWs: Config.imWsUrl);
  final String chatApi, imApi, imWs;
  String get signature => '$chatApi|$imApi|$imWs';
}
