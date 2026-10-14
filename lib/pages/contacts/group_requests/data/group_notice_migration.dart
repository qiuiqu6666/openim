import 'package:openim_common/openim_common.dart';
import '../../request_history/data/request_history_store.dart';

/// Upload previous on-device dismissals once, in bounded idempotent batches.
Future<void> migrateGroupNotices(
    String owner,
    Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
        send) async {
  final key = 'group_notices_server_migrated_v1_${Uri.encodeComponent(owner)}';
  if (SpUtil().getString(key) == 'done') return;
  final legacy =
      RequestHistoryStore(owner, RequestHistoryKind.group).groupMigration;
  final items = legacy['items'] as List<Map<String, dynamic>>;
  final through = legacy['through'] as int;
  if (items.isEmpty && through > 0) {
    await send('migrate', {'through': through, 'items': <dynamic>[]});
  }
  for (var offset = 0; offset < items.length; offset += 100) {
    await send('migrate',
        {'through': through, 'items': items.skip(offset).take(100).toList()});
  }
  if (await SpUtil().putString(key, 'done') != true) {
    throw StateError('Could not save group notice migration');
  }
}
