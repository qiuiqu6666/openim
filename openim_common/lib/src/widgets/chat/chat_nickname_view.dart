import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class ChatNicknameView extends StatelessWidget {
  const ChatNicknameView({
    super.key,
    this.nickname,
    this.timeStr,
  });
  final String? nickname;
  final String? timeStr;

  static const _maxNicknameCharacters = 20;

  @override
  Widget build(BuildContext context) {
    final name = nickname ?? '';
    final prefix = graphemePrefix(name, _maxNicknameCharacters);
    final displayName = prefix.length < name.length ? '$prefix…' : name;
    return Text.rich(
      TextSpan(
        children: [
          if (null != nickname)
            TextSpan(text: displayName, semanticsLabel: nickname),
          if (name.isNotEmpty && timeStr?.isNotEmpty == true)
            WidgetSpan(
              child: SizedBox(width: 6.w),
            ),
          TextSpan(text: timeStr),
        ],
      ),
      style: Styles.ts_8E9AB0_12sp,
      // Use the message row's width; narrow screens and large text can wrap
      // instead of introducing a second, premature layout-based truncation.
      softWrap: true,
      overflow: TextOverflow.visible,
    );
  }
}
