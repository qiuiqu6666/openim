import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  testWidgets('newer search page preserves the last visible message',
      (tester) async {
    final scroll = ScrollController();
    var ids = List.generate(40, (i) => 'old-$i');
    late StateSetter update;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(home: Scaffold(body: StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return ChatListView(
            controller: scroll,
            messageIDs: ids,
            itemCount: ids.length,
            loadOnInit: false,
            followLatest: false,
            hasMore: false,
            enabledScrollTopLoad: true,
            newerHasMore: true,
            findChildIndexCallback: (key) {
              final i = ids.indexOf((key as ValueKey<String>).value);
              return i < 0 ? null : i;
            },
            itemBuilder: (_, i) => SizedBox(
                key: ValueKey(ids[i]), height: 60, child: Text(ids[i])),
          );
        },
      ))),
    ));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('old-0')).dy;
    update(() => ids = [...List.generate(20, (i) => 'new-$i'), ...ids]);
    await tester.pumpAndSettle();
    expect(find.text('old-0'), findsOneWidget);
    expect(tester.getTopLeft(find.text('old-0')).dy, closeTo(before, 1));
    // Reaching the next page edge must not re-enable automatic latest pinning.
    scroll.jumpTo(scroll.position.minScrollExtent);
    await tester.pumpAndSettle();
    final nextBefore = tester.getTopLeft(find.text('new-0')).dy;
    update(() => ids = [...List.generate(20, (i) => 'next-$i'), ...ids]);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('new-0')).dy, closeTo(nextBefore, 1));
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
  });
}
