import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

class _Controller extends TextEditingController {
  _Controller({super.text});
  bool get hasActiveListeners => hasListeners;
}

Finder get _clearIcon => find.byWidgetPredicate(
    (widget) => widget is ImageView && widget.name == ImageRes.clearText);

Future<void> _pumpSearch(WidgetTester tester, TextEditingController controller,
    {VoidCallback? onCleared}) async {
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      home: Scaffold(
        body: SearchBox(
          key: const ValueKey('search-box'),
          controller: controller,
          enabled: true,
          hintText: 'Search',
          onCleared: onCleared,
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('a prefilled query exposes clear immediately and clears on tap',
      (tester) async {
    final controller = TextEditingController(text: 'existing query');
    addTearDown(controller.dispose);
    var cleared = 0;
    await _pumpSearch(tester, controller, onCleared: () => cleared++);
    expect(find.text('existing query'), findsOneWidget);
    expect(_clearIcon, findsOneWidget);

    await tester.tap(_clearIcon);
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(_clearIcon, findsNothing);
    expect(cleared, 1);

    await tester.enterText(find.byType(TextField), 'new query');
    await tester.pump();
    expect(_clearIcon, findsOneWidget);
  });

  testWidgets('replacing the controller updates clear and unbinds the old one',
      (tester) async {
    final first = _Controller(text: 'first query');
    final second = _Controller();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await _pumpSearch(tester, first);
    expect(_clearIcon, findsOneWidget);

    await _pumpSearch(tester, second);
    expect(first.hasActiveListeners, isFalse);
    expect(_clearIcon, findsNothing);
    first.text = 'stale query';
    await tester.pump();
    expect(find.text('stale query'), findsNothing);
    expect(_clearIcon, findsNothing);

    second.text = 'current query';
    await tester.pump();
    expect(_clearIcon, findsOneWidget);
    await tester.tap(_clearIcon);
    await tester.pump();
    expect(second.text, isEmpty);
    expect(first.text, 'stale query');
  });

  testWidgets(
      'external controller stays usable without listeners after unmount',
      (tester) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    await _pumpSearch(tester, controller);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.hasActiveListeners, isFalse);
    controller.text = 'after unmount';
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(controller.text, 'after unmount');
  });
}
