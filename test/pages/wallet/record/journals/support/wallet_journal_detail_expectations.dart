import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void expectCompactJournalDetail() {
  for (final label in const ['更多明细', '商品说明', '付款方式', '余额']) {
    expect(find.text(label), findsNothing);
  }
  for (final key in const [
    'wallet-journal-more-details',
    'wallet-journal-detail-description',
    'wallet-journal-detail-payment-method',
    'wallet-journal-detail-after-available',
  ]) {
    expect(find.byKey(ValueKey(key)), findsNothing);
  }
}
