import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/register/rules/register_password_rules.dart';

void main() {
  test('registration accepts 8 to 24 characters', () {
    expect(RegisterPasswordRules.valid('abc1234'), isFalse);
    expect(RegisterPasswordRules.valid('abc12345'), isTrue);
    expect(RegisterPasswordRules.valid('a1' + 'a' * 22), isTrue);
    expect(RegisterPasswordRules.valid('a1' + 'a' * 23), isFalse);
  });

  test('registration requires both an English letter and a digit', () {
    expect(RegisterPasswordRules.valid('password'), isFalse);
    expect(RegisterPasswordRules.valid('12345678'), isFalse);
    expect(RegisterPasswordRules.valid('中文密码中文1234'), isFalse);
    expect(RegisterPasswordRules.valid('Password1!'), isFalse);
  });
}
