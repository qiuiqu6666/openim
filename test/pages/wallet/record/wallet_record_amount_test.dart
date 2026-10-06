import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/record/wallet_record_amount.dart';

void main() {
  test('integers and short fractions always show two decimal places', () {
    for (final (raw, expected) in [
      ('0', '0.00'),
      ('7', '7.00'),
      ('7.2', '7.20'),
      ('7.20', '7.20'),
      ('0007.2', '7.20'),
      ('  7.2  ', '7.20'),
    ]) {
      expect(walletRecordAmountTwoDecimals(raw), expected, reason: raw);
    }
  });

  test('decimal half thresholds round exactly without binary-float drift', () {
    for (final (raw, expected) in [
      ('1.004', '1.00'),
      ('1.005', '1.01'),
      ('1.0050000000000000000000000000000', '1.01'),
      ('1.0049999999999999999999999999999', '1.00'),
      ('2.675', '2.68'),
      ('0.000000000000000000000000000001', '0.00'),
      ('0.009999999999999999999999999999', '0.01'),
    ]) {
      expect(walletRecordAmountTwoDecimals(raw), expected, reason: raw);
    }
  });

  test('rounding carries through cents and the integer part', () {
    for (final (raw, expected) in [
      ('9.994', '9.99'),
      ('9.995', '10.00'),
      ('99.999', '100.00'),
      ('999.995', '1000.00'),
    ]) {
      expect(walletRecordAmountTwoDecimals(raw), expected, reason: raw);
    }
  });

  test('supplied signs are preserved and negative halves round away from zero',
      () {
    for (final (raw, expected) in [
      ('+7', '+7.00'),
      ('-7.2', '-7.20'),
      ('-1.004', '-1.00'),
      ('-1.005', '-1.01'),
      ('+9.995', '+10.00'),
      ('-9.995', '-10.00'),
      ('-0.004', '-0.00'),
    ]) {
      expect(walletRecordAmountTwoDecimals(raw), expected, reason: raw);
    }
  });

  test('valid thousands groups are retained and rebuilt after carry', () {
    for (final (raw, expected) in [
      ('1,234', '1,234.00'),
      ('12,345.6', '12,345.60'),
      ('123,456.789', '123,456.79'),
      ('999,999.995', '1,000,000.00'),
      ('-9,999.995', '-10,000.00'),
      ('+1,234.567', '+1,234.57'),
      ('1234567.899', '1234567.90'),
    ]) {
      expect(walletRecordAmountTwoDecimals(raw), expected, reason: raw);
    }
  });

  test('integers above the exact double range preserve every digit', () {
    for (final (raw, expected) in [
      ('9007199254740993.125', '9007199254740993.13'),
      ('9007199254740993.995', '9007199254740994.00'),
      (
        '1234567890123456789012345678901234567890.004',
        '1234567890123456789012345678901234567890.00',
      ),
      (
        '9999999999999999999999999999999999999999.995',
        '10000000000000000000000000000000000000000.00',
      ),
      (
        '999,999,999,999,999,999,999,999.995',
        '1,000,000,000,000,000,000,000,000.00',
      ),
    ]) {
      expect(walletRecordAmountTwoDecimals(raw), expected, reason: raw);
    }
  });

  test('empty unknown and invalid amounts remain unknown', () {
    for (final raw in [
      '',
      '   ',
      '--',
      ' -- ',
      'null',
      'NaN',
      'Infinity',
      '1e3',
      '¥12.30',
      '12.30 USDT',
      '+',
      '-',
      '.',
      '1.',
      '.5',
      '1.2.3',
      '--1.2',
      '1,23.4',
      '1234,567.8',
      '1,,234.56',
      ',123.45',
      '1,234,',
      '0,123.45',
      '01,234.56',
      '1,234.5,6',
      '1 234.56',
      '+ 1.23',
    ]) {
      expect(walletRecordAmountTwoDecimals(raw), '--', reason: raw);
    }
  });
}
