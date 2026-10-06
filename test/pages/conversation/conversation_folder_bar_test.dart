import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/conversation_organizer.dart';
import 'package:openim/pages/conversation/folders/conversation_folder_bar.dart';
import 'package:openim_common/openim_common.dart';

ChatFolder _folder(String id, String name) => ChatFolder.fromJson({
      'id': id,
      'name': name,
      'sortOrder': 0,
      'createdAt': 1,
      'updatedAt': 1,
    });

void _noop() {}

ConversationFolderBar _bar({
  required List<ChatFolder> folders,
  String? selected,
  int Function(ChatFolder)? unread,
  bool Function(ChatFolder)? notifiable,
  VoidCallback onAll = _noop,
  ValueChanged<String>? onSelect,
  VoidCallback onCreate = _noop,
  ValueChanged<ChatFolder>? onLongPress,
  bool editing = false,
  VoidCallback? onExit,
  ValueChanged<ChatFolder>? onDelete,
  void Function(int, int)? onReorder,
}) =>
    ConversationFolderBar(
      folders: folders,
      selectedFolderID: selected,
      unreadForFolder: unread ?? (_) => 0,
      hasNotifiableUnreadForFolder: notifiable ?? (_) => true,
      onSelectAll: onAll,
      onSelectFolder: onSelect ?? (_) {},
      onCreateFolder: onCreate,
      onFolderLongPress: onLongPress ?? (_) {},
      reorderEditing: editing,
      onExitReorderEditing: onExit,
      onDeleteFolder: onDelete,
      onReorderFolders: onReorder,
    );

Widget _host(Widget child, {bool dark = false, bool reduceMotion = false}) =>
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN')],
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: const Size(375, 812),
            disableAnimations: reduceMotion,
          ),
          child: SizedBox(width: 375, child: Column(children: [child])),
        ),
      ),
    );

BoxDecoration _segmentDecoration(WidgetTester tester, String label) => tester
    .widget<AnimatedContainer>(find
        .ancestor(
            of: find.text(label), matching: find.byType(AnimatedContainer))
        .first)
    .decoration! as BoxDecoration;

BoxDecoration _badgeDecoration(WidgetTester tester, String label) => tester
    .widget<Container>(find
        .ancestor(of: find.text(label), matching: find.byType(Container))
        .first)
    .decoration! as BoxDecoration;

void main() {
  testWidgets('no folders leave no bar space or create control',
      (tester) async {
    await tester.pumpWidget(_host(_bar(folders: [])));
    expect(tester.getSize(find.byType(ConversationFolderBar)).height, 0);
    expect(find.text('全部'), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.byType(ReorderableListView), findsNothing);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final dark in [false, true]) {
      testWidgets(
          'capsule geometry and theme stay consistent ($platform/$dark)',
          (tester) async {
        await tester.pumpWidget(_host(
          _bar(folders: [_folder('work', '工作')], selected: 'work'),
          dark: dark,
        ));
        final bar = find.byType(ConversationFolderBar);
        expect(tester.getSize(bar), const Size(375, 45));
        expect(tester.getSize(find.byType(ReorderableListView)).height, 32);
        final addContainer = find
            .ancestor(
                of: find.byIcon(Icons.add_rounded),
                matching: find.byType(Container))
            .first;
        expect(tester.getSize(addContainer), const Size(32, 32));
        expect(tester.getRect(addContainer).right, 363);
        final colors = Theme.of(tester.element(bar)).colorScheme;
        final addDecoration =
            tester.widget<Container>(addContainer).decoration! as BoxDecoration;
        expect(addDecoration.color,
            dark ? colors.surfaceContainerLow : AppTokens.surfaceLight);
        expect(_segmentDecoration(tester, '工作').color,
            dark ? colors.surfaceContainerHighest : const Color(0xFFECECEC));
        expect(_segmentDecoration(tester, '全部').color, Colors.transparent);
        final title = tester.widget<Text>(find.text('工作'));
        expect(title.style!.fontSize, 14);
        expect(title.style!.fontWeight, FontWeight.w600);
        expect(title.style!.color,
            dark ? colors.onSurface : AppTokens.textPrimaryLight);
        final decoratedSurfaces = tester
            .widgetList<DecoratedBox>(
                find.descendant(of: bar, matching: find.byType(DecoratedBox)))
            .map((widget) => widget.decoration)
            .whereType<BoxDecoration>()
            .where((decoration) => decoration.boxShadow != null)
            .toList();
        expect(decoratedSurfaces, hasLength(2));
        for (final decoration in decoratedSurfaces) {
          if (!dark && platform == TargetPlatform.iOS) {
            expect(decoration.boxShadow, hasLength(1));
            expect(decoration.boxShadow!.single.color,
                const Color(0xFF000000).withValues(alpha: .06));
          } else {
            expect(decoration.boxShadow, isEmpty);
          }
        }
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant({platform}));
    }
  }

  for (final dark in [false, true]) {
    testWidgets('large and muted unread badges remain distinct ($dark)',
        (tester) async {
      await tester.pumpWidget(_host(
        _bar(
          folders: [_folder('work', '工作'), _folder('family', '家庭')],
          unread: (folder) => folder.id == 'work' ? 120 : 2,
          notifiable: (folder) => folder.id == 'work',
        ),
        dark: dark,
      ));
      expect(find.text('99+'), findsOneWidget);
      expect(find.text('120'), findsNothing);
      final colors =
          Theme.of(tester.element(find.byType(ConversationFolderBar)))
              .colorScheme;
      expect(_badgeDecoration(tester, '99+').color, const Color(0xFFFF524B));
      expect(_badgeDecoration(tester, '2').color,
          dark ? colors.secondaryContainer : const Color(0xFFA8A8AE));
      final mutedText = tester.widget<Text>(find.text('2'));
      expect(mutedText.style!.color,
          dark ? colors.onSecondaryContainer : AppTokens.onAccent);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('all, folder, create and long press reach their owning callbacks',
      (tester) async {
    final folder = _folder('work', '工作');
    final calls = <String>[];
    ChatFolder? longPressed;
    await tester.pumpWidget(_host(_bar(
      folders: [folder],
      onAll: () => calls.add('all'),
      onSelect: (id) => calls.add(id),
      onCreate: () => calls.add('create'),
      onLongPress: (value) => longPressed = value,
    )));
    await tester.tap(find.text('工作'));
    await tester.tap(find.text('全部'));
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.longPress(find.text('工作'));
    await tester.pumpAndSettle();
    expect(calls, ['work', 'all', 'create']);
    expect(longPressed, same(folder));
  });

  testWidgets('reordering needs edit mode and a real parent callback',
      (tester) async {
    final folders = [_folder('work', '工作'), _folder('family', '家庭')];
    final reorders = <List<int>>[];
    void record(int oldIndex, int newIndex) =>
        reorders.add([oldIndex, newIndex]);
    for (final state in [
      (editing: false, callback: record),
      (editing: true, callback: null),
      (editing: true, callback: record),
    ]) {
      await tester.pumpWidget(_host(
        _bar(
          folders: folders,
          editing: state.editing,
          onReorder: state.callback,
        ),
        reduceMotion: true,
      ));
      final enabled = state.editing && state.callback != null;
      for (final listener
          in tester.widgetList<ReorderableDelayedDragStartListener>(
              find.byType(ReorderableDelayedDragStartListener))) {
        expect(listener.enabled, enabled);
      }
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorder(0, 2);
      await tester.pump();
    }
    expect(reorders, [
      [0, 2]
    ]);
    // A callback is a request, not a fabricated local order confirmation.
    expect(tester.getRect(find.text('工作')).left,
        lessThan(tester.getRect(find.text('家庭')).left));
    expect(folders.map((folder) => folder.id), ['work', 'family']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing exposes delete and check without starting create',
      (tester) async {
    final folder = _folder('work', '工作');
    var exits = 0;
    var creates = 0;
    ChatFolder? deleted;
    await tester.pumpWidget(_host(
      _bar(
        folders: [folder],
        editing: true,
        onCreate: () => creates++,
        onExit: () => exits++,
        onDelete: (value) => deleted = value,
        onReorder: (_, __) {},
      ),
      reduceMotion: true,
    ));
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(deleted, same(folder));
    await tester.tap(find.byIcon(Icons.check_rounded));
    expect(exits, 1);
    expect(creates, 0);
    await tester.tap(find.text('全部'));
    expect(exits, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long folder lists stay horizontally scrollable at fixed height',
      (tester) async {
    final folders = [
      for (var index = 0; index < 12; index++)
        _folder('folder-$index', '消息分组$index'),
    ];
    await tester.pumpWidget(_host(_bar(folders: folders)));
    final bar = find.byType(ConversationFolderBar);
    expect(tester.getSize(bar).height, 45);
    final list = find.byType(ReorderableListView);
    await tester.drag(list, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<ReorderableListView>(list).scrollController!.offset,
        greaterThan(0));
    expect(tester.getSize(bar).height, 45);
    expect(tester.takeException(), isNull);
  });
}
