import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../widgets/fund_page_colors.dart';

/// Keep recipient selection on the same surface as the withdrawal form.
class FundTransferFriendPickerColors {
  FundTransferFriendPickerColors.of(BuildContext context)
      : _wallet = FundPageColors.of(context);

  final FundPageColors _wallet;
  Color get page => _wallet.card;
  Color get searchFill => _wallet.inputFill;
  Color get text => _wallet.text;
  // Secondary text also serves as the search placeholder on a gray field.
  // Increase its contrast without introducing another fixed light/dark palette.
  Color get secondary => Color.lerp(_wallet.subText, _wallet.text,
      FundTransferFriendPickerTokens.textEmphasis)!;
  Color get actionText => _wallet.dark
      ? _wallet.blue
      : Color.lerp(_wallet.blue, _wallet.text,
          FundTransferFriendPickerTokens.actionEmphasis)!;
  Color get accent => _wallet.blue;
  Color get separator => _wallet.line;
  Color get hover => _wallet.blue
      .withValues(alpha: FundTransferFriendPickerTokens.hoverOpacity);
}

abstract final class FundTransferFriendPickerTokens {
  static const textEmphasis = .20;
  static const actionEmphasis = .25;
  static const hoverOpacity = .08;
  static const selectionOpacity = .20;
  static const dividerHeight = 1.0;
  static const dividerStart =
      AppTokens.s5 + FundTokens.memberAvatarSize + AppTokens.s5;
  static const dividerEnd = AppTokens.s5;
}
