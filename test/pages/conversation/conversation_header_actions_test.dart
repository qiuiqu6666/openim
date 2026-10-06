import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/widgets/conversation_header_actions.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('header actions keep source order and callbacks ($dark)',
        (tester) async {
      final plusKey = GlobalKey();
      final calls = <String>[];
      await tester.pumpWidget(_host(
        dark: dark,
        child: ConversationHeaderActions(
          editing: false,
          onSupport: () => calls.add('support'),
          onToggleEditing: () => calls.add('edit'),
          plusKey: plusKey,
          plusTurns: .125,
          onPlus: () => calls.add('plus'),
        ),
      ));
      await tester.pumpAndSettle();
      final support = find.byTooltip('在线客服');
      final edit = find.byTooltip('编辑');
      final plus = find.byKey(plusKey);
      expect(tester.getCenter(support).dx, lessThan(tester.getCenter(edit).dx));
      expect(tester.getCenter(edit).dx, lessThan(tester.getCenter(plus).dx));
      expect(tester.getSize(plus).width, greaterThanOrEqualTo(48));
      final svg =
          tester.widgetList<SvgPicture>(find.byType(SvgPicture)).toList();
      expect(svg.first.width, 26);
      expect(svg.first.height, 26);
      expect(svg.first.colorFilter,
          const ColorFilter.mode(AppTokens.accent, BlendMode.srcIn));
      expect(svg.last.width, 24);
      final rotation =
          tester.widget<AnimatedRotation>(find.byType(AnimatedRotation));
      expect(rotation.turns, .125);
      expect(rotation.duration, const Duration(milliseconds: 220));
      await tester.tap(support);
      await tester.tap(edit);
      await tester.tap(plus);
      expect(calls, ['support', 'edit', 'plus']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('missing plus resource keeps header usable ($dark)',
        (tester) async {
      final imageCache = tester.binding.imageCache;
      imageCache
        ..clear()
        ..clearLiveImages();
      addTearDown(() {
        imageCache
          ..clear()
          ..clearLiveImages();
      });
      final bundle = _MissingPlusBundle();
      final plusKey = GlobalKey();
      var plusTaps = 0;
      await tester.pumpWidget(DefaultAssetBundle(
        bundle: bundle,
        child: _host(
          dark: dark,
          child: ConversationHeaderActions(
            editing: false,
            onSupport: () {},
            onToggleEditing: () {},
            plusKey: plusKey,
            plusTurns: .125,
            onPlus: () => plusTaps++,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final fallback =
          find.byKey(const ValueKey('conversation-plus-fallback'));
      expect(bundle.missingPlusLoads, greaterThan(0));
      expect(fallback, findsOneWidget);
      expect(tester.getSize(fallback), const Size(24, 24));
      expect(tester.getSize(find.byKey(plusKey)), const Size(48, 48));
      expect(tester.getSize(find.byType(ConversationHeaderActions)).width, 144);
      expect(find.textContaining('Unable to load'), findsNothing);
      final rotation =
          tester.widget<AnimatedRotation>(find.byType(AnimatedRotation));
      expect(rotation.turns, .125);
      expect(rotation.duration, const Duration(milliseconds: 220));
      expect(rotation.curve, Curves.easeInOut);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(plusKey));
      await tester.pump();
      expect(plusTaps, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('editing exposes only localized Done action', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(
      dark: false,
      locale: const Locale('en'),
      child: ConversationHeaderActions(
        editing: true,
        onSupport: () => fail('support must be hidden'),
        onToggleEditing: () => done++,
        plusKey: GlobalKey(),
        plusTurns: 0,
        onPlus: () => fail('plus must be hidden'),
      ),
    ));
    expect(find.byType(IconButton), findsNothing);
    expect(find.text('Done'), findsOneWidget);
    expect(
        tester.widget<Text>(find.text('Done')).style?.color, AppTokens.accent);
    await tester.tap(find.text('Done'));
    expect(done, 1);
    expect(tester.takeException(), isNull);
  });
}

Widget _host({
  required bool dark,
  required Widget child,
  Locale locale = const Locale('zh', 'CN'),
}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: Scaffold(appBar: AppBar(actions: [child])),
    );

class _MissingPlusBundle extends CachingAssetBundle {
  int missingPlusLoads = 0;

  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith('home_nav_plus_99chat.png')) {
      missingPlusLoads++;
      throw FlutterError('Intentionally missing plus asset: $key');
    }
    return rootBundle.load(key);
  }
}
