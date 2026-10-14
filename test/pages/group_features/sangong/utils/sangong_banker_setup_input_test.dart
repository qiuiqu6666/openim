import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/utils/sangong_banker_setup_input.dart';

void main() {
  test('every requested single separator and full-width ASCII is accepted', () {
    const symbols =
        '''。.,，/、+:：;；()（）!！?？"'‘’“”#\$%&*<=>@[]^_`{|}~×÷±≈≠≤≥∞∑√…·ˉ∶〃-\\''';
    final separators = [
      ...symbols.split(''),
      ' ',
      '\t',
      '\n',
      '\r\n',
      ' \t\n ',
      '\u3000',
      ...symbols.runes
          .where((r) => r >= 0x21 && r <= 0x7e)
          .map((r) => String.fromCharCode(r + 0xfee0)),
    ];
    for (final separator in separators) {
      final text = '2${separator}200000';
      final result = parseSangongBankerSetupText(text);
      expect(result.door, 2, reason: text);
      expect(result.limit, 200000, reason: text);
      expect(result.hasExplicitLimit, isTrue, reason: text);
    }
  });

  test('complete parentheses accept spaces and unit amounts', () {
    for (final text in [
      '2(5000)',
      '2（5000）',
      '２（５０００）',
      '2 ( 5千 )',
      '2\n(0.5万)'
    ]) {
      final result = parseSangongBankerSetupText(text);
      expect(result.door, 2, reason: text);
      expect(result.limit, 5000, reason: text);
      expect(result.hasExplicitLimit, isTrue, reason: text);
    }
  });

  test('long-press banker phrases and original separators agree', () {
    for (final text in [
      '庄2限5000',
      '庄2限额5000',
      '2门5000',
      '庄2门限5000',
      '2.5千',
      '2*5000',
      '2×5000',
      '2/5000',
      '2、5000',
      '2-5000',
      '2+5000',
      '2.5000',
      '２＊５０００',
      ' 庄 2 门 限额 5 千 ',
      '2*5k',
      '2*0.5万',
      '2*0.5W',
      '2*50百',
    ]) {
      final result = parseSangongBankerSetupText(text);
      expect(result.door, 2, reason: text);
      expect(result.limit, 5000, reason: text);
      expect(result.hasExplicitLimit, isTrue, reason: text);
    }
    expect(parseSangongBankerSetupText('2*200000').limit, 200000);
    expect(parseSangongBankerSetupText('2*2.5千').limit, 2500);
    expect(parseSangongBankerSetupText('2*0.0001万').limit, 1);
  });

  test(
      'door-only and explicit zero remain distinct; negatives reach validation',
      () {
    for (final text in ['2', '庄2', '2门', '庄2门']) {
      final result = parseSangongBankerSetupText(text);
      expect(result.door, 2);
      expect(result.limit, isNull);
      expect(result.hasExplicitLimit, isFalse);
    }
    expect(parseSangongBankerSetupText('2*0').limit, 0);
    expect(parseSangongBankerSetupText('2*0').hasExplicitLimit, isTrue);
    expect(parseSangongBankerSetupText('2.-5').limit, -5);
    expect(parseSangongBankerSetupText('2*-0.5千').limit, -500);
  });

  test(
      'reject malformed or imprecise limits without extracting partial numbers',
      () {
    for (final text in [
      '',
      'abc',
      '请定庄2限5000',
      '2门5000谢谢',
      '2**5000',
      '2//100',
      '2++100',
      '2 / / 100',
      '2((100))',
      '2[100]',
      '2)100(',
      '2(100))',
      '2*',
      '2门限',
      '2*2.5',
      '2*0.0001千',
      '2*5千万',
      '2*5 000',
      '2*9007199254740992',
      '2.5千元',
    ]) {
      final result = parseSangongBankerSetupText(text);
      expect(result.door, isNull, reason: text);
      expect(result.limit, isNull, reason: text);
      expect(result.hasExplicitLimit, isFalse, reason: text);
    }
  });
}
