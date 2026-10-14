import 'package:openim_common/openim_common.dart';

/// One deployment route; its three addresses always change together.
class NodeEndpoint {
  const NodeEndpoint(
      {required this.chatApi,
      required this.imApi,
      required this.imWs,
      this.customerServiceUrl});

  factory NodeEndpoint.current() => NodeEndpoint(
      chatApi: Config.appAuthUrl,
      imApi: Config.imApiUrl,
      imWs: Config.imWsUrl,
      customerServiceUrl:
          Config.customerServiceForwardUrl ?? Config.customerServiceOriginUrl);

  static const direct = NodeEndpoint(
      chatApi: 'https://99chatapi.99chat.vip',
      imApi: 'https://99imapi.99chat.vip',
      imWs: 'wss://websocket.99chat.vip',
      customerServiceUrl:
          'http://lhins-14l2mj2j.3w3hbb07j0xz.eo.dnse5.com:8815');
  static const backup = NodeEndpoint(
      chatApi: 'http://lhins-14l2mj2j.3w3hbb07j0xz.eo.dnse5.com:10008',
      imApi: 'http://lhins-14l2mj2j.3w3hbb07j0xz.eo.dnse5.com:10002',
      imWs: 'ws://lhins-14l2mj2j.3w3hbb07j0xz.eo.dnse5.com:10001',
      customerServiceUrl:
          'http://lhins-14l2mj2j.3w3hbb07j0xz.eo.dnse5.com:8815');
  static const shield = NodeEndpoint(
      chatApi: 'http://127.0.0.1:10008',
      imApi: 'http://127.0.0.1:10002',
      imWs: 'ws://127.0.0.1:10001',
      customerServiceUrl: 'http://127.0.0.1:8815');
  static const builtIn = [direct, backup];
  static List<NodeEndpoint> selectable(NodeEndpoint current) =>
      [...builtIn, shield].any((node) => node.signature == current.signature)
          ? [...builtIn, shield]
          : [current];

  final String chatApi, imApi, imWs;
  final String? customerServiceUrl;

  /// Compact support marker; custom deployments deliberately have no number.
  String? get diagnosticCode {
    if (signature == shield.signature) return '3';
    final index = builtIn.indexWhere((node) => node.signature == signature);
    return index < 0 ? null : '${index + 1}';
  }

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
