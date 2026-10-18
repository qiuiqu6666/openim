import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/compensation/models/compensation_detail.dart';
import 'support.dart';

void main() {
  test('remaining pool uses server amount and preserves precision', () {
    final data = response();
    expect(CompensationDetail.fromJson(data).remainingLabel, '68.25万99币');
    (data['activity'] as Map)['remainingAmount'] = '682500.01';
    expect(CompensationDetail.fromJson(data).remainingLabel, '682500.01 99币');
    (data['activity'] as Map).remove('remainingAmount');
    expect(CompensationDetail.fromJson(data).remainingLabel, isNull);
    (data['activity'] as Map)['remainingAmount'] = 'invalid';
    expect(() => CompensationDetail.fromJson(data), throwsFormatException);
  });
}
