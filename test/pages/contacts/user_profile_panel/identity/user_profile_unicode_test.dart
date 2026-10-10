import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/user_profile_panel/user_profile_tokens.dart';
import 'package:openim/pages/contacts/user_profile_panel/widgets/user_profile_identity.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../support/unicode/unicode_samples.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('Unicode identity layout $platform/$brightness/$scale',
            (tester) async {
          tester.view.physicalSize = const Size(320, 650);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(375, 812),
            builder: (_, __) => MaterialApp(
              theme: ThemeData(platform: platform, brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final sample in unicodeSamples)
                        UserProfileIdentity(
                          key: ValueKey(sample.name),
                          name: sample.text,
                          signature: '${sample.text}\n${sample.text}',
                          account: '',
                          reserveAccountSpace: true,
                          copyLabel: 'Copy account',
                          onCopy: () {},
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ));

          for (final sample in unicodeSamples) {
            final identity = find.byKey(ValueKey(sample.name));
            final rawSignature = '${sample.text}\n${sample.text}';
            final signature = find.descendant(
              of: identity,
              matching: find.byWidgetPredicate(
                  (widget) => widget is Text && widget.data == rawSignature),
            );
            expect(signature, findsOneWidget);
            final text = tester.widget<Text>(signature);
            expect(text.strutStyle?.forceStrutHeight, isNot(true));
            expect(text.style?.fontSize, AppTokens.captionFontSize);
            expect(text.style?.height, UserProfileTokens.signatureLineHeight);

            final paragraph = tester.renderObject<RenderParagraph>(find
                .descendant(of: signature, matching: find.byType(RichText)));
            expect(
                paragraph.text.toPlainText().codeUnits, rawSignature.codeUnits,
                reason: sample.name);
            expect(tester.getSize(signature).height,
                greaterThanOrEqualTo(scale * 14 * 1.3 * 2));
            expect(tester.takeException(), isNull, reason: sample.name);
          }
        });
      }
    }
  }
}
