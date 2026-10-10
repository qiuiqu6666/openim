import 'package:characters/characters.dart';
import 'package:openim_common/openim_common.dart';

import '../../../widgets/auth/auth_copy.dart';

abstract final class RegisterNicknameRules {
  static String? validate(String value) =>
      graphemeTrim(value).characters.length < 2
          ? authText('昵称至少 2 位', 'Nickname must be at least 2 characters')
          : null;
}
