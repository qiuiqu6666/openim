import '../../../data/group_feature_api.dart';
import '../../models/sangong_admin_models.dart';
import '../../utils/sangong_bet_submit_cutoff.dart';
import '../sangong_game_http.dart';
import '../sangong_v2_api.dart';

class SangongReportImagesApi {
  SangongReportImagesApi(this.http);
  final SangongGameHttp http;

  Future<SangongReportImageResult> send(String kind,
      {int? roundId,
      int? groupId,
      String? targetGroupId,
      SangongBetSubmitCutoff? cutoff}) async {
    if (kind == 'bets' && (roundId == null || roundId <= 0)) {
      throw StateError('请先选择要发送报表的局');
    }
    final data = await SangongV2Api(http).command('report.send', {
      'kind': kind,
      if (roundId != null && roundId > 0) 'roundId': roundId,
      if (groupId != null) 'groupId': groupId,
      if (targetGroupId != null && targetGroupId.trim().isNotEmpty)
        'targetGroupId': targetGroupId.trim(),
      ...?cutoff?.toJson(),
    });
    if (data['queued'] != true ||
        data['type'] != kind ||
        data['reportId'] is! String ||
        (data['reportId'] as String).isEmpty ||
        data['deliveryIds'] is! List ||
        (data['deliveryIds'] as List).isEmpty ||
        (roundId != null && roundId > 0 && data['roundId'] != roundId)) {
      throw const GroupFeatureException('报表提交结果尚未确认，请查看群消息后重试',
          code: 'UNKNOWN_RESULT', unknownResult: true);
    }
    return SangongReportImageResult.fromJson({'ok': true, ...data});
  }
}
