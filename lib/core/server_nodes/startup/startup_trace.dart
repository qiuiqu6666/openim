import 'dart:convert';
import 'dart:io';
import 'package:openim_common/openim_common.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

/// Callers supply only fixed events, route codes, timings and error types.
class StartupTrace {
  StartupTrace({void Function(String)? sink}) : _sink = sink ?? _write;
  static Future<void> _writes = Future.value();
  static void _write(String line) {
    // Unlike Logger.print, these sanitized diagnostics also survive release
    // startup before the IM SDK logger exists. Retain at most two 256 KiB files.
    // ignore: avoid_print
    print(line);
    _writes = _writes.then((_) async {
      try {
        final folder = Directory('${Config.cachePath}startup_diagnostics');
        await folder.create(recursive: true);
        final file = File('${folder.path}/startup.jsonl');
        if (await file.exists() && await file.length() > 256 * 1024) {
          await file.copy('${folder.path}/startup.previous.jsonl');
          await file.writeAsString('');
        }
        await file.writeAsString('$line\n', mode: FileMode.append);
      } catch (_) {
        // Disk availability must never block startup or trigger another retry.
      }
    });
  }

  final void Function(String) _sink;
  final id = const Uuid().v4();
  final _clock = Stopwatch()..start();
  void event(String event, [Map<String, Object?> fields = const {}]) =>
      _sink(jsonEncode({
        'startupTraceId': id,
        'event': event,
        'elapsedMs': _clock.elapsedMilliseconds,
        'at': DateTime.now().toUtc().toIso8601String(),
        ...fields
      }));
  Future<void> metadata() async {
    String version = 'unknown';
    try {
      final info =
          await PackageInfo.fromPlatform().timeout(const Duration(seconds: 1));
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    event(
        'startup', {'version': version, 'platform': Platform.operatingSystem});
  }
}
