import 'package:flutter/material.dart';

import '../../host/app_empty_state.dart';
import '../../host/wallet_i18n.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../wallet_record_tokens.dart';

class WalletRecordEmptyContent extends StatelessWidget {
  const WalletRecordEmptyContent(
      {super.key,
      required this.loading,
      required this.failed,
      required this.onRetry,
      this.failureMessage});
  final bool loading;
  final bool failed;
  final String? failureMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    if (loading) {
      return Center(
          child: SizedBox.square(
        key: const ValueKey('wallet-record-loading'),
        dimension: AppTokens.s7,
        child:
            CircularProgressIndicator(color: WalletPageColors.of(context).blue),
      ));
    }
    if (failed) {
      return Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppEmptyState(
                key: const ValueKey('wallet-record-error'),
                imageWidth: WalletRecordTokens.emptyImage,
                message: failureMessage ??
                    i18n.t(
                        zhHans: '加载失败',
                        zhHant: '載入失敗',
                        en: 'Load failed',
                        ja: '読み込みに失敗しました',
                        ko: '불러오기에 실패했습니다')),
            TextButton(
                key: const ValueKey('wallet-record-retry'),
                onPressed: onRetry,
                style: TextButton.styleFrom(
                    minimumSize: const Size.square(WalletRecordTokens.minTap)),
                child: Text(i18n.t(
                    zhHans: '重试',
                    zhHant: '重試',
                    en: 'Retry',
                    ja: '再試行',
                    ko: '다시 시도'))),
          ]);
    }
    return AppEmptyState(
        key: const ValueKey('wallet-record-empty'),
        imageWidth: WalletRecordTokens.emptyImage,
        message: i18n.t(
            zhHans: '暂无记录',
            zhHant: '暫無記錄',
            en: 'No records',
            ja: '記録はありません',
            ko: '기록이 없습니다'));
  }
}
