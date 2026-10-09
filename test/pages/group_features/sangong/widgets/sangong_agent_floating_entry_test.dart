import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/widgets/sangong_agent_floating_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpEntry(WidgetTester tester, String conversationId,
    {required bool dark}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      platform: dark ? TargetPlatform.iOS : TargetPlatform.android,
    ),
    home: Scaffold(
      body: Builder(builder: (context) {
        return Stack(children: [
          SangongAgentFloatingEntry(
            theme: SangongFloatTheme.of(context),
            conversationId: conversationId,
            onOpenQuery: () {},
            onOpenTeam: () {},
            onOpenPersonal: () {},
          ),
        ]);
      }),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('agent buttons start expanded and remember hide dark=$dark',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final conversationId = 'first-agent-entry-$dark';
      await _pumpEntry(tester, conversationId, dark: dark);
      for (final label in ['查', '团', '个', '隐']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('隐'));
      await tester.pumpAndSettle();
      expect(find.text('显'), findsOneWidget);
      expect(find.text('查'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('agent_rebate_float_v2:$conversationId:expanded'),
          false);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpEntry(tester, conversationId, dark: dark);
      expect(find.text('显'), findsOneWidget);
      expect(find.text('查'), findsNothing);
      await tester.tap(find.text('显'));
      await tester.pumpAndSettle();
      for (final label in ['查', '团', '个', '隐']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('saved hidden preference overrides expanded default dark=$dark',
        (tester) async {
      final conversationId = 'saved-hidden-agent-entry-$dark';
      SharedPreferences.setMockInitialValues({
        'agent_rebate_float_v2:$conversationId:expanded': false,
      });
      await _pumpEntry(tester, conversationId, dark: dark);
      expect(find.text('显'), findsOneWidget);
      expect(find.text('查'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
