import 'dart:async';
import 'package:flutter/foundation.dart';

class DiagnosticLoggingController extends ChangeNotifier {
  DiagnosticLoggingController({required this.read, required this.write});
  final Future<int> Function() read;
  final Future<int> Function(int) write;
  int? remaining;
  bool busy = false;
  bool failed = false;
  bool _disposed = false;
  bool _active = true;
  Timer? _refreshTimer;

  Future<void> refresh() => _run(read);
  Future<void> setEnabled(bool enabled) => _run(() => write(enabled ? 600 : 0));

  void setActive(bool active) {
    _active = active;
    _refreshTimer?.cancel();
    if (active) unawaited(refresh());
  }

  Future<void> _run(Future<int> Function() operation) async {
    if (busy || _disposed) return;
    _refreshTimer?.cancel();
    busy = true;
    notifyListeners();
    try {
      final value = await operation();
      if (_disposed) return;
      if (value < 0 || value > 900) {
        throw const FormatException('Invalid duration');
      }
      remaining = value;
      failed = false;
    } catch (_) {
      if (_disposed) return;
      failed = true;
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
        if (_active && !failed && (remaining ?? 0) > 0) {
          _refreshTimer = Timer(const Duration(seconds: 5), refresh);
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    super.dispose();
  }
}
