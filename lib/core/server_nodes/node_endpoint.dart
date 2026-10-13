import 'package:openim_common/openim_common.dart';

/// One deployment route; its three addresses always change together.
class NodeEndpoint {
  const NodeEndpoint(
      {required this.chatApi, required this.imApi, required this.imWs});

  factory NodeEndpoint.current() => NodeEndpoint(
      chatApi: Config.appAuthUrl, imApi: Config.imApiUrl, imWs: Config.imWsUrl);

  static const direct = NodeEndpoint(
      chatApi: 'http://lhins-14l2mj2j.3w3hbb07j0xz.eo.dnse5.com:10008',
      imApi: 'http://lhins-14l2mj2j.3w3hbb07j0xz.eo.dnse5.com:10002',
      imWs: 'ws://lhins-14l2mj2j.3w3hbb07j0xz.eo.dnse5.com:10001');
  static const builtIn = [direct];

  final String chatApi, imApi, imWs;
  String get signature => [chatApi, imApi, imWs]
      .map((value) => value.trim().replaceFirst(RegExp(r'/+$'), ''))
      .join('|');

  /// Custom servers belong to a different deployment and must not inherit
  /// production fallback routes or send their saved credentials to them.
  static List<NodeEndpoint> candidates(NodeEndpoint current) =>
      builtIn.any((node) => node.signature == current.signature)
          ? builtIn
          : [current];
}
