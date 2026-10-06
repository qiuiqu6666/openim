import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/widgets/fund_recipient_user_id.dart';
import 'package:openim_common/openim_common.dart';

class _Profiles {
  _Profiles() {
    resolver = ContactCardProfileResolver(
      fetchProfile: (target) {
        requests.add(target);
        final request = Completer<List<UserFullInfo>?>();
        responses.add(request);
        return request.future;
      },
      currentUserID: () => owner,
      currentToken: () => token,
    );
  }

  String? owner = 'signed-in-account';
  String? token = 'test-session';
  final requests = <String>[];
  final responses = <Completer<List<UserFullInfo>?>>[];
  late final ContactCardProfileResolver resolver;

  void complete(int index, String target, String? account) =>
      responses[index].complete([
        UserFullInfo(userID: target, account: account),
      ]);
}

Future<void> _pump(
  WidgetTester tester,
  _Profiles profiles, {
  String? userID = 'im_recipient',
  bool dark = false,
  double width = 260,
  double textScale = 1,
}) =>
    tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: Center(
              child: SizedBox(
                width: width,
                child: SingleChildScrollView(
                  child: FundRecipientUserID(
                    userID: userID,
                    resolver: profiles.resolver,
                    style: Theme.of(context).textTheme.bodyMedium!,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));

void main() {
  testWidgets('shows the matched public account and keeps leading zeroes',
      (tester) async {
    final profiles = _Profiles();
    await _pump(tester, profiles);
    expect(find.text('99Chat ID号：--'), findsOneWidget);
    expect(find.textContaining('im_recipient'), findsNothing);
    expect(profiles.requests, ['im_recipient']);

    profiles.complete(0, 'im_recipient', ' 0012345678 ');
    await tester.pump();
    expect(find.text('99Chat ID号：0012345678'), findsOneWidget);
    expect(find.textContaining('im_recipient'), findsNothing);
    await _pump(tester, profiles);
    expect(profiles.requests, ['im_recipient']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reuses an already resolved account without another lookup',
      (tester) async {
    final profiles = _Profiles();
    final request = profiles.resolver.resolve('im_recipient');
    profiles.complete(0, 'im_recipient', '@public-account');
    await request;

    await _pump(tester, profiles);
    expect(find.text('99Chat ID号：@public-account'), findsOneWidget);
    expect(profiles.requests, ['im_recipient']);
  });

  for (final scenario in [
    (name: 'mismatched profile', target: 'im_other', account: '@other'),
    (name: 'missing account', target: 'im_recipient', account: null),
    (name: 'blank account', target: 'im_recipient', account: '   '),
  ]) {
    testWidgets('${scenario.name} never falls back to the internal identifier',
        (tester) async {
      final profiles = _Profiles();
      await _pump(tester, profiles);
      profiles.complete(0, scenario.target, scenario.account);
      await tester.pump();

      expect(find.text('99Chat ID号：--'), findsOneWidget);
      expect(find.textContaining('im_recipient'), findsNothing);
      expect(find.textContaining('@other'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an empty recipient does not request a profile', (tester) async {
    final profiles = _Profiles();
    await _pump(tester, profiles, userID: null);
    expect(find.text('99Chat ID号：--'), findsOneWidget);
    expect(profiles.requests, isEmpty);

    await _pump(tester, profiles, userID: '   ');
    expect(profiles.requests, isEmpty);
    expect(find.text('99Chat ID号：--'), findsOneWidget);
  });

  testWidgets('a changed recipient rejects the previous late profile',
      (tester) async {
    final profiles = _Profiles();
    await _pump(tester, profiles, userID: 'im_previous');
    await _pump(tester, profiles, userID: 'im_current');
    expect(profiles.requests, ['im_previous', 'im_current']);

    profiles.complete(0, 'im_previous', '@previous');
    await tester.pump();
    expect(find.textContaining('@previous'), findsNothing);
    expect(find.text('99Chat ID号：--'), findsOneWidget);

    profiles.complete(1, 'im_current', '@current');
    await tester.pumpAndSettle();
    expect(find.text('99Chat ID号：@current'), findsOneWidget);
    expect(find.textContaining('im_'), findsNothing);
  });

  for (final change in ['account', 'token']) {
    testWidgets('a late lookup from a changed $change cannot show its account',
        (tester) async {
      final profiles = _Profiles();
      await _pump(tester, profiles);
      if (change == 'account') {
        profiles.owner = 'next-account';
      } else {
        profiles.token = 'next-session';
      }
      profiles.complete(0, 'im_recipient', '@old-session');
      await tester.pump();

      expect(find.text('99Chat ID号：--'), findsOneWidget);
      expect(find.textContaining('@old-session'), findsNothing);
      expect(find.textContaining('im_recipient'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('rebuilding after an account change clears the old account',
      (tester) async {
    final profiles = _Profiles();
    await _pump(tester, profiles);
    profiles.complete(0, 'im_recipient', '@old-account');
    await tester.pump();
    expect(find.text('99Chat ID号：@old-account'), findsOneWidget);

    profiles.owner = 'next-account';
    profiles.token = 'next-session';
    await _pump(tester, profiles);
    expect(find.textContaining('@old-account'), findsNothing);
    expect(find.textContaining('im_recipient'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late lookup after closing the widget is harmless',
      (tester) async {
    final profiles = _Profiles();
    await _pump(tester, profiles);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    profiles.complete(0, 'im_recipient', '@closed');
    await tester.pump();
    expect(find.textContaining('@closed'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacing the profile source rejects its previous late result',
      (tester) async {
    final previous = _Profiles();
    final current = _Profiles();
    await _pump(tester, previous);
    await _pump(tester, current);
    previous.complete(0, 'im_recipient', '@previous-source');
    await tester.pump();
    expect(find.textContaining('@previous-source'), findsNothing);

    current.complete(0, 'im_recipient', '@current-source');
    await tester.pumpAndSettle();
    expect(find.text('99Chat ID号：@current-source'), findsOneWidget);
  });

  testWidgets('a failed optional lookup leaves a placeholder', (tester) async {
    final profiles = _Profiles();
    await _pump(tester, profiles);
    profiles.responses.single.completeError(StateError('test lookup failure'));
    await tester.pump();
    expect(find.text('99Chat ID号：--'), findsOneWidget);
    expect(find.textContaining('im_recipient'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'long public account stays selectable without overflow dark=$dark',
        (tester) async {
      final profiles = _Profiles();
      final account = List.filled(8, 'user1234567890').join();
      await _pump(tester, profiles, dark: dark, width: 200, textScale: 2);
      profiles.complete(0, 'im_recipient', account);
      await tester.pump();

      final text = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(text.data, '99Chat ID号：$account');
      expect(text.maxLines, isNull);
      expect(
          tester.getSize(find.byType(SelectableText)).height, greaterThan(50));
      expect(find.textContaining('im_recipient'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
