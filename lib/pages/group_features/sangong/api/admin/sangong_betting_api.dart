import '../../../data/group_feature_api.dart';
import '../../models/sangong_admin_models.dart';
import '../../utils/sangong_bet_submit_cutoff.dart';
import '../sangong_game_http.dart';
import '../sangong_v2_api.dart';
import 'sangong_round_api.dart';

class SangongBettingApi {
  SangongBettingApi(this.http);
  final SangongGameHttp http;
  SangongV2Api get _api => SangongV2Api(http);

  Future<SangongBetSubmitResult> close(
      int roundId, SangongBetSubmitCutoff? cutoff) async {
    final rounds = SangongRoundApi(http);
    final data =
        await rounds.command('round.close', roundId, cutoff?.toJson() ?? {});
    final state = rounds.state(data);
    final raw = state['round'];
    final refund = data['refundedAmount'];
    if (raw is! Map ||
        raw['id'] != roundId ||
        raw['betWindowCloseAt'] == null ||
        refund is! int) {
      throw const GroupFeatureException('截止结果尚未确认，请刷新后查看',
          code: 'UNKNOWN_RESULT', unknownResult: true);
    }
    return SangongBetSubmitResult(
        round: SangongAdminRound.fromJson(Map<String, dynamic>.from(raw)),
        refundedAmount: refund,
        collectionReady: state['collectionReady'] == true,
        placedCount: state['placed'] is Map
            ? (state['placed']['betCount'] as int? ?? 0)
            : 0,
        cutoffMsgSeq: cutoff?.untilMsgSeq);
  }

  Future<SangongBetPreviewResult> preview(
      int roundId, SangongBetSubmitCutoff? cutoff) async {
    if (roundId <= 0) throw ArgumentError('roundId required');
    final context = http.context, tenant = http.tenantId;
    final query = {'roundId': roundId, ...?cutoff?.toQuery(), 'limit': 100};
    final first = await _api.read('bet-preview', query: query);
    final preview = first['preview'];
    if (preview is! Map ||
        preview['roundId'] != roundId ||
        preview['report'] is! Map) {
      throw const FormatException('下注预览格式无效');
    }
    final report = Map<String, dynamic>.from(preview['report']);
    if (report['entries'] is! List) throw const FormatException('下注预览缺少明细');
    final entries = List<dynamic>.from(report['entries']);
    var cursor = _cursor(first);
    while (cursor > 0) {
      if (!identical(context, http.context) || tenant != http.tenantId) {
        throw StateError('群或账号已改变');
      }
      final page =
          await _api.read('bet-preview', query: {...query, 'beforeId': cursor});
      final details = page['preview'];
      if (page['version'] != first['version'] ||
          details is! Map ||
          details['roundId'] != roundId ||
          details['report'] is! Map ||
          details['report']['entries'] is! List) {
        throw StateError('下注数据已更新，请刷新预览');
      }
      entries.addAll(details['report']['entries'] as List);
      final next = _cursor(page);
      if (next >= cursor) throw const FormatException('下注分页游标无效');
      cursor = next;
    }
    if (!identical(context, http.context) || tenant != http.tenantId) {
      throw StateError('群或账号已改变');
    }
    return SangongBetPreviewResult.fromJson({
      'preview': {
        ...preview,
        'report': {...report, 'entries': entries}
      }
    });
  }

  int _cursor(Map<String, dynamic> data) {
    final cursor = data['nextBeforeId'];
    if (cursor is! int || cursor < 0) throw const FormatException('下注分页游标无效');
    return cursor;
  }
}
