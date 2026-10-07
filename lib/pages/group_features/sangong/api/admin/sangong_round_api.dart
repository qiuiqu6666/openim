import '../../../data/group_feature_api.dart';
import '../../models/sangong_admin_models.dart';
import '../../utils/sangong_banker_setup_input.dart';
import '../sangong_game_http.dart';
import '../sangong_v2_api.dart';

/// Round operations always carry the ID the operator saw before confirming.
/// Mutation replies include the committed state, so no follow-up read is needed.
class SangongRoundApi {
  SangongRoundApi(this.http);
  final SangongGameHttp http;
  SangongV2Api get _api => SangongV2Api(http);

  Future<Map<String, dynamic>> command(String action, int roundId,
      [Map<String, dynamic> input = const {}]) async {
    if (roundId <= 0) throw ArgumentError('roundId required');
    return _api.command(action, {'roundId': roundId, ...input});
  }

  Map<String, dynamic> state(Map<String, dynamic> data) {
    final state = data['state'];
    if (state is! Map ||
        state['groupId'] != http.context.groupID ||
        state['version'] is! int ||
        !state.containsKey('round')) {
      throw const GroupFeatureException('操作结果尚未确认，请刷新后查看',
          code: 'UNKNOWN_RESULT', unknownResult: true);
    }
    return Map<String, dynamic>.from(state);
  }

  Future<SangongAdminSession> assignBanker(
      {required int roundId,
      required String imUserId,
      required int door,
      int? limit,
      String? nickname,
      bool openBetting = false}) async {
    final data = await command('round.banker', roundId, {
      'imUserId': imUserId.trim(),
      'door': door,
      'bankerLimit': limit ?? 0,
      if (nickname?.trim().isNotEmpty == true) 'nickname': nickname!.trim(),
      'openBetting': openBetting,
    });
    return SangongAdminSession.fromJson(state(data));
  }

  Future<SangongQuickSetupBankerResult> quickBanker(
      {required int roundId,
      String? text,
      String? imUserId,
      String? nickname,
      int? door,
      int? limit}) async {
    final parsed = parseSangongBankerSetupText(text ?? '');
    final selectedDoor = door ?? parsed.door;
    final selectedLimit = limit ?? parsed.limit ?? 0;
    if (selectedDoor == null || imUserId?.trim().isNotEmpty != true) {
      throw ArgumentError('请输入庄门或庄门.限额，并选择群成员');
    }
    final session = await assignBanker(
        roundId: roundId,
        imUserId: imUserId!,
        door: selectedDoor,
        limit: selectedLimit,
        nickname: nickname,
        openBetting: true);
    return SangongQuickSetupBankerResult(
        ok: true, round: session.round, newRound: session.round?.id != roundId);
  }

  Future<SangongAdminSession> coBank(String action, int roundId,
          [Map<String, dynamic> input = const {}]) async =>
      SangongAdminSession.fromJson(
          state(await command(action, roundId, input)));

  List<Map<String, dynamic>> draws(List<SangongDrawInput> entries) =>
      entries.map((e) {
        final match =
            RegExp(r'^(0|1)(?:\.(\d{1,2}))?$').firstMatch(e.amount.trim());
        if (match == null) throw ArgumentError('开彩金额必须为 0.01～1.00');
        final amount = int.parse(match.group(1)!) * 100 +
            int.parse((match.group(2) ?? '').padRight(2, '0'));
        if (amount < 1 || amount > 100) {
          throw ArgumentError('开彩金额必须为 0.01～1.00');
        }
        return {'door': e.door, 'amountHundredths': amount};
      }).toList();

  Future<SangongDrawFetchResult> fetchDraws() async =>
      SangongDrawFetchResult.fromJson(await _api.read('snapshot'));

  Future<SangongDrawMutationResult> submitDraws(
          int roundId, List<SangongDrawInput> entries) async =>
      SangongDrawMutationResult.fromJson(state(
          await command('round.draws', roundId, {'draws': draws(entries)})));

  Future<SangongAdminRound> settle(int roundId) async {
    final data = await command('round.settle', roundId);
    return _round(data, roundId, 'settled');
  }

  SangongAdminRound _round(Map<String, dynamic> data, int id, String? status) {
    final raw = data['round'];
    if (raw is! Map ||
        raw['id'] != id ||
        status != null && raw['status'] != status) {
      throw const GroupFeatureException('操作结果尚未确认，请刷新后查看',
          code: 'UNKNOWN_RESULT', unknownResult: true);
    }
    return SangongAdminRound.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<SangongVoidSettlementResult> reverse(int roundId) async {
    final data = await command('round.reverse', roundId);
    return SangongVoidSettlementResult(
        ok: true, round: _round(data, roundId, null));
  }

  Future<SangongResettleResult> resettle(
      int roundId, List<SangongDrawInput> entries) async {
    if (entries.isEmpty) throw ArgumentError('重结须重新录入各门开彩');
    final data =
        await command('round.resettle', roundId, {'draws': draws(entries)});
    return SangongResettleResult(
        ok: true,
        round: _round(data, roundId, 'settled'),
        settlement: Map<String, dynamic>.from(data)
          ..remove('state')
          ..remove('round'));
  }
}
