import 'dart:async';

import 'package:flutter/services.dart';
import '../queries/sdk_query_gate.dart';

/// Keep the actual native request alive in one slot even after a UI timeout.
class IMNativeConnectionWake {
  IMNativeConnectionWake(
      {required this.channel,
      required this.isCurrentSession,
      required this.isDisconnected});
  final MethodChannel channel;
  final bool Function() isCurrentSession;
  final bool Function() isDisconnected;
  final _requests = SdkQueryGate<void>();

  Future<void> wake(bool Function() isCurrentAttempt) => wakeIMConnection(
      channel: channel,
      isCurrent: isCurrentAttempt,
      isDisconnected: isDisconnected,
      invokeNative: (method, arguments) => _requests.run(
          // A pre-background ACK cannot stand in for the new foreground
          // report. Keep one native request at a time, but issue the new
          // attempt after the obsolete request releases its slot.
          (method, isCurrentAttempt),
          () => channel.invokeMethod<void>(method, arguments),
          timeout: const Duration(seconds: 30),
          isCurrent: () => isCurrentSession() && isCurrentAttempt()));

  void close() => _requests.close();
}

/// Ask the server to mark this device foreground and retry incremental sync.
/// The pinned SDK closes its socket on networkStatusChanged, so use that only
/// when the current transport is confirmed disconnected. Slow replies
/// alone cannot prove that closing the socket would help.
Future<void> wakeIMConnection({
  required MethodChannel channel,
  required bool Function() isCurrent,
  bool Function()? isDisconnected,
  Duration foregroundTimeout = const Duration(seconds: 12),
  Future<void> Function(String method, Map<String, Object> arguments)?
      invokeNative,
}) async {
  Future<void> notify(String method, Map<String, Object> arguments) async {
    if (!isCurrent()) return;
    final envelope = <String, Object>{
      // Both native plugin dispatchers require this envelope, even though
      // these two methods are not exposed by the plugin's Dart IMManager.
      'ManagerName': 'imManager',
      'operationID': DateTime.now().microsecondsSinceEpoch.toString(),
      ...arguments,
    };
    if (invokeNative != null) {
      await invokeNative(method, envelope);
    } else {
      await channel.invokeMethod<void>(method, envelope);
    }
  }

  final reconnectRequested = isCurrent() && isDisconnected?.call() == true;
  if (reconnectRequested) {
    await notify('networkStatusChanged', {});
  }
  try {
    await notify('setAppBackgroundStatus', {'isBackground': false})
        .timeout(foregroundTimeout);
  } on TimeoutException {
    // Timeout is not native cancellation and is not evidence of a dead socket.
    rethrow;
  } on PlatformException {
    // A late foreground callback must not disconnect a successor session or
    // a new foreground attempt. The recovery owner supplies an attempt fence.
    if (!isCurrent() || isDisconnected?.call() != true) rethrow;
    if (!reconnectRequested) await notify('networkStatusChanged', {});
    rethrow;
  }
}
