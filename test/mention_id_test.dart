import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim/pages/chat/mention_id.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  test('keeps the full UID first and handles invisible separators', () {
    expect(mentionIDCandidates('@hqBvmIFPZYWn'),
        ['@hqBvmIFPZYWn', 'hqBvmIFPZYWn']);
    expect(mentionIDCandidates('@h\u200bqBvmIFPZYWn').first, '@hqBvmIFPZYWn');
    expect(
        mentionIDCandidates('hqBvmIFPZYWn'), ['hqBvmIFPZYWn', '@hqBvmIFPZYWn']);
  });

  test('finds user and group IDs without matching email addresses', () {
    final regex = RegExp(mentionIDPattern);
    expect(
        regex
            .allMatches('找 @2138014845 和 @TGS#2P5XTVUUS')
            .map((match) => match.group(0))
            .toList(),
        ['@2138014845', '@TGS#2P5XTVUUS']);
    expect(regex.hasMatch('a@example.com'), isFalse);
  });

  testWidgets('tapping an ID in chat text invokes its search action',
      (tester) async {
    String? tapped;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: ChatText(
              text: '@hqBvmIFPZYWn',
              patterns: [
                MatchPattern(
                  type: PatternType.custom,
                  pattern: mentionIDPattern,
                  onTap: (value, _) => tapped = value,
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(ChatText));
    expect(tapped, '@hqBvmIFPZYWn');
  });
}
