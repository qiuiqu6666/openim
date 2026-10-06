import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/scanning/friend_qr_scanner.dart';
import 'package:openim_common/openim_common.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/contacts/native_qr_scanner.dart';

const _invite = 'openim://user/peer?source=qrcode&inviteCode=fi_test';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await NavigationGlassController.instance
        .setMode(NavigationGlassMode.translucent);
  });
  testWidgets('opaque route pauses existing scanner and pop resumes it',
      (tester) async {
    final h = _ScannerHost(tester);
    try {
      await h.mount();
      final scanner = tester.state(find.byType(FriendQrScanner));
      h.native.cameraCalls.clear();

      h.cover();
      await tester.pumpAndSettle();
      expect(h.native.cameraCalls, contains('pauseCamera'));
      expect(h.native.cameraCalls, isNot(contains('resumeCamera')));
      await h.native.recognize(_invite);
      await tester.pump();
      expect(find.text('Covered page'), findsOneWidget);
      expect(h.results, isEmpty,
          reason: 'A covered scanner cannot consume a valid invitation');

      h.native.cameraCalls.clear();
      h.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(FriendQrScanner)), same(scanner));
      expect(h.native.cameraCalls, contains('resumeCamera'));
      await h.native.recognize(_invite);
      await tester.pumpAndSettle();
      expect(h.results, [
        {'userID': 'peer', 'inviteCode': 'fi_test', 'source': 'qrcode'}
      ]);
      expect(find.text('Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await h.close();
    }
  });

  testWidgets('uncovering while backgrounded does not resume the camera',
      (tester) async {
    final h = _ScannerHost(tester);
    try {
      await h.mount();
      h.cover();
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      h.native.cameraCalls.clear();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.native.cameraCalls, isNot(contains('resumeCamera')),
          reason: 'Foregrounding cannot resume a covered scanner');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      h.native.cameraCalls.clear();

      h.navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byType(FriendQrScanner, skipOffstage: false), findsOneWidget);
      expect(h.native.cameraCalls, isNot(contains('resumeCamera')));
      await h.native.recognize(_invite);
      await tester.pump();
      expect(h.results, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.native.cameraCalls, contains('resumeCamera'));
      await h.native.recognize(_invite);
      await tester.pumpAndSettle();
      expect(h.results.single?['userID'], 'peer');
      expect(tester.takeException(), isNull);
    } finally {
      await h.close();
    }
  });

  testWidgets('barcode arriving during scanner dismissal cannot pop again',
      (tester) async {
    final h = _ScannerHost(tester);
    try {
      await h.mount();
      final lateCreated = tester
          .widget<AndroidView>(find.byType(AndroidView))
          .onPlatformViewCreated!;

      h.navigator.currentState!.pop();
      // The outgoing QRView is still mounted during this frame. This represents
      // a native result already in transit while the user closes the scanner.
      await h.native.recognize(_invite);
      await tester.pumpAndSettle();
      expect(h.results, [null]);
      expect(find.text('Home'), findsOneWidget);
      expect(find.byType(FriendQrScanner), findsNothing);

      final commands = h.native.cameraCalls.length;
      lateCreated(9999); // A delayed platform-view creation after unmount.
      await tester.pump();
      expect(h.native.cameraCalls, hasLength(commands));
      expect(h.results, [null]);
      expect(tester.takeException(), isNull);
    } finally {
      await h.close();
    }
  });
}

class _ScannerHost {
  _ScannerHost(this.tester) : native = NativeQrScanner(tester) {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  }

  Future<void> close() async {
    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      native.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  }

  final WidgetTester tester;
  final NativeQrScanner native;
  final navigator = GlobalKey<NavigatorState>();
  final results = <Map<String, String>?>[];

  Future<void> mount() async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(builder: (context) {
        return Scaffold(
          body: Column(children: [
            const Text('Home'),
            TextButton(
                onPressed: () async {
                  results.add(await scanFriendQrCode(context));
                },
                child: const Text('Open scanner')),
          ]),
        );
      }),
    ));
    await tester.tap(find.text('Open scanner'));
    await tester.pumpAndSettle();
    expect(find.byType(QRView), findsOneWidget);
    expect(find.byType(AndroidView), findsOneWidget);
    expect(native.channel, isNotNull);
    await native.permission(true);
    await tester.pumpAndSettle();
    expect(native.cameraCalls, contains('resumeCamera'));
  }

  void cover() {
    unawaited(navigator.currentState!.push<void>(MaterialPageRoute(
      builder: (_) => const Scaffold(body: Text('Covered page')),
    )));
  }
}
