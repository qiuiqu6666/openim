import 'conversation_batch_read_api.dart';

/// Freeze every target before writing; retry only failed frozen watermarks.
/// Transport errors propagate because the outcome may be unknown. Never fall
/// back to a fresh whole-conversation read, which could consume a new message.
Future<int> runServerConversationReadBatch({
  required Future<List<BatchReadTarget>> Function(String, List<String>?)
      prepare,
  required Future<Set<String>> Function(List<BatchReadTarget>) apply,
  required bool Function() isCurrent,
  required void Function(int, int) progress,
  required void Function(List<BatchReadTarget>) confirmed,
  String scope = 'selected',
  List<String> conversationIDs = const [],
}) async {
  final targets = <String, BatchReadTarget>{};
  if (scope == 'selected') {
    final ids = conversationIDs.toSet().toList();
    for (var offset = 0; offset < ids.length && isCurrent(); offset += 1000) {
      final end = (offset + 1000).clamp(0, ids.length);
      for (final target in await prepare(scope, ids.sublist(offset, end))) {
        targets[target.conversationID] = target;
      }
    }
  } else if (isCurrent()) {
    for (final target in await prepare(scope, null)) {
      targets[target.conversationID] = target;
    }
  }
  if (!isCurrent()) return targets.length;
  final rows = targets.values.toList();
  var done = 0, failures = 0;
  progress(0, rows.length);
  for (var offset = 0; offset < rows.length && isCurrent(); offset += 100) {
    final end = (offset + 100).clamp(0, rows.length);
    var pending = rows.sublist(offset, end);
    for (var attempt = 0; attempt < 2 && pending.isNotEmpty; attempt++) {
      if (!isCurrent()) return failures + rows.length - done;
      final succeeded = await apply(pending);
      if (!isCurrent()) return failures + rows.length - done;
      confirmed(
          pending.where((t) => succeeded.contains(t.conversationID)).toList());
      pending =
          pending.where((t) => !succeeded.contains(t.conversationID)).toList();
    }
    failures += pending.length;
    done = end;
    progress(done, rows.length);
  }
  return failures + rows.length - done;
}
