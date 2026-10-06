import '../../../../services/fund_api.dart';
import '../../data/group_feature_api.dart';
import 'live_models.dart';

class LiveApiException extends GroupFeatureException {
  const LiveApiException(super.message,
      {required super.code,
      this.committedSession,
      super.unknownResult,
      super.authRequired,
      super.unavailable});

  /// A validated scene from an incomplete successful-write response.
  /// Reconcile it with current(); never repeat a write to repair its summary.
  final LiveSession? committedSession;
}

bool livePermissionDenied(Object error) =>
    error is GroupFeatureException &&
    const {'20012', '1002', 'FORBIDDEN'}.contains(error.code.toUpperCase());

/// Keep the business code and uncertain-write flag while showing useful feedback.
GroupFeatureException mapLiveError(GroupFeatureException error) {
  final code = error.code.toUpperCase();
  final messages = <String, String>{
    '1001': '直播参数不正确，请检查名称、时间或打赏内容',
    '1002': '你没有该直播操作的权限',
    '20012': '你已不在该群中，或没有该直播操作的权限',
    'FORBIDDEN': '你没有该直播操作的权限',
    '20062': '该打赏单号的参数与原交易不一致，请确认原交易',
    '20068': '这场直播不存在，请刷新群资料后重新进入',
    '20069': '该群已有未结束的直播，请刷新后查看当前场次',
    '20070': '当前直播状态不允许此操作，请刷新场次状态',
    '20071': '直播服务尚未配置，请联系管理员',
  };
  String? message = messages[code];
  final numeric = int.tryParse(code);
  if (const {20026, 20034, 20035, 20036}.contains(numeric)) {
    message = fundErrorMessage(FundApiException(numeric!, error.message),
        chinese: true);
  }
  return LiveApiException(message ?? error.message,
      code: error.code,
      committedSession:
          error is LiveApiException ? error.committedSession : null,
      unknownResult: error.unknownResult,
      authRequired: error.authRequired,
      unavailable: error.unavailable);
}

String liveErrorMessage(Object error) => error is GroupFeatureException
    ? mapLiveError(error).message
    : error is FormatException
        ? error.message
        : error is StateError
            ? error.message
            : error.toString();
