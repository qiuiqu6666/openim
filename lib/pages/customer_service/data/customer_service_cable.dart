import 'dart:async';
import 'dart:convert';

import 'customer_service_config.dart';
import 'customer_service_message.dart';
import 'customer_service_transport.dart';

/// Page-owned ActionCable subscription. Every callback belongs to a connection
/// generation and an explicit conversation; suspended pages receive no events.
class CustomerServiceCable {
  CustomerServiceCable({
    required this.config,
    required this.onMessage,
    required this.onTyping,
    this.onConnected,
    this.onDisconnected,
    CustomerServiceTransport transport = const NativeCustomerServiceTransport(),
  }) : _transport = transport;

  final CustomerServiceConfig config;
  final void Function(CustomerServiceMessage) onMessage;
  final void Function(bool) onTyping;
  final void Function()? onConnected;
  final void Function()? onDisconnected;
  final CustomerServiceTransport _transport;
  CustomerServiceConnection? _connection;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnect;
  String _pubsubToken = '', _conversationId = '';
  int _generation = 0, _attempt = 0;
  bool _suspended = true, _disposed = false, _confirmed = false;

  void connect({required String pubsubToken, required String conversationId}) {
    if (_disposed) return;
    _pubsubToken = pubsubToken.trim();
    _conversationId = conversationId.trim();
    _suspended = false;
    _attempt = 0;
    final generation = ++_generation;
    _reconnect?.cancel();
    _reconnect = null;
    unawaited(_open(generation));
  }

  bool _live(int generation) =>
      !_disposed && !_suspended && generation == _generation;

  Future<void> _open(int generation) async {
    if (!_live(generation) || _pubsubToken.isEmpty || _conversationId.isEmpty) {
      return;
    }
    await _closeConnection();
    if (!_live(generation)) return;
    CustomerServiceConnection? connecting;
    try {
      connecting = await _transport.connect(config.cableUri);
      if (!_live(generation)) {
        await connecting.close();
        return;
      }
      _connection = connecting;
      _confirmed = false;
      _subscription = connecting.messages.listen(
        (raw) => _onRaw(raw, generation),
        onError: (_) => _scheduleReconnect(generation),
        onDone: () => _scheduleReconnect(generation),
      );
      connecting.send(jsonEncode({
        'command': 'subscribe',
        'identifier': jsonEncode({
          'channel': 'RoomChannel',
          'pubsub_token': _pubsubToken,
        }),
      }));
    } catch (_) {
      if (identical(_connection, connecting)) _connection = null;
      if (connecting != null) {
        try {
          await connecting.close();
        } catch (_) {}
      }
      _scheduleReconnect(generation);
    }
  }

  void _onRaw(dynamic raw, int generation) {
    if (!_live(generation)) return;
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! Map) return;
      final type = decoded['type'];
      if (type == 'confirm_subscription') {
        if (!_confirmed) {
          _confirmed = true;
          _attempt = 0;
          onConnected?.call();
        }
        return;
      }
      if (type == 'reject_subscription' || type == 'disconnect') {
        _scheduleReconnect(generation);
        return;
      }
      final payload = decoded['message'];
      if (payload is! Map) return;
      final event = payload['event']?.toString() ?? '';
      final data = payload['data'];
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);
      final id = _eventConversation(map,
          typing: event.startsWith('conversation_typing_'));
      if (id != _conversationId) return;
      if (event == 'conversation_typing_on') {
        onTyping(true);
      } else if (event == 'conversation_typing_off') {
        onTyping(false);
      } else if (event == 'message.created' || event == 'message.updated') {
        onMessage(CustomerServiceMessage.fromJson(map, config: config));
      }
    } catch (_) {
      // Ignore malformed individual frames without losing the subscription.
    }
  }

  void _scheduleReconnect(int generation) {
    if (!_live(generation) || _reconnect != null) return;
    _confirmed = false;
    onTyping(false);
    onDisconnected?.call();
    final seconds = (2 * (1 << (_attempt > 4 ? 4 : _attempt))).clamp(2, 30);
    _attempt++;
    _reconnect = Timer(Duration(seconds: seconds), () {
      _reconnect = null;
      if (_live(generation)) unawaited(_open(generation));
    });
  }

  void suspend() {
    if (_disposed) return;
    _suspended = true;
    _generation++;
    _reconnect?.cancel();
    _reconnect = null;
    onTyping(false);
    unawaited(_closeConnection());
  }

  void dispose() {
    if (_disposed) return;
    suspend();
    _disposed = true;
  }

  Future<void> _closeConnection() async {
    final subscription = _subscription;
    final connection = _connection;
    _subscription = null;
    _connection = null;
    await subscription?.cancel();
    try {
      await connection?.close();
    } catch (_) {}
  }
}

String _eventConversation(Map<String, dynamic> data, {required bool typing}) {
  final conversation = data['conversation'];
  return (data['conversation_id'] ??
              data['conversationId'] ??
              (conversation is Map ? conversation['id'] : null) ??
              // Chatwoot typing frames contain the conversation itself.
              (typing ? data['id'] : null))
          ?.toString() ??
      '';
}
