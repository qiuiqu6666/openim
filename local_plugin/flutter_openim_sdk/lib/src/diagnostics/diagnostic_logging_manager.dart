import 'package:flutter/services.dart';

/// Bounded native diagnostics; never persisted or simulated on the Dart side.
class DiagnosticLoggingManager {
  DiagnosticLoggingManager(this._channel);
  final MethodChannel _channel;

  Future<int> setDuration(int seconds) =>
      _invoke('setDiagnosticLogging', {'seconds': seconds.clamp(0, 900)});
  Future<int> remainingSeconds() => _invoke('getDiagnosticLoggingSeconds', {});

  Future<int> _invoke(String method, Map<String, Object> values) async {
    final result = await _channel.invokeMethod<int>(method, {
      'ManagerName': 'imManager',
      ...values,
    }).timeout(const Duration(seconds: 5));
    if (result == null || result < 0 || result > 900) {
      throw const FormatException('Invalid native diagnostic state');
    }
    return result;
  }
}
