import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/register/rules/register_password_rules.dart';

void main() {
  test('registration follows the reference minimum without the old 20-char cap',
      () {
    expect(RegisterPasswordRules.valid('abc1234'), isFalse);
    expect(RegisterPasswordRules.valid('abc12345'), isTrue);
    expect(RegisterPasswordRules.valid('longPasswordWithMoreThan20Chars1'),
        isTrue);
  });

  test('registration requires both an English letter and a digit', () {
    expect(RegisterPasswordRules.valid('password'), isFalse);
    expect(RegisterPasswordRules.valid('12345678'), isFalse);
    expect(RegisterPasswordRules.valid('中文密码中文1234'), isFalse);
    expect(RegisterPasswordRules.valid('Password1!'), isTrue);
  });
}
