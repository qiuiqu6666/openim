import '../../host/wallet_i18n.dart';
import '../wallet_record_amount.dart';
import 'wallet_journal_entry.dart';

String walletJournalCoin(String currency) =>
    currency.toUpperCase() == 'BI99' ? '99币' : currency.toUpperCase();

String walletJournalAmount(String? raw, String currency,
    {bool signed = false}) {
  final amount = walletRecordAmountExact(raw, signed: signed);
  if (amount == '--') return amount;
  return '$amount ${walletJournalCoin(currency)}';
}

/// Application/return events keep their ledger direction, but use business
/// language on packet and withdrawal receipts.
bool walletJournalHasBusinessBalanceMovement(WalletJournalEntry entry) =>
    (entry.direction == 'freeze' || entry.direction == 'unfreeze') &&
    (entry.bizType == 'withdraw' || entry.bizType.startsWith('packet_'));

String walletJournalDirectionLabel(WalletJournalEntry entry, AppI18n i18n) {
  final businessLabel = _businessBalanceMovementTitle(entry, i18n);
  if (businessLabel != null) return businessLabel;
  return switch (entry.direction) {
    'income' =>
      i18n.t(zhHans: '收入', zhHant: '收入', en: 'Income', ja: '収入', ko: '수입'),
    'expense' =>
      i18n.t(zhHans: '支出', zhHant: '支出', en: 'Expense', ja: '支出', ko: '지출'),
    'freeze' =>
      i18n.t(zhHans: '冻结', zhHant: '凍結', en: 'Frozen', ja: '凍結', ko: '동결'),
    'unfreeze' => i18n.t(
        zhHans: '解冻', zhHant: '解凍', en: 'Unfrozen', ja: '凍結解除', ko: '동결 해제'),
    _ => i18n.t(
        zhHans: '无资产变动',
        zhHant: '無資產變動',
        en: 'No asset change',
        ja: '資産の変動なし',
        ko: '자산 변동 없음'),
  };
}

String? _packetName(WalletJournalEntry entry, AppI18n i18n) =>
    switch (entry.bizType) {
      'packet_normal' => i18n.t(
          zhHans: '普通红包',
          zhHant: '普通紅包',
          en: 'normal red packet',
          ja: '普通紅包',
          ko: '일반 레드패킷'),
      'packet_lucky' => i18n.t(
          zhHans: '拼手气红包',
          zhHant: '拼手氣紅包',
          en: 'lucky red packet',
          ja: '運試し紅包',
          ko: '행운 레드패킷'),
      'packet_exclusive' => i18n.t(
          zhHans: '专属红包',
          zhHant: '專屬紅包',
          en: 'exclusive red packet',
          ja: '専用紅包',
          ko: '전용 레드패킷'),
      _ => null,
    };

String? _businessBalanceMovementTitle(WalletJournalEntry entry, AppI18n i18n) {
  if (!walletJournalHasBusinessBalanceMovement(entry)) return null;
  if (entry.bizType == 'withdraw') {
    return entry.direction == 'freeze'
        ? i18n.t(
            zhHans: '提现申请',
            zhHant: '提現申請',
            en: 'Withdrawal request',
            ja: '出金申請',
            ko: '출금 신청')
        : i18n.t(
            zhHans: '提现退回',
            zhHant: '提現退回',
            en: 'Withdrawal returned',
            ja: '出金返金',
            ko: '출금 반환');
  }
  if (entry.direction == 'unfreeze') {
    return i18n.t(
        zhHans: '红包退回',
        zhHant: '紅包退回',
        en: 'Red packet returned',
        ja: '紅包返金',
        ko: '레드패킷 반환');
  }
  final name = _packetName(entry, i18n) ??
      i18n.t(
          zhHans: '红包', zhHant: '紅包', en: 'red packet', ja: '紅包', ko: '레드패킷');
  return i18n.t(
      zhHans: '发出$name',
      zhHant: '發出$name',
      en: 'Sent $name',
      ja: '$nameを送信',
      ko: '$name 보내기');
}

String walletJournalTitle(WalletJournalEntry entry, AppI18n i18n,
    {String counterpartyNickname = ''}) {
  final businessTitle = _businessBalanceMovementTitle(entry, i18n);
  if (businessTitle != null) return businessTitle;
  final packetName = _packetName(entry, i18n);
  if (packetName != null &&
      (entry.type == 'packet_sent' || entry.type == 'packet_freeze')) {
    return i18n.t(
        zhHans: '发出$packetName',
        zhHant: '發出$packetName',
        en: 'Sent $packetName',
        ja: '$packetNameを送信',
        ko: '$packetName 보내기');
  }
  if (packetName != null && entry.type == 'packet_received') {
    return i18n.t(
        zhHans: '收到$packetName',
        zhHant: '收到$packetName',
        en: 'Received $packetName',
        ja: '$packetNameを受取',
        ko: '$packetName 받음');
  }
  if ((entry.bizType == 'transfer' || entry.bizType == 'group_transfer') &&
      (entry.type == 'transfer_sent' || entry.type == 'transfer_received')) {
    final transfer =
        i18n.t(zhHans: '转账', zhHant: '轉帳', en: 'Transfer', ja: '送金', ko: '송금');
    final nickname = counterpartyNickname.trim();
    return nickname.isEmpty ? transfer : '$transfer-$nickname';
  }
  final title = entry.title.trim();
  final direction = walletJournalDirectionLabel(entry, i18n);
  if (title.isEmpty) return direction;
  if (entry.direction == 'income' ||
      entry.direction == 'expense' ||
      title.contains(direction)) {
    return title;
  }
  return '$title · $direction';
}

String walletJournalPrimaryAmount(WalletJournalEntry entry) =>
    walletJournalAmount(
        entry.direction == 'income' || entry.direction == 'expense'
            ? entry.assetDelta
            : entry.amount,
        entry.currency,
        signed: entry.direction == 'income' || entry.direction == 'expense');

String walletJournalDirectionExplanation(
        WalletJournalEntry entry, AppI18n i18n) =>
    switch (entry.direction) {
      'freeze' => i18n.t(
          zhHans: '可用余额转为冻结余额，资产总数量不变，不计入支出。',
          zhHant: '可用餘額轉為凍結餘額，資產總數量不變，不計入支出。',
          en: 'Available balance moves to frozen balance. Total assets are unchanged; this is not an expense.',
          ja: '利用可能残高が凍結残高に移ります。総資産は変わらず、支出には含まれません。',
          ko: '사용 가능 잔액이 동결 잔액으로 이동합니다. 총자산은 변하지 않으며 지출에 포함되지 않습니다.'),
      'unfreeze' => i18n.t(
          zhHans: '冻结余额转回可用余额，资产总数量不变，不计入收入。',
          zhHant: '凍結餘額轉回可用餘額，資產總數量不變，不計入收入。',
          en: 'Frozen balance returns to available balance. Total assets are unchanged; this is not income.',
          ja: '凍結残高が利用可能残高に戻ります。総資産は変わらず、収入には含まれません。',
          ko: '동결 잔액이 사용 가능 잔액으로 돌아옵니다. 총자산은 변하지 않으며 수입에 포함되지 않습니다.'),
      'income' || 'expense' => i18n.t(
          zhHans: '按原币数量显示资产变动。',
          zhHant: '按原幣數量顯示資產變動。',
          en: 'Asset changes are shown in the original currency.',
          ja: '資産変動は元の通貨数量で表示されます。',
          ko: '자산 변동은 원래 통화 수량으로 표시됩니다.'),
      _ => i18n.t(
          zhHans: '本次事件未改变资产总数量。',
          zhHant: '本次事件未改變資產總數量。',
          en: 'This event did not change total assets.',
          ja: 'このイベントで総資産は変動していません。',
          ko: '이 이벤트로 총자산이 변하지 않았습니다.'),
    };
