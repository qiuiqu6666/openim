import 'package:flutter_test/flutter_test.dart';
import 'package:characters/characters.dart';
import 'package:openim/pages/register/rules/register_nickname_rules.dart';

import '../../support/unicode/unicode_samples.dart';

void main() {
  for (final sample
      in unicodeSamples.where((sample) => sample.text.characters.length == 1)) {
    test('nickname minimum counts graphemes for ${sample.name}', () {
      expect(RegisterNicknameRules.validate(sample.text), isNotNull);
      expect(RegisterNicknameRules.validate('${sample.text}甲'), isNull);
    });
  }
}
