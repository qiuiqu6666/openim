import 'dart:io';

/// Small injectable transport; tests never connect to the approved deployment.
abstract class CustomerServiceTransport {
  Future<CustomerServiceConnection> connect(Uri uri);
}

abstract class CustomerServiceConnection {
  Stream<dynamic> get messages;
  void send(String message);
  Future<void> close();
}

class NativeCustomerServiceTransport implements CustomerServiceTransport {
  const NativeCustomerServiceTransport();

  @override
  Future<CustomerServiceConnection> connect(Uri uri) async =>
      _NativeConnection(await WebSocket.connect(uri.toString()));
}

class _NativeConnection implements CustomerServiceConnection {
  _NativeConnection(this._socket);
  final WebSocket _socket;

  @override
  Stream<dynamic> get messages => _socket;
  @override
  void send(String message) => _socket.add(message);
  @override
  Future<void> close() async {
    await _socket.close();
  }
}
