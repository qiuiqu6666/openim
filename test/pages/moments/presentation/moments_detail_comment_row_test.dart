import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/presentation/moments_detail_comment_row.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';

const _actor =
    MomentUser(userId: 'friend', nickname: 'Nickname', remark: 'Remark Name');
const _comment = MomentComment(
    commentId: 'comment', author: _actor, text: 'A comment', createdAt: 1);

Widget _host(Widget row,
        {bool dark = false,
        String language = 'en',
        double width = 390,
        double textScale = 1}) =>
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        locale: Locale(language),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: width, child: row),
              ),
            ),
          ),
        ),
      ),
    );

Finder _body() => find
    .byWidgetPredicate((widget) => widget is Text && widget.textSpan != null);

void main() {
  testWidgets('comment content aligns to the avatar and retains three lines',
      (tester) async {
    await tester.pumpWidget(_host(MomentsDetailCommentRow(
        comment: _comment, isFirst: true, onAction: () {})));
    final avatar = tester.widget<AvatarView>(find.byType(AvatarView));
    expect(avatar.width, 32);
    expect(avatar.height, 32);
    expect(avatar.isCircle, isTrue);
    expect(tester.getTopLeft(find.byType(AvatarView)).dx, 54);
    expect(tester.getTopLeft(find.text('Remark Name')).dx, 94);
    final name = tester.widget<Text>(find.text('Remark Name'));
    expect(name.style!.fontSize, 14);
    expect(name.style!.fontWeight, FontWeight.w600);
    expect(name.style!.color, const Color(0xFF374151));
    final body = tester.widget<Text>(_body());
    expect(body.textSpan!.toPlainText(), 'A comment');
    expect(body.maxLines, 3);
    expect(body.overflow, TextOverflow.ellipsis);
    expect(body.style!.fontSize, 14);
    expect(body.style!.height, 1.24);
    expect(body.style!.fontWeight, FontWeight.w500);
    final timestamp = tester
        .widgetList<Text>(find.byType(Text))
        .singleWhere((text) => text.data != null && text.style?.fontSize == 11);
    expect(timestamp.maxLines, 1);
    final divider = tester.widget<Divider>(find.byType(Divider));
    expect(divider.height, 1);
    expect(divider.indent, 94);
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panel edges and the first-comment icon are independent',
      (tester) async {
    await tester.pumpWidget(_host(MomentsDetailCommentRow(
        comment: _comment, startsPanel: true, isLast: true, onAction: () {})));
    final clips = tester.widgetList<ClipRRect>(find.byType(ClipRRect));
    expect(clips.first.borderRadius, BorderRadius.circular(7));
    expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
    expect(find.byType(Divider), findsNothing);
    final panel = tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .singleWhere((box) => box.color == const Color(0xFFF1F3F5));
    expect(panel.color, const Color(0xFFF1F3F5));
  });

  testWidgets('dark panel uses a readable author and target color',
      (tester) async {
    await tester.pumpWidget(_host(
        MomentsDetailCommentRow(
            comment: const MomentComment(
                commentId: 'reply',
                author: _actor,
                text: 'Response',
                replyToUser: MomentUser(userId: 'target', nickname: 'Target')),
            onAction: () {}),
        dark: true));
    expect(tester.widget<Text>(find.text('Remark Name')).style!.color,
        const Color(0xFFF4F4F4));
    expect(
        tester
            .widgetList<ColoredBox>(find.byType(ColoredBox))
            .any((box) => box.color == const Color(0xFF23262D)),
        isTrue);
    expect(tester.widget<Text>(_body()).textSpan!.toPlainText(),
        'Reply to Target：Response');
  });

  for (final language in ['en', 'zh']) {
    testWidgets('deleted target is anonymous in $language', (tester) async {
      await tester.pumpWidget(_host(
          MomentsDetailCommentRow(
            comment: const MomentComment(
                commentId: 'deleted-reply',
                author: _actor,
                text: 'Response',
                replyTargetDeleted: true,
                replyToUser: MomentUser(
                    userId: 'target',
                    nickname: 'Secret old nickname',
                    remark: 'Secret old remark')),
            onAction: () {},
          ),
          language: language));
      final text = tester.widget<Text>(_body()).textSpan!.toPlainText();
      expect(text, contains(language == 'zh' ? '已删除评论' : 'Deleted comment'));
      expect(text, isNot(contains('Secret')));
      expect(text, isNot(contains('target')));
    });
  }

  testWidgets('content tap and long press preserve the action callback',
      (tester) async {
    var actions = 0;
    await tester.pumpWidget(_host(
        MomentsDetailCommentRow(comment: _comment, onAction: () => ++actions)));
    await tester.tap(_body());
    expect(actions, 1);
    await tester.longPress(_body());
    expect(actions, 2);
  });

  testWidgets('avatar navigation does not also invoke the comment action',
      (tester) async {
    var actions = 0;
    var authors = 0;
    await tester.pumpWidget(_host(MomentsDetailCommentRow(
        comment: _comment,
        onAction: () => ++actions,
        onAuthor: () => ++authors)));
    await tester.tap(find.byType(AvatarView));
    expect(authors, 1);
    expect(actions, 0);
  });

  testWidgets(
      'narrow width and large text retain reply truncation without overflow',
      (tester) async {
    await tester.pumpWidget(_host(
        MomentsDetailCommentRow(
            comment: MomentComment(
                commentId: 'long-reply',
                author: _actor,
                text: List.filled(20, 'Long response').join(' '),
                replyToUser: const MomentUser(
                    userId: 'target', nickname: 'Long target display name')),
            onAction: () {}),
        width: 280,
        textScale: 2));
    expect(tester.widget<Text>(_body()).maxLines, 3);
    expect(tester.takeException(), isNull);
  });
}
