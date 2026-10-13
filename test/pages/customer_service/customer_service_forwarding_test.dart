import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/customer_service/data/data.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void forward(int port) => Config.useRuntimeNetworkRoute(RuntimeNetworkRoute(
    authUrl: 'http://127.0.0.1:20008',
    apiUrl: 'http://127.0.0.1:20002',
    wsUrl: 'ws://127.0.0.1:20001',
    customerServiceUrl: 'http://127.0.0.1:$port'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    forward(28815);
  });
  tearDown(() => Config.useRuntimeNetworkRoute(null));
  const config = CustomerServiceConfig();
  test('customer REST reads and multipart uploads use the fourth local ingress',
      () async {
    final adapter = _Adapter();
    final api = CustomerServiceApi(client: Dio()..httpClientAdapter = adapter);
    addTearDown(api.dispose);
    await api.listMessages(contactId: 'contact', conversationId: '41');
    await api.sendAttachment(
        contactId: 'contact',
        conversationId: '41',
        echoId: 'upload',
        filename: 'photo.png',
        path: '',
        bytes: [1, 2, 3]);
    expect(adapter.requests, hasLength(2));
    for (final request in adapter.requests) {
      expect(request.uri.host, '127.0.0.1');
      expect(request.uri.port, 28815);
      expect(request.uri.path, contains('/public/api/v1/inboxes/'));
      expect(request.headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('token')));
    }
    expect(adapter.requests.last.data, isA<FormData>());
  });
  test('ActionCable connects through the same forwarding port and keeps /cable',
      () async {
    final transport = _Transport();
    final cable = CustomerServiceCable(
        config: config,
        onMessage: (_) {},
        onTyping: (_) {},
        transport: transport);
    addTearDown(cable.dispose);
    cable.connect(pubsubToken: 'fixture', conversationId: '41');
    expect((await transport.started.future).toString(),
        'ws://127.0.0.1:28815/cable');
    await Future<void>.delayed(Duration.zero);
    cable.dispose();
    await Future<void>.delayed(Duration.zero);
  });
  test(
      'relative and same-origin attachment URLs are forwarded with queries intact',
      () {
    expect(config.resolveMediaUrl('/uploads/a.png'),
        'http://127.0.0.1:28815/uploads/a.png');
    expect(
        config.resolveMediaUrl(
            'http://lhins-14l2mj2j.3w3hbb07j0xz.eo.dnse5.com:8815/uploads/a.png?download=1'),
        'http://127.0.0.1:28815/uploads/a.png?download=1');
    expect(config.resolveMediaUrl('//lhins-14l2mj2j.3w3hbb07j0xz.eo.dnse5.com:8815/uploads/a.png'),
        'http://127.0.0.1:28815/uploads/a.png');
    expect(config.resolveMediaUrl('https://cdn.example/a.png'),
        'https://cdn.example/a.png');
    expect(config.resolveMediaUrl('https://lhins-14l2mj2j.3w3hbb07j0xz.eo.dnse5.com:8815/a.png'),
        'https://lhins-14l2mj2j.3w3hbb07j0xz.eo.dnse5.com:8815/a.png');
  });
  test('custom customer endpoint does not inherit production forwarding', () {
    const custom =
        CustomerServiceConfig(baseUrl: 'https://custom.example/support');
    expect(custom.normalizedBaseUrl, 'https://custom.example/support');
    expect(custom.cableUri.toString(), 'wss://custom.example/support/cable');
    Config.useRuntimeNetworkRoute(null);
    expect(config.normalizedBaseUrl, Config.customerServiceOriginUrl);
    expect(config.cableUri.toString(), 'ws://lhins-14l2mj2j.3w3hbb07j0xz.eo.dnse5.com:8815/cable');
  });
  test(
      'visitor session survives forwarding-port changes and resumes old conversation',
      () async {
    final adapter = _Adapter();
    final api = CustomerServiceApi(client: Dio()..httpClientAdapter = adapter);
    addTearDown(api.dispose);
    final original = CustomerServiceSessionStore(
        api: api,
        accountId: 'account',
        isActive: () => true,
        identifierFactory: () => 'visitor');
    addTearDown(original.dispose);
    final key = original.storageKey;
    final session = await original.ensure(name: 'Alice');
    forward(38815);
    final reopened = CustomerServiceSessionStore(
        api: api, accountId: 'account', isActive: () => true);
    addTearDown(reopened.dispose);
    final restored = await reopened.ensure(name: 'Alice');
    expect(reopened.storageKey, key);
    expect(restored.sourceId, session.sourceId);
    expect(restored.conversationId, session.conversationId);
    expect(
        adapter.requests.where((request) =>
            request.method == 'POST' && request.uri.path.endsWith('/contacts')),
        hasLength(1));
    expect(adapter.requests.last.uri.port, 38815);
  });
}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions request, Stream<Uint8List>? stream,
      Future<void>? cancel) async {
    requests.add(request);
    final Object body = request.method == 'GET'
        ? []
        : request.uri.path.endsWith('/contacts')
            ? {'source_id': 'contact', 'pubsub_token': 'fixture'}
            : request.uri.path.endsWith('/conversations')
                ? {'id': 41}
                : {'id': 7, 'content': '', 'message_type': 0};
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

class _Transport implements CustomerServiceTransport {
  final started = Completer<Uri>();
  @override
  Future<CustomerServiceConnection> connect(Uri uri) async {
    started.complete(uri);
    return _Connection();
  }
}

class _Connection implements CustomerServiceConnection {
  final controller = StreamController<dynamic>.broadcast();
  @override
  Stream<dynamic> get messages => controller.stream;
  @override
  void send(String message) {}
  @override
  Future<void> close() => controller.close();
}
