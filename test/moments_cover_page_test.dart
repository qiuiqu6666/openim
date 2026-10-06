import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/moments_cover_page.dart';
import 'package:openim/services/moments_repository.dart';

class _PickedFile implements File {
  _PickedFile({this.size = 100});
  final int size;
  Uint8List? replacementBytes;
  bool unreadable = false;
  @override
  final String path = '/selected-cover.png';
  @override
  Future<int> length() async => size;
  @override
  Future<Uint8List> readAsBytes() async {
    if (unreadable) throw const FileSystemException('Unavailable image');
    return replacementBytes ??
        base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a/q8AAAAASUVORK5CYII=');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api extends MomentsApi {
  _Api() : super(baseUrl: 'https://moments.example');
  bool available = true;
  bool unknownUpload = false;
  bool unknownSetting = false;
  bool commitBeforeTimeout = false;
  bool conflict = false;
  bool mediaNotReady = false;
  Object? settingsError;
  String mediaState = 'READY';
  final mediaIds = <String>[];
  final filePaths = <String>[];
  final writes = <Map<String, dynamic>>[];
  int statusCalls = 0;
  MomentsSettings current = const MomentsSettings(version: 7);
  Completer<MomentsSettings>? settingGate;
  @override
  Future<MomentsCapabilities> capabilities() async {
    if (!available) {
      throw const MomentsException('not ready', unavailable: true);
    }
    return const MomentsCapabilities(enabled: true, settingsEnabled: true);
  }

  @override
  Future<MomentsSettings> settings() async {
    if (settingsError != null) throw settingsError!;
    return current;
  }

  @override
  Future<MomentMedia> uploadCover(
      {required String filePath,
      required String clientMediaId,
      String? fileName,
      ProgressCallback? onProgress,
      CancelToken? cancelToken}) async {
    mediaIds.add(clientMediaId);
    filePaths.add(filePath);
    if (unknownUpload) {
      throw const MomentsException('upload timeout', unknownResult: true);
    }
    return MomentMedia(mediaId: 'uploaded-cover', status: mediaState);
  }

  @override
  Future<MomentMedia> mediaStatus(String mediaId) async {
    statusCalls++;
    throw const MomentsException('No media-status contract', unavailable: true);
  }

  @override
  Future<MomentsSettings> updateSettings(
      {int? visibleRangeDays,
      String? coverMediaId,
      bool clearCover = false,
      required int expectedVersion}) async {
    writes.add({
      'coverMediaId': coverMediaId,
      'clearCover': clearCover,
      'expectedVersion': expectedVersion
    });
    if (settingGate != null) return settingGate!.future;
    if (mediaNotReady) {
      throw const MomentsException('not ready', code: 'MEDIA_NOT_READY');
    }
    if (conflict) {
      throw const MomentsException('version conflict',
          code: 'VERSION_CONFLICT', statusCode: 409);
    }
    if (!unknownSetting || commitBeforeTimeout) {
      current = MomentsSettings(
          version: expectedVersion + 1,
          coverMediaId: clearCover ? null : coverMediaId);
    }
    if (unknownSetting) {
      throw const MomentsException('settings timeout', unknownResult: true);
    }
    return current;
  }
}

Future<void> _open(WidgetTester tester, MomentsRepository repository,
    {File? file,
    bool dark = false,
    String language = 'zh',
    double scale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(375, 812);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
            locale: Locale(language),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => MomentsCoverPage(
                                    repository: repository,
                                    pickImage: (_) async =>
                                        file ?? _PickedFile()))),
                        child: const Text('open')))),
          )));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('moments_cover_pick')));
  await tester.tap(find.byKey(const ValueKey('moments_cover_pick')));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('moments_cover_save')));
  await tester.tap(find.byKey(const ValueKey('moments_cover_save')));
  await tester.pumpAndSettle();
}

void main() {
  late _Api api;
  late MomentsRepository repository;
  var owner = 'me';
  var environment = 'https://moments.example';
  setUp(() {
    api = _Api();
    owner = 'me';
    environment = 'https://moments.example';
    repository = MomentsRepository(
        api: api,
        subscribeToSdk: false,
        userIdProvider: () => owner,
        environmentProvider: () => environment,
        friendLoader: () async => const []);
  });
  tearDown(() => repository.dispose());
  testWidgets('selected cover uploads once and saves the current version',
      (tester) async {
    await _open(tester, repository);
    await _pick(tester);
    expect(find.byKey(const ValueKey('moments_cover_preview')), findsOneWidget);
    await _save(tester);
    expect(api.mediaIds, hasLength(1));
    expect(api.writes.single, {
      'coverMediaId': 'uploaded-cover',
      'clearCover': false,
      'expectedVersion': 7
    });
    expect(find.text('open'), findsOneWidget);
  });
  testWidgets(
      'processing cover keeps its media ID and retries binding without a status endpoint',
      (tester) async {
    api.mediaState = 'PROCESSING';
    await _open(tester, repository);
    await _pick(tester);
    await _save(tester);
    expect(api.statusCalls, 0);
    expect(api.mediaIds, hasLength(1));
    expect(api.writes, isEmpty);
    expect(find.text('封面仍在处理中，请稍后再次保存'), findsOneWidget);
    api.mediaNotReady = true;
    await _save(tester);
    expect(api.statusCalls, 0);
    expect(api.mediaIds, hasLength(1));
    expect(api.writes.single['coverMediaId'], 'uploaded-cover');
    expect(find.text('封面仍在处理中，请稍后再次保存'), findsOneWidget);
    api.mediaNotReady = false;
    await _save(tester);
    expect(api.mediaIds, hasLength(1));
    expect(api.statusCalls, 0);
    expect(api.writes, hasLength(2));
    expect(api.writes.last, api.writes.first);
    expect(find.text('open'), findsOneWidget);
  });
  testWidgets(
      'uncertain upload freezes selection and retries the same media ID',
      (tester) async {
    api.unknownUpload = true;
    await _open(tester, repository);
    await _pick(tester);
    await _save(tester);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('moments_cover_pick')))
            .onPressed,
        isNull);
    expect(api.writes, isEmpty);
    api.unknownUpload = false;
    await _save(tester);
    expect(api.mediaIds, hasLength(2));
    expect(api.mediaIds.first, api.mediaIds.last);
    expect(api.filePaths.first, api.filePaths.last);
    expect(api.writes, hasLength(1));
  });
  testWidgets('a changed file never reuses an uncertain upload ID',
      (tester) async {
    final file = _PickedFile();
    api.unknownUpload = true;
    await _open(tester, repository, file: file);
    await _pick(tester);
    await _save(tester);
    file.replacementBytes = Uint8List.fromList([1, 2, 3]);
    api.unknownUpload = false;
    await _save(tester);
    expect(api.mediaIds, hasLength(1));
    expect(api.writes, isEmpty);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('moments_cover_pick')))
            .onPressed,
        isNull);
    expect(find.textContaining('所选图片内容已变化'), findsOneWidget);
    file.replacementBytes = null;
    await _save(tester);
    expect(api.mediaIds, hasLength(2));
    expect(api.mediaIds.first, api.mediaIds.last);
    expect(api.writes, hasLength(1));
  });
  testWidgets(
      'an unreadable file keeps an uncertain upload locked until restored',
      (tester) async {
    final file = _PickedFile();
    api.unknownUpload = true;
    await _open(tester, repository, file: file);
    await _pick(tester);
    await _save(tester);
    file.unreadable = true;
    api.unknownUpload = false;
    await _save(tester);
    expect(api.mediaIds, hasLength(1));
    expect(api.writes, isEmpty);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('moments_cover_pick')))
            .onPressed,
        isNull);
    expect(find.text('确认保存结果'), findsOneWidget);
    file.unreadable = false;
    await _save(tester);
    expect(api.mediaIds, hasLength(2));
    expect(api.mediaIds.first, api.mediaIds.last);
    expect(api.writes, hasLength(1));
  });
  testWidgets('an unchanged settings read cannot replay an unknown cover write',
      (tester) async {
    api.unknownSetting = true;
    await _open(tester, repository);
    await _pick(tester);
    await _save(tester);
    await _save(tester);
    expect(api.writes, hasLength(1));
    expect(api.mediaIds, hasLength(1));
    expect(find.text('确认保存结果'), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('moments_cover_pick')))
            .onPressed,
        isNull);
    api.current =
        const MomentsSettings(version: 8, coverMediaId: 'uploaded-cover');
    await _save(tester);
    expect(api.writes, hasLength(1));
    expect(find.text('open'), findsOneWidget);
  });
  testWidgets(
      'already committed timeout reconciles with settings and never writes twice',
      (tester) async {
    api.unknownSetting = true;
    api.commitBeforeTimeout = true;
    await _open(tester, repository);
    await _pick(tester);
    await _save(tester);
    expect(find.text('确认保存结果'), findsOneWidget);
    await _save(tester);
    expect(api.writes, hasLength(1));
    expect(api.mediaIds, hasLength(1));
    expect(find.text('open'), findsOneWidget);
  });
  testWidgets(
      'failed confirmation read preserves unknown state and locked selection',
      (tester) async {
    api.unknownSetting = true;
    await _open(tester, repository);
    await _pick(tester);
    await _save(tester);
    api.settingsError = const MomentsException('read failed');
    await _save(tester);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('moments_cover_pick')))
            .onPressed,
        isNull);
    expect(find.text('确认保存结果'), findsOneWidget);
    expect(api.writes, hasLength(1));
    api.settingsError = null;
    api.current =
        const MomentsSettings(version: 8, coverMediaId: 'uploaded-cover');
    await _save(tester);
    expect(api.writes, hasLength(1));
    expect(find.text('open'), findsOneWidget);
  });
  testWidgets('version conflict requires refresh and an explicit second save',
      (tester) async {
    api.conflict = true;
    await _open(tester, repository);
    await _pick(tester);
    await _save(tester);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('moments_cover_save')))
            .onPressed,
        isNull);
    api.current = const MomentsSettings(version: 12);
    await tester.ensureVisible(
        find.byKey(const ValueKey('moments_cover_refresh_version')));
    await tester
        .tap(find.byKey(const ValueKey('moments_cover_refresh_version')));
    await tester.pumpAndSettle();
    expect(api.writes, hasLength(1));
    expect(find.text('已加载最新设置。所选图片仍保留，是否再次保存由你决定。'), findsOneWidget);
    api.conflict = false;
    await _save(tester);
    expect(api.writes.last['expectedVersion'], 12);
    expect(api.mediaIds, hasLength(1));
  });
  testWidgets(
      'newer conflicting cover found during confirmation is not overwritten automatically',
      (tester) async {
    api.unknownSetting = true;
    await _open(tester, repository);
    await _pick(tester);
    await _save(tester);
    api.current =
        const MomentsSettings(version: 11, coverMediaId: 'another-cover');
    await _save(tester);
    expect(api.writes, hasLength(1));
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('moments_cover_pick')))
            .onPressed,
        isNotNull);
    api.unknownSetting = false;
    await _save(tester);
    expect(api.writes.last['expectedVersion'], 11);
  });
  testWidgets(
      'uncertain default-cover reset also reconciles without duplicate writes',
      (tester) async {
    api.current = const MomentsSettings(
        version: 7, coverMediaId: 'old', coverUrl: '/old-cover');
    api.unknownSetting = true;
    api.commitBeforeTimeout = true;
    await _open(tester, repository);
    await tester
        .ensureVisible(find.byKey(const ValueKey('moments_cover_reset')));
    await tester.tap(find.byKey(const ValueKey('moments_cover_reset')));
    await tester.pumpAndSettle();
    expect(find.text('确认恢复结果'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('moments_cover_reset')));
    await tester.pumpAndSettle();
    expect(api.writes, hasLength(1));
    expect(find.text('open'), findsOneWidget);
  });
  testWidgets('oversized image reports size limits and never uploads',
      (tester) async {
    await _open(tester, repository, file: _PickedFile(size: 10485761));
    await _pick(tester);
    expect(find.text('图片超过上传大小限制，请选择较小的图片'), findsOneWidget);
    expect(find.byKey(const ValueKey('moments_cover_preview')), findsNothing);
    expect(api.mediaIds, isEmpty);
  });
  testWidgets(
      'failed media processing explains the failure and enables a different photo',
      (tester) async {
    api.mediaState = 'FAILED';
    await _open(tester, repository);
    await _pick(tester);
    await _save(tester);
    expect(find.text('封面处理失败，请选择其他图片。'), findsOneWidget);
    expect(api.writes, isEmpty);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('moments_cover_pick')))
            .onPressed,
        isNotNull);
  });
  testWidgets(
      'account and server switches hide preview immediately and ignore late writes',
      (tester) async {
    await _open(tester, repository);
    await _pick(tester);
    api.settingGate = Completer<MomentsSettings>();
    await tester.tap(find.byKey(const ValueKey('moments_cover_save')));
    await tester.pump();
    owner = 'other';
    environment = 'https://other.example';
    await repository.ensureCapabilities(force: true);
    await tester.pump();
    expect(find.byKey(const ValueKey('moments_cover_preview')), findsNothing);
    expect(find.text('登录状态已改变'), findsOneWidget);
    api.settingGate!.complete(
        const MomentsSettings(version: 8, coverMediaId: 'old-account-cover'));
    await tester.pumpAndSettle();
    expect(find.byType(MomentsCoverPage), findsOneWidget);
    expect(repository.settings, isNull);
  });
  testWidgets(
      'unavailable service has truthful English dark and light states with large text',
      (tester) async {
    api.available = false;
    await _open(tester, repository, dark: true, language: 'en', scale: 1.8);
    expect(find.text('Cover unavailable'), findsOneWidget);
    expect(find.text('Moments is not available yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await _open(tester, repository, language: 'en', scale: 1.8);
    tester.view.physicalSize = const Size(812, 375);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(api.mediaIds, isEmpty);
  });
}
