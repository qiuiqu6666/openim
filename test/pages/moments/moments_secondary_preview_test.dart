import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim/pages/moments/moments_compose_page.dart';
import 'package:openim/pages/moments/moments_cover_page.dart';
import 'package:openim/pages/moments/moments_draft_store.dart';
import 'package:openim/pages/moments/moments_notifications_page.dart';
import 'package:openim/pages/moments/moments_privacy_friend_picker.dart';
import 'package:openim/pages/moments/moments_privacy_list_page.dart';
import 'package:openim/pages/moments/moments_settings_page.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy/privacy_test_store.dart';
import 'support/moments_ui_fixture.dart';
import 'support/moments_ui_host.dart';

final _exportPreview =
    Platform.environment['EXPORT_MOMENTS_SECONDARY_PREVIEW'] == '1' ||
        const String.fromEnvironment('EXPORT_MOMENTS_SECONDARY_PREVIEW') == '1';

enum _Surface {
  compose,
  cover,
  notifications,
  settings,
  privacyEmpty,
  privacyFilled,
  friendPicker,
  notificationsEmpty,
  settingsError,
}

class _PreviewApi extends MomentsUiApi {
  _PreviewApi(this.surface) : super(posts: momentsUiPosts());
  final _Surface surface;

  @override
  Future<MomentsSettings> settings() async {
    if (surface == _Surface.settingsError) {
      throw const MomentsException('Offline preview');
    }
    return const MomentsSettings(visibleRangeDays: 90, version: 4);
  }

  @override
  Future<MomentsPageResult<MomentNotification>> notifications(
          {String? cursor, int pageSize = 20}) async =>
      surface == _Surface.notificationsEmpty
          ? const MomentsPageResult(items: [])
          : const MomentsPageResult(
              items: [
                  MomentNotification(
                      notificationId: 'preview-like',
                      actor: momentsUiFriend,
                      type: 'LIKE',
                      momentId: momentsUiOwnPostId,
                      momentText: '阳光刚好，心情也刚好。',
                      createdAt: 1791164400000,
                      seq: 3),
                  MomentNotification(
                      notificationId: 'preview-comment',
                      actor: momentsUiSecondFriend,
                      type: 'COMMENT',
                      momentId: momentsUiOwnPostId,
                      momentText: '把这一刻留在相册里。',
                      comment: MomentComment(
                          commentId: 'preview-inbox-comment',
                          author: momentsUiSecondFriend,
                          text: '下次一起去吧！'),
                      createdAt: 1791160800000,
                      seq: 2),
                  MomentNotification(
                      notificationId: 'preview-reply',
                      actor: momentsUiFriend,
                      type: 'REPLY',
                      momentId: momentsUiOwnPostId,
                      momentText: '路上的风，和远处的山。',
                      replyToUser: momentsUiSelf,
                      comment: MomentComment(
                          commentId: 'preview-inbox-reply',
                          author: momentsUiFriend,
                          text: '周末见！'),
                      read: true,
                      createdAt: 1791157200000,
                      seq: 1),
                ],
              unreadCount: 2,
              seenWatermark: 'preview-watermark',
              readThroughSeq: 3);
}

Future<void> _loadFonts() async {
  final bytes = ByteData.sublistView(
      await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
  for (final family in [
    'MomentsSecondaryPreviewFont',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
  ]) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}

Future<void> _decode(ImageProvider provider) async {
  final stream = provider.resolve(ImageConfiguration.empty);
  final ready = Completer<void>();
  late ImageStreamListener listener;
  listener = ImageStreamListener((info, __) {
    if (!ready.isCompleted) ready.complete();
    stream.removeListener(listener);
    info.dispose();
  }, onError: (Object error, StackTrace? stack) {
    if (!ready.isCompleted) ready.completeError(error, stack);
    stream.removeListener(listener);
  });
  stream.addListener(listener);
  await ready.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    if (_exportPreview) await _loadFonts();
  });

  for (final surface in _Surface.values) {
    for (final dark in [false, true]) {
      testWidgets('export actual secondary ${surface.name} ($dark)',
          (tester) async {
        final api = _PreviewApi(surface);
        final selections =
            surface == _Surface.privacyFilled || surface == _Surface.settings
                ? MomentsPrivacySelections(
                    blockedViewerIds: [momentsUiFriend.userId],
                    hiddenAuthorIds: [momentsUiSecondFriend.userId])
                : MomentsPrivacySelections.empty;
        final repository = MomentsRepository(
            api: api,
            userIdProvider: () => momentsUiSelf.userId,
            environmentProvider: () => momentsUiServer,
            friendLoader: () async =>
                const [momentsUiFriend, momentsUiSecondFriend],
            privacySelectionStore: MemoryPrivacySelectionStore(
                initial: selections,
                ownerUserId: momentsUiSelf.userId,
                baseUrl: momentsUiServer),
            subscribeToSdk: false);
        addTearDown(repository.dispose);
        Directory? directory;
        final store = MomentsDraftStore(
            repository: repository,
            read: () async => null,
            write: (_) async {},
            directory: () async => directory!);
        addTearDown(store.dispose);
        await store.load();
        if (surface == _Surface.compose) {
          await tester.runAsync(() async {
            directory = await Directory.systemTemp
                .createTemp('moments-secondary-preview-');
            final photos = <File>[];
            for (final name in ['scenery', 'car']) {
              final bytes = await rootBundle.load(
                  'packages/openim_common/assets/images/chat_backgrounds/$name.png');
              final file = File(p.join(directory!.path, '$name.png'));
              await file.writeAsBytes(bytes.buffer.asUint8List());
              photos.add(file);
            }
            await store.addFiles(photos);
            for (final media in store.media) {
              final provider = FileImage(File(media.path));
              await _decode(provider);
              await _decode(ResizeImage.resizeIfNeeded(480, null, provider));
            }
          });
          store.updateText('慢下来，发现生活里的小美好。\n把这一路的风景和心情记录下来。');
        }
        await tester.runAsync(() async {
          for (final name in ['moments_cover_99chat', 'empty_99chat']) {
            await _decode(AssetImage('assets/images/$name.webp',
                package: 'openim_common'));
          }
        });
        final page = switch (surface) {
          _Surface.compose => MomentsComposePage(
              repository: repository,
              draftStore: store,
              displayName: momentsUiSelf.nickname),
          _Surface.cover => MomentsCoverPage(repository: repository),
          _Surface.notifications ||
          _Surface.notificationsEmpty =>
            MomentsNotificationsPage(
                repository: repository, onOpenMoment: (_) {}),
          _Surface.settings ||
          _Surface.settingsError =>
            MomentsSettingsPage(repository: repository),
          _Surface.privacyEmpty ||
          _Surface.privacyFilled =>
            MomentsPrivacyListPage(
                repository: repository, kind: MomentsPrivacyKind.blockedViewer),
          _Surface.friendPicker => MomentsPrivacyFriendPicker(
              repository: repository,
              title: '选择朋友',
              initialSelectedIds: [momentsUiFriend.userId]),
        };
        final key = GlobalKey();
        Get.testMode = true;
        Styles.isDark = dark;
        addTearDown(() => Styles.isDark = false);
        addTearDown(Get.reset);
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(375, 812),
            builder: (_, __) => RepaintBoundary(
                key: key,
                child: GetMaterialApp(
                  debugShowCheckedModeBanner: false,
                  translations: TranslationService(),
                  locale: const Locale('zh', 'CN'),
                  supportedLocales: const [
                    Locale('zh', 'CN'),
                    Locale('en', 'US')
                  ],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: momentsUiTheme(dark,
                      fontFamily: 'MomentsSecondaryPreviewFont'),
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                          padding: const EdgeInsets.only(top: 24, bottom: 34)),
                      child: child!),
                  home: const SizedBox.shrink(),
                  initialRoute: '/secondary-preview',
                  routes: {'/secondary-preview': (_) => page},
                ))));
        await tester.pumpAndSettle();
        if (surface == _Surface.friendPicker) {
          for (var attempt = 0;
              attempt < 100 && find.byType(AzListView).evaluate().isEmpty;
              attempt++) {
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)));
            await tester.pump();
          }
          expect(find.byType(AzListView), findsOneWidget);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final output =
                File('docs/previews/moments-optimized-${surface.name}-'
                    '${dark ? 'dark' : 'light'}.png');
            await output.parent.create(recursive: true);
            await output.writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        PaintingBinding.instance.imageCache.clearLiveImages();
        PaintingBinding.instance.imageCache.clear();
        if (directory != null) {
          await tester.runAsync(() async {
            final target = directory!.absolute.path;
            if (!p.isWithin(Directory.systemTemp.absolute.path, target)) {
              throw StateError('Preview directory escaped the temporary root');
            }
            await directory!.delete(recursive: true);
          });
        }
      }, skip: !_exportPreview);
    }
  }
}
