import 'package:openim/pages/customer_service/customer_service_controller.dart';
import 'package:openim/pages/customer_service/data/data.dart';

const customerServiceTestConfig = CustomerServiceConfig(
    baseUrl: 'https://support.invalid/kefu', inboxIdentifier: 'test-inbox');
const customerServiceTestSession = CustomerServiceSession(
    identifier: 'test-visitor',
    sourceId: 'test-contact',
    pubsubToken: 'test-public-room',
    conversationId: '42');

CustomerServiceMessage customerServiceTestMessage(String id, String content,
        {String echoId = '',
        String conversationId = '42',
        int type = 1,
        DateTime? createdAt}) =>
    CustomerServiceMessage(
        id: id,
        content: content,
        messageType: type,
        echoId: echoId,
        conversationId: conversationId,
        attachments: const [],
        createdAt: createdAt);

class CustomerServiceTestSend {
  const CustomerServiceTestSend(this.content, this.echoId);
  final String content, echoId;
}

class CustomerServiceTestApi extends CustomerServiceApi {
  CustomerServiceTestApi() : super(config: customerServiceTestConfig);

  List<CustomerServiceMessage> history = [];
  Future<List<CustomerServiceMessage>> Function()? onList;
  Future<CustomerServiceMessage> Function(CustomerServiceTestSend request)?
      onSend;
  Future<CustomerServiceMessage> Function(String echoId)? onAttachment;
  final sends = <CustomerServiceTestSend>[];
  int listCalls = 0;
  bool disposed = false;

  @override
  Future<List<CustomerServiceMessage>> listMessages(
      {required String contactId, required String conversationId}) async {
    assert(contactId == customerServiceTestSession.sourceId);
    assert(conversationId == customerServiceTestSession.conversationId);
    listCalls++;
    if (onList != null) return onList!();
    return history;
  }

  @override
  Future<CustomerServiceMessage> sendText(
      {required String contactId,
      required String conversationId,
      required String content,
      required String echoId}) async {
    assert(contactId == customerServiceTestSession.sourceId);
    assert(conversationId == customerServiceTestSession.conversationId);
    final request = CustomerServiceTestSend(content, echoId);
    sends.add(request);
    if (onSend != null) return onSend!(request);
    return customerServiceTestMessage('${100 + sends.length}', content,
        echoId: echoId, type: 0, createdAt: DateTime.utc(2026, 1, 1));
  }

  @override
  Future<CustomerServiceMessage> sendAttachment(
      {required String contactId,
      required String conversationId,
      required String echoId,
      required String filename,
      required String path,
      List<int>? bytes,
      int width = 0,
      int height = 0,
      String content = '',
      String thumbnailPath = '',
      List<int>? thumbnailBytes}) async {
    if (onAttachment == null) {
      throw StateError('Configure the local attachment response in this test');
    }
    return onAttachment!(echoId);
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class CustomerServiceTestStore extends CustomerServiceSessionStore {
  CustomerServiceTestStore({required super.api, required super.isActive})
      : super(accountId: 'test-account');
  Future<CustomerServiceSession> Function()? onEnsure;
  int ensureCalls = 0;
  bool disposed = false;

  @override
  Future<CustomerServiceSession> ensure(
      {required String name, String avatarUrl = ''}) async {
    ensureCalls++;
    if (onEnsure != null) return onEnsure!();
    return customerServiceTestSession;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class CustomerServiceTestCable extends CustomerServiceCable {
  CustomerServiceTestCable(
      {required super.onMessage,
      required super.onTyping,
      required super.onConnected,
      required super.onDisconnected})
      : super(config: customerServiceTestConfig);
  final connections = <({String pubsubToken, String conversationId})>[];
  int suspensions = 0;
  bool disposed = false;

  @override
  void connect({required String pubsubToken, required String conversationId}) {
    connections.add((pubsubToken: pubsubToken, conversationId: conversationId));
  }

  @override
  void suspend() => suspensions++;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  void message(CustomerServiceMessage message) => onMessage(message);
  void typing(bool value) => onTyping(value);
  void connected() => onConnected?.call();
  void disconnect() => onDisconnected?.call();
}

class CustomerServiceTestHarness {
  CustomerServiceTestHarness({Future<String> Function()? officialURLLoader}) {
    api = CustomerServiceTestApi();
    store = CustomerServiceTestStore(api: api, isActive: () => active);
    controller = CustomerServiceController(
        api: api,
        sessionStore: store,
        isActive: () => active,
        name: 'Test user',
        officialURLLoader:
            officialURLLoader ?? () async => 'https://official.invalid',
        cableFactory: (message, typing, connected, disconnected) => cable =
            CustomerServiceTestCable(
                onMessage: message,
                onTyping: typing,
                onConnected: connected,
                onDisconnected: disconnected));
  }
  bool active = true;
  late final CustomerServiceTestApi api;
  late final CustomerServiceTestStore store;
  late final CustomerServiceTestCable cable;
  late final CustomerServiceController controller;

  void dispose() {
    if (!api.disposed) controller.dispose();
  }
}
