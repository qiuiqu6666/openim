import '../../../data/group_feature_api.dart';
import '../../models/sangong_admin_models.dart';
import '../sangong_game_http.dart';
import '../sangong_v2_api.dart';

/// Wallet commands are posted once with an idempotency receipt. The backend
/// resolves the IM user inside this group and records the authenticated actor.
class SangongWalletApi {
  SangongWalletApi(this.http);
  final SangongGameHttp http;
  SangongV2Api get _api => SangongV2Api(http);

  Future<SangongBalanceMutationResult> adjust(
      {required String imUserId,
      required int amount,
      required bool credit,
      String? note}) async {
    if (imUserId.trim().isEmpty || amount <= 0) throw ArgumentError('账号与金额无效');
    final data = await _api.command('wallet.adjust', {
      'imUserId': imUserId.trim(),
      'delta': credit ? amount : -amount,
      if (note?.trim().isNotEmpty == true) 'note': note!.trim(),
    });
    if (data['imUserId'] != imUserId.trim() || data['balance'] is! int) {
      throw const GroupFeatureException('操作结果尚未确认，请刷新后查看',
          code: 'UNKNOWN_RESULT', unknownResult: true);
    }
    return SangongBalanceMutationResult.fromResponse(data);
  }

  Future<Map<String, dynamic>> setLimit(
      {required int userId, required int maxNegative}) async {
    if (userId <= 0 || maxNegative < 0) throw ArgumentError('账号或可负额度无效');
    final data = await _api.command(
        'wallet.limit', {'userId': userId, 'maxNegative': maxNegative});
    if (data['userId'] != userId || data['maxNegative'] != maxNegative) {
      throw const GroupFeatureException('操作结果尚未确认，请刷新后查看',
          code: 'UNKNOWN_RESULT', unknownResult: true);
    }
    return {'user': data};
  }
}
