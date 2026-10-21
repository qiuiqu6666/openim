import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/login/widgets/login_toolbar.dart';
import 'package:openim/widgets/auth/auth_version_footer.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  for (final build in ['128', '']) {
    testWidgets('shared entry footer reads installed version with build $build',
        (tester) async {
      PackageInfo.setMockInitialValues(
        appName: '99Chat',
        packageName: 'test.app',
        version: '4.2.1',
        buildNumber: build,
        buildSignature: '',
      );
      final expected = build.isEmpty ? '4.2.1' : '4.2.1+$build';
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Column(
        children: [
          AuthVersionFooter(version: expected),
          const AuthEntryFooter(),
          const AuthVersionFooter(),
        ],
      ))));
      await tester.pumpAndSettle();
      expect(find.text('Version $expected'), findsNWidgets(3));
      expect(find.text('Version 3.8.3'), findsNothing);
    });
  }
}
