import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/messages/forwarding/forward_success_feedback.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  testWidgets('forward success uses centered shared text toast and dismisses',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: EasyLoading.init(),
      home: const Scaffold(body: SizedBox.expand()),
    ));
    ForwardSuccessFeedback.show();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text(StrRes.sendSuccessfully), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    expect(
        tester.getCenter(find.text(StrRes.sendSuccessfully)).dy,
        closeTo(
            tester.view.physicalSize.height / tester.view.devicePixelRatio / 2,
            1));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text(StrRes.sendSuccessfully), findsNothing);
    await EasyLoading.dismiss(animation: false);
  });
}

