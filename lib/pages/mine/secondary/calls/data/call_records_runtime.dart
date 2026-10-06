import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'call_record_sync_binding.dart';
import 'call_records_repository.dart';

/// The SDK listener and Recent Calls share the existing account cache owner.
class CallRecordsRuntime {
  CallRecordsRuntime._();
  static CallRecordsRepository? _repository;
  static CallRecordSyncBinding? _binding;
  static Stream<String>? _businessNotifications;
  static Stream<void>? _reconnected;

  static CallRecordsRepository get repository =>
      forAccount(Get.find<CacheController>());

  static CallRecordsRepository? get currentRepository => _repository;

  static CallRecordsRepository forAccount(CacheController cache) {
    final value = _repository;
    if (value != null && identical(value.cache, cache) && value.isCurrent) {
      return value;
    }
    _binding?.dispose();
    _binding = null;
    value?.dispose();
    final next = _repository = CallRecordsRepository(cache: cache);
    _attachSync(next);
    return next;
  }

  static void bindSync({
    required Stream<String> businessNotifications,
    required Stream<void> reconnected,
  }) {
    detachSync();
    _businessNotifications = businessNotifications;
    _reconnected = reconnected;
    final value = _repository;
    if (value != null) _attachSync(value);
  }

  static void _attachSync(CallRecordsRepository value) {
    if (_binding != null || _businessNotifications == null) return;
    _binding = CallRecordSyncBinding(
      repository: value,
      businessNotifications: _businessNotifications,
      reconnected: _reconnected,
    );
  }

  static void detachSync() {
    _binding?.dispose();
    _binding = null;
    _businessNotifications = null;
    _reconnected = null;
  }

  static void resetSession({CallRecordsRepository? expected}) {
    if (expected != null && !identical(expected, _repository)) return;
    _binding?.dispose();
    _binding = null;
    _repository?.dispose();
    _repository = null;
  }
}
