import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/media_browser/media_image_loading.dart';

void main() {
  testWidgets('fast loads do not flash; slow loads show feedback',
      (tester) async {
    await tester.pumpWidget(const CupertinoApp(home: MediaImageLoading()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const CupertinoApp(home: MediaImageLoading()));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
