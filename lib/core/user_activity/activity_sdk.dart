import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'activity_runtime.dart';
import 'activity_collector.dart';

Future<T> observeUserActivity<T>(
    String action, Future<T> Function() run) async {
  final runtime = ActivityRuntime.instance;
  ActivitySession? owner;
  try {
    owner = runtime.captureOwner();
  } catch (_) {/* Optional observation. */}
  void record(String result) {
    try {
      runtime.actionFor(owner, action, result: result);
    } catch (_) {/* Never replace a business result. */}
  }

  try {
    final result = await run();
    record('success');
    return result;
  } catch (_) {
    record('unconfirmed');
    rethrow;
  }
}

String messageActivity(int? type) => switch (type) {
      MessageType.text ||
      MessageType.atText ||
      MessageType.quote ||
      MessageType.advancedText =>
        'message_text',
      MessageType.picture => 'message_image',
      MessageType.voice => 'message_voice',
      MessageType.video => 'message_video',
      MessageType.file => 'message_file',
      _ => 'message_other',
    };
