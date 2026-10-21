import 'dart:io';
import 'support/channel_contacts_fixture.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim/pages/contacts/select_contacts/friend_list/group_contact_picker.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/channels/channel_list_page.dart';
import 'package:openim/pages/channels/channel_entry.dart';
import 'package:openim/pages/channels/presentation/channel_avatar.dart';
import 'package:openim/pages/channels/create/channel_create_page.dart';
import 'package:openim/pages/channels/detail/channel_detail_page.dart';
import 'package:openim/pages/channels/models/channel_preview.dart';
import 'package:openim/pages/channels/settings/channel_settings_page.dart';
import 'package:openim/pages/channels/comments/channel_comments_page.dart';
import 'package:openim/pages/channels/detail/channel_profile_page.dart';
import 'package:openim/pages/channels/create/channel_intro_page.dart';
import 'package:openim/pages/channels/settings/channel_type_page.dart';
import 'package:openim/pages/channels/members/channel_members_page.dart';

Future<void> mount(WidgetTester tester, Widget page,
    {bool dark = false,
    double scale = 1,
    bool highContrast = false,
    Size size = const Size(390, 844),
    GlobalKey? capture}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  registerChannelContactsFixture();
  await tester.pumpWidget(GetMaterialApp(
    locale: const Locale('zh', 'CN'),
    translations: TranslationService(),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        colorSchemeSeed: AppTokens.accent,
        fontFamily: capture == null ? null : 'ChannelPreviewFont'),
    builder: (context, child) {
      ScreenUtil.init(context, designSize: const Size(390, 844));
      return MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale), highContrast: highContrast),
          child: child!);
    },
    home: RepaintBoundary(key: capture, child: page),
  ));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String text) async {
  await tester.pumpAndSettle();
  final finder = find.text(text).last;
  if (find.text(text).evaluate().isEmpty) {
    await tester.scrollUntilVisible(find.text(text), 250,
        scrollable: find
            .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable))
            .first);
  }
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await NavigationGlassController.instance
        .setMode(NavigationGlassMode.translucent);
  });
  tearDown(Get.reset);

  testWidgets(
      'directory entry shows group-style search and empty channel count',
      (tester) async {
    await mount(tester, const ChannelListPage());
    expect(find.byType(ChannelListPage), findsOneWidget);
    expect(find.byType(SearchBox), findsOneWidget);
    expect(find.text('暂无频道'), findsOneWidget);
    expect(find.text('共 0 个频道'), findsOneWidget);
    expect(find.text('日常灵感'), findsNothing);
    await tester.enterText(find.byType(TextField), '测试');
    await tester.pumpAndSettle();
    expect(find.text('没有找到频道'), findsOneWidget);
    expect(find.byTooltip('创建频道'), findsNothing);
    expect(find.byType(ChannelListPage), findsOneWidget);
    expect(find.text('没有找到频道'), findsOneWidget);
  });

  testWidgets('entry skips demo list and dismissal returns to origin',
      (tester) async {
    await mount(
        tester,
        Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => openChannelPages(context, create: true),
                    child: const Text('打开频道')))));
    await tap(tester, '打开频道');
    expect(find.byType(ChannelIntroPage), findsOneWidget);
    expect(find.byType(ChannelListPage), findsNothing);
    await tap(tester, '返回');
    expect(find.text('打开频道'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tap(tester, '打开频道');
    await tap(tester, '创建频道');
    expect(find.byType(GroupContactPicker), findsOneWidget);
    tester
        .widget<GroupContactPicker>(find.byType(GroupContactPicker))
        .onBack!();
    await tester.pumpAndSettle();
    expect(find.byType(ChannelListPage), findsNothing);
    expect(find.text('打开频道'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('channel sheets cover tab navigation and restore it on close',
      (tester) async {
    const navKey = Key('host-bottom-navigation');
    await mount(
        tester,
        Scaffold(
          body: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => const ChannelListPage(initialCreate: true),
                  )),
          bottomNavigationBar: const SizedBox(
            key: navKey,
            height: 72,
            child: Text('主导航'),
          ),
        ));
    final navPoint = tester.getCenter(find.byKey(navKey));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(BottomSheet)).contains(navPoint), isTrue);
    final introContext = tester.element(find.byType(ChannelIntroPage));
    expect(Navigator.of(introContext),
        Navigator.of(introContext, rootNavigator: true));
    await tap(tester, '创建频道');
    expect(find.byType(GroupContactPicker), findsOneWidget);
    expect(tester.getRect(find.byType(BottomSheet)).contains(navPoint), isTrue);
    tester
        .widget<GroupContactPicker>(find.byType(GroupContactPicker))
        .onBack!();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(navKey).hitTestable(), findsOneWidget);
    expect(find.byType(ChannelListPage), findsOneWidget);
  });

  testWidgets('create validates name, publishes, pins and finds local content',
      (tester) async {
    await mount(tester, const ChannelListPage(initialCreate: true));
    await tap(tester, '创建频道');
    expect(find.byType(GroupContactPicker), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group-picker-channel-friend')));
    await tester.pumpAndSettle();
    await tap(tester, '下一步');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.enterText(find.byKey(const Key('channel-name')), '测试频道');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('channel-next')))
            .onPressed,
        isNotNull);
    await tester.pumpAndSettle();
    await tap(tester, '下一步');
    expect(find.text('还没有消息'), findsOneWidget);
    await tap(tester, '发布消息');
    await tap(tester, '发布到预览');
    expect(find.text('请输入消息内容'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '第一条频道消息');
    await tap(tester, '发布到预览');
    expect(find.text('第一条频道消息'), findsOneWidget);
    await tester.tap(find.byTooltip('置顶消息'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('取消置顶'), findsOneWidget);
    await tester.tap(find.byTooltip('搜索消息'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有找到消息'), findsOneWidget);
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    expect(find.text('第一条频道消息'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('频道详情'));
    await tester.pumpAndSettle();
    await tap(tester, '频道设置');
    await tap(tester, '解散频道');
    await tap(tester, '删除');
    expect(find.byType(ChannelListPage), findsOneWidget);
    expect(find.text('测试频道'), findsNothing);
  });

  testWidgets('subscriber joins, reacts, comments and confirms leaving',
      (tester) async {
    final channel = ChannelPreview(
        name: '示例频道',
        description: '',
        owner: false,
        subscribed: false,
        posts: [ChannelPost('欢迎订阅')]);
    addTearDown(channel.dispose);
    await mount(tester, ChannelDetailPage(channel: channel));
    expect(find.text('发布消息'), findsNothing);
    await tap(tester, '订阅频道（预览）');
    await tap(tester, '回应');
    expect(find.text('已回应 1'), findsOneWidget);
    await tap(tester, '评论 0');
    await tester.enterText(find.byType(TextField), '很期待');
    await tester.pump();
    await tester.tap(find.byTooltip('发送评论'));
    await tester.pumpAndSettle();
    expect(find.text('很期待'), findsOneWidget);
    Navigator.of(tester.element(find.byType(ChannelCommentsPage))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('频道详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tap(tester, '退出');
    await tap(tester, '取消');
    expect(channel.subscribed, isTrue);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tap(tester, '退出');
    await tap(tester, '退出');
    expect(channel.subscribed, isFalse);
    expect(find.text('订阅频道（预览）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('small screen large text layout and labels ($dark)',
        (tester) async {
      final channel = ChannelPreview(
          name: '较长的频道名称与内容布局检查',
          description: '频道简介',
          posts: [ChannelPost('频道内容')]);
      addTearDown(channel.dispose);
      for (final page in [
        const ChannelCreatePage(),
        ChannelDetailPage(channel: channel),
        ChannelSettingsPage(channel: channel),
        ChannelTypePage(channel: channel),
        ChannelProfilePage(channel: channel),
        ChannelMembersPage(channel: channel, mode: ChannelMemberMode.admins),
        ChannelCommentsPage(channel: channel, post: channel.posts.first)
      ]) {
        await mount(tester, page,
            dark: dark,
            scale: 2,
            highContrast: true,
            size: const Size(320, 640));
        expect(tester.takeException(), isNull);
        final semantics = tester.ensureSemantics();
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
        await tester.pumpWidget(const SizedBox());
      }
    });
  }

  testWidgets(
      'comment composer stays above the keyboard and respects disabled comments',
      (tester) async {
    final channel =
        ChannelPreview(name: '频道', description: '', posts: [ChannelPost('内容')]);
    addTearDown(channel.dispose);
    await mount(tester,
        ChannelCommentsPage(channel: channel, post: channel.posts.first));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.byType(TextField)).dy,
        lessThanOrEqualTo(544));
    channel.update(() => channel.commentsEnabled = false);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('该频道已关闭评论'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manage preview subscribers, remove and restore them',
      (tester) async {
    final channel = ChannelPreview(name: '测试', description: '');
    addTearDown(channel.dispose);
    await mount(
        tester,
        ChannelMembersPage(
            channel: channel,
            mode: ChannelMemberMode.subscribers,
            adding: true));
    await tap(tester, '小林（示例）');
    expect(channel.members, contains('小林（示例）'));
    await tester.drag(
        find.byKey(const ValueKey('小林（示例）')), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tap(tester, '移除');
    expect(channel.members, ['我']);
    expect(channel.removedMembers, ['小林（示例）']);
    await tester.pumpWidget(const SizedBox());
    await mount(tester,
        ChannelMembersPage(channel: channel, mode: ChannelMemberMode.removed));
    await tap(tester, '恢复');
    expect(channel.removedMembers, isEmpty);
    expect(channel.members, contains('小林（示例）'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile editing retains changes only on save', (tester) async {
    final channel = ChannelPreview(name: '原名称', description: '');
    addTearDown(channel.dispose);
    await mount(tester, ChannelProfilePage(channel: channel));
    await tap(tester, '频道设置');
    await tap(tester, '频道名称');
    await tester.enterText(find.byType(TextField).first, '新名称');
    await tap(tester, '保存');
    expect(channel.name, '新名称');
    expect(find.text('新名称'), findsOneWidget);
    await tap(tester, '频道名称');
    await tester.enterText(find.byType(TextField).first, '不保存');
    Navigator.of(tester.element(find.byType(ChannelSettingsPage).last)).pop();
    await tester.pumpAndSettle();
    expect(channel.name, '新名称');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reference picker preserves selection when returning from the form',
      (tester) async {
    await mount(tester, const ChannelListPage(initialCreate: true));
    await tap(tester, '创建频道');
    await tester.tap(find.byKey(const ValueKey('group-picker-channel-friend')));
    await tester.pumpAndSettle();
    await tap(tester, '下一步');
    await tap(tester, '返回');
    expect(find.text('选择联系人'), findsOneWidget);
    expect(
        tester
            .widget<GroupContactPicker>(find.byType(GroupContactPicker))
            .selection
            .checkedList
            .keys,
        ['channel-friend']);
    await tap(tester, '下一步');
    await tester.enterText(find.byKey(const Key('channel-name')), '保留选择');
    final bytes =
        (await rootBundle.load('assets/images/channel_intro_99chat.png'))
            .buffer
            .asUint8List();
    tester.widget<ChannelAvatar>(find.byType(ChannelAvatar)).onChanged!(bytes);
    await tester.pumpAndSettle();
    await tap(tester, '下一步');
    await tester.tap(find.byTooltip('频道详情'));
    await tester.pumpAndSettle();
    expect(find.text('2位订阅者'), findsOneWidget);
    expect(
        tester
            .widget<ChannelProfilePage>(find.byType(ChannelProfilePage))
            .channel
            .selectedContacts
            .keys,
        ['channel-friend']);
    await tap(tester, '订阅者');
    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pumpAndSettle();
    expect(find.text('未找到匹配的订阅者'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('introduction handles small screens and text scaling',
      (tester) async {
    for (final dark in [false, true]) {
      await mount(tester, const ChannelIntroPage(),
          dark: dark, scale: 2, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
      await tester
          .ensureVisible(find.byKey(const ValueKey('channel-intro-create')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('preview screenshots', (tester) async {
    await tester.runAsync(() async {
      final bytes = ByteData.sublistView(
          await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
      await (FontLoader('ChannelPreviewFont')..addFont(Future.value(bytes)))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    });
    final channel = ChannelPreview(
        name: '日常灵感',
        description: '分享生活里的好点子，让每一天都有新发现。',
        owner: true,
        subscribed: true,
        posts: [
          ChannelPost('欢迎来到日常灵感。\n\n这里会分享阅读、摄影与生活中的小发现。订阅后，一起记录值得收藏的瞬间。',
              pinned: true)
        ]);
    channel.avatar = await tester.runAsync(() async => (await rootBundle.load(
            'packages/openim_common/assets/images/moments_cover_99chat.webp'))
        .buffer
        .asUint8List());
    addTearDown(channel.dispose);
    for (final dark in [false, true]) {
      for (final entry in {
        'create': const ChannelCreatePage(),
        'feed': ChannelDetailPage(channel: channel),
        'settings': ChannelSettingsPage(channel: channel),
        'intro': const ChannelIntroPage(),
        'type': ChannelTypePage(channel: channel, creating: true),
        'profile': ChannelProfilePage(channel: channel),
        'admins': ChannelMembersPage(
            channel: channel, mode: ChannelMemberMode.admins),
        'subscribers': ChannelMembersPage(
            channel: channel, mode: ChannelMemberMode.subscribers)
      }.entries) {
        final key = GlobalKey();
        await mount(tester, entry.value, dark: dark, capture: key);
        await tester.runAsync(() =>
            precacheImage(MemoryImage(channel.avatar!), key.currentContext!));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = File(
              'docs/previews/channels/${entry.key}-${dark ? 'dark' : 'light'}.png');
          await output.parent.create(recursive: true);
          await output.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox());
      }
    }
  }, skip: Platform.environment['EXPORT_CHANNEL_PREVIEW'] != '1');
}
