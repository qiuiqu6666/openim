import '../models/sangong_admin_models.dart';

/// Unsaved profile settings belong to one displayed round and never reach
/// the server until that section's Send button is confirmed.
class SangongProfileConfigDraft {
  int? roundId;
  int? bankerDoor;
  int? bankerLimit;
  int? coBankAmount; // zero means remove the selected member

  void clear() {
    roundId = bankerDoor = bankerLimit = coBankAmount = null;
  }

  void bind(int id) {
    if (roundId != null && roundId != id) clear();
    roundId = id;
  }

  SangongCoBank preview(SangongCoBank saved,
      {required int userId,
      required String imUserId,
      required String nickname}) {
    final amount = coBankAmount;
    if (amount == null) return saved;
    final members = saved.members.where((m) => m.userId != userId).toList();
    if (amount > 0) {
      members.add(SangongCoBankMember(
          userId: userId,
          imUserId: imUserId,
          nickname: nickname,
          amount: amount,
          sharePercent: 0));
    }
    final previous = saved.memberForUserId(userId)?.amount ?? 0;
    final pool = saved.poolTotal - previous + amount;
    return SangongCoBank(poolTotal: pool, count: members.length, members: [
      for (final m in members)
        SangongCoBankMember(
            userId: m.userId,
            imUserId: m.imUserId,
            nickname: m.nickname,
            amount: m.amount,
            sharePercent: pool > 0 ? m.amount * 100 / pool : 0),
    ]);
  }
}
