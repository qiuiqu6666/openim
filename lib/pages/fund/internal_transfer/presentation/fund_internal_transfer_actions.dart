import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../services/fund_models.dart';
import '../../../mine/settings/pages/country_code_page.dart';
import '../../../mine/settings/widgets/settings_widgets.dart';
import '../../../wallet/host/wallet_i18n.dart';
import '../../../wallet/record/wallet_record_screen.dart';
import '../data/fund_transfer_recipient_source.dart';

/// Entry surfaces only. The existing send owner keeps all payment state.
Future<FundTransferAccountType?> showFundTransferAccountTypes(
    BuildContext context, FundTransferAccountType selected) {
  final i18n = AppI18n.of(context);
  final currentChoice = i18n.t(
      zhHans: '当前选择',
      zhHant: '目前選擇',
      en: 'Current selection',
      ja: '現在の選択',
      ko: '현재 선택');
  return showAppActionSheet<FundTransferAccountType>(
    context,
    title: i18n.t(
        zhHans: '选择账号类型',
        zhHant: '選擇帳號類型',
        en: 'Choose account type',
        ja: 'アカウントの種類を選択',
        ko: '계정 유형 선택'),
    actions: [
      for (final type in const [
        FundTransferAccountType.account,
        FundTransferAccountType.email,
        FundTransferAccountType.phone,
      ])
        AppAction(
          switch (type) {
            FundTransferAccountType.account => i18n.t(
                zhHans: '99号',
                zhHant: '99號',
                en: '99Chat ID',
                ja: '99Chat ID',
                ko: '99Chat ID'),
            FundTransferAccountType.email => i18n.t(
                zhHans: '邮箱',
                zhHant: '電子郵件',
                en: 'Email',
                ja: 'メールアドレス',
                ko: '이메일'),
            FundTransferAccountType.phone => i18n.t(
                zhHans: '手机号',
                zhHant: '手機號碼',
                en: 'Phone number',
                ja: '電話番号',
                ko: '전화번호'),
            FundTransferAccountType.uid => 'UID',
          },
          type,
          key: ValueKey('internal-transfer-type-${type.name}'),
          selected: type == selected,
          subtitle: type == selected ? currentChoice : null,
        ),
    ],
  );
}

Future<String?> chooseFundTransferAreaCode(
        BuildContext context, String selectedCode) =>
    Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => CountryCodePage(selectedCode: selectedCode)));

Future<void> showFundInternalTransferHelp(BuildContext context) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(settingsText(context, zh: '内部转账', en: 'Internal transfer')),
        content: Text(settingsText(context,
            zh: '通过99号、邮箱或带区号的手机号查找收款人，也可从好友中选择。内部转账手续费为0，支付成功后直接到账。请在支付弹窗核对收款人和金额。',
            en: 'Find a recipient by 99Chat ID, email or phone number with calling code, or select a friend. Internal transfers have no fee and arrive directly after payment. Review the recipient and amount in the payment sheet.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(settingsText(context, zh: '知道了', en: 'Got it'))),
        ],
      ),
    );

Future<void> openFundInternalTransferHistory(
        BuildContext context, FundCurrency currency) =>
    Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => WalletRecordScreen(initialCoin: currency.code)));
