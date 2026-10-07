import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/announcements/group_announcement_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _notice =
    'A long announcement that keeps scrolling across the narrow banner.';

void main() {
  testWidgets('marquee keeps its spacing, speed and seamless loop',
      (tester) async {
    await _mount(tester);
    final lines = find.text(_notice);
    expect(lines, findsNWidgets(2));
    final first = tester.getTopLeft(lines.at(0));
    final second = tester.getTopLeft(lines.at(1));
    final distance = second.dx - first.dx;
    expect(distance, closeTo(tester.getSize(lines.first).width - 1 + 48, .01));
    await tester.pump(const Duration(seconds: 9));
    expect(tester.getTopLeft(lines.first).dx,
        closeTo(first.dx - distance / 4, .01));
    expect(tester.getTopLeft(lines.at(1)).dx,
        closeTo(second.dx - distance / 4, .01));
    await tester.pump(const Duration(seconds: 27));
    expect(tester.getTopLeft(lines.first).dx, closeTo(first.dx, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('marquee does not rebuild its text on animation frames',
      (tester) async {
    await _mount(tester);
    var textBuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget case Text(data: _notice)) textBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(textBuilds, 0, reason: 'The two laid-out copies should be reused');
  });

  testWidgets('dismissing a scrolling banner stops its ticker', (tester) async {
    await _mount(tester);
    expect(tester.hasRunningAnimations, isTrue);
    await tester.tap(find.byKey(const ValueKey('group-announcement-close')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_notice), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  for (final change in ['short text', 'reduced motion', 'wider viewport']) {
    testWidgets('$change stops scrolling and can resume', (tester) async {
      await _mount(tester);
      final state = tester.state<_HostState>(find.byType(_Host));
      state.update(change);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.hasRunningAnimations, isFalse);
      state.update('reset');
      await tester.pump();
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      expect(find.text(_notice), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(3200, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(
      {'group_announcement_read:user:group': _notice});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: _Host(prefs))));
  await tester.pump();
}

class _Host extends StatefulWidget {
  const _Host(this.preferences);
  final SharedPreferences preferences;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String mode = 'reset';
  void update(String value) => setState(() {
        mode = value;
        widget.preferences.setString('group_announcement_read:user:group',
            mode == 'short text' ? 'Hi' : _notice);
      });

  @override
  Widget build(BuildContext context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: mode == 'reduced motion'),
        child: UnconstrainedBox(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: mode == 'wider viewport' ? 3000 : 320,
            child: GroupAnnouncementBanner(
              text: mode == 'short text' ? 'Hi' : _notice,
              groupID: 'group',
              userID: 'user',
              preferences: widget.preferences,
            ),
          ),
        ),
      );
}
