import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/interactions/moments_post_actions.dart';
import 'package:openim/services/moments_repository.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
        'actions name numeric counts and honor reduced motion ($reduced)',
        (tester) async {
      final semantics = tester.ensureSemantics();

      var likes = 0;
      Future<void> mount({bool liked = false, bool busy = false}) =>
          tester.pumpWidget(MaterialApp(
              home: MediaQuery(
                  data: MediaQueryData(disableAnimations: reduced),
                  child: Scaffold(
                      body: MomentsPostActions(
                          post: MomentPost(
                              momentId: 'one',
                              author: const MomentUser(
                                  userId: 'author', nickname: 'Author'),
                              canLike: true,
                              canComment: true,
                              likeCount: 2,
                              commentCount: 3,
                              likedByMe: liked),
                          busy: busy,
                          onLike: () => likes++,
                          onComment: () {})))));
      await mount();
      final like = find.byKey(const ValueKey('moments_like_one'));
      expect(tester.getSemantics(like).label, contains('Like'));
      await tester.tap(like);
      expect(likes, 1);
      await mount(liked: true);
      final switcher =
          tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher).first);
      expect(switcher.duration,
          reduced ? Duration.zero : const Duration(milliseconds: 180));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(like).label, contains('Unlike'));
      await mount(liked: true, busy: true);
      await tester.tap(like);
      expect(likes, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    });
  }
}
