import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../../data/group_feature_api.dart';
import '../../api/diagnostics/sangong_api_debug_log.dart';
import '../../api/sangong_game_http.dart';

/// Adds account-lookup outcomes to the existing masked HTTP diagnostics.
class SangongProfileLedgerLog {
  SangongProfileLedgerLog._(this._logger, this._scope);

  static SangongProfileLedgerLog? start(SangongGameHttp http, String target) {
    final logger = SangongApiDebugLog.create();
    if (logger == null) return null;
    final log = SangongProfileLedgerLog._(logger, {
      'lookupID': const Uuid().v4(),
      'groupID': http.context.groupID,
      'currentUserID': http.context.currentUserID,
      'targetIMUserID': target,
      'logicalTenantID': http.tenantId,
      'resource': 'user',
    });
    log._elapsed.start();
    log._emit('开始', const {});
    return log;
  }

  final SangongApiDebugLog _logger;
  final Map<String, dynamic> _scope;
  final Stopwatch _elapsed = Stopwatch();

  void complete({required String? returnedUserID, required bool current}) {
    _elapsed.stop();
    _emit('结果', {
      'result': returnedUserID == null
          ? 'account_not_found'
          : returnedUserID == _scope['targetIMUserID']
              ? 'account_confirmed'
              : 'identity_mismatch',
      'returnedIMUserID': returnedUserID,
      'current': current,
    });
  }

  void failed(Object error) {
    _elapsed.stop();
    _emit('失败', {
      'errorType': error.runtimeType.toString(),
      if (error is FormatException) 'validationError': error.message,
      if (error is StateError) 'scopeError': error.message,
      if (error is GroupFeatureException) ...{
        'code': error.code,
        'status': error.statusCode,
        'serverCode': error.serverCode,
      },
      if (error is DioException) ...{
        'networkType': error.type.name,
        'status': error.response?.statusCode,
        if (error.error != null)
          'causeType': error.error.runtimeType.toString(),
        if (error.error is StateError)
          'scopeError': (error.error as StateError).message,
        if (error.error is GroupFeatureException) ...{
          'code': (error.error as GroupFeatureException).code,
          'serverCode': (error.error as GroupFeatureException).serverCode,
          'status': error.response?.statusCode ??
              (error.error as GroupFeatureException).statusCode,
        },
      },
    });
  }

  void _emit(String stage, Map<String, dynamic> data) =>
      _logger.onApplicationEvent('资料流水_$stage', {
        ..._scope,
        'elapsedMs': _elapsed.elapsedMilliseconds,
        ...data,
      });
}
