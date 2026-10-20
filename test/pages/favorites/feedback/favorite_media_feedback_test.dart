import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/favorites/feedback/favorite_media_feedback.dart';
import 'package:openim/pages/favorites/feedback/favorite_media_progress.dart';
import 'package:openim/pages/mine/secondary/favorites_page.dart';
import 'package:openim/services/favorite_repository.dart';

import '../support/favorite_ui_test_support.dart';

void main() {
  for (final locale in [const Locale('en'), const Locale('zh', 'TW')]) {
    testWidgets('media hints and errors follow $locale', (tester) async {
      await tester.pumpWidget(favoriteUiHost(Builder(
        builder: (context) => Localizations.override(
          context: context,
          locale: locale,
          child: Builder(
              builder: (context) => Scaffold(
                    body: Column(children: [
                      Text(FavoriteMediaFeedback.limitHint(
                          context, FavoriteKind.video)),
                      Text(FavoriteMediaFeedback.failureMessage(
                          context, const FavoriteApiException(20059, 'raw'),
                          kind: FavoriteKind.video)),
                      const FavoriteMediaProgress(progress: 0.5),
                    ]),
                  )),
        ),
      )));
      await tester.pump();
      expect(find.textContaining('100 MiB'), findsOneWidget);
      expect(
          find.textContaining(locale.languageCode == 'en'
              ? 'Uploading original 50%'
              : '正在上傳原始檔案 50%'),
          findsOneWidget);
      expect(
          find.textContaining(
              locale.languageCode == 'en' ? 'Convert it to MP4' : '請轉換為 MP4'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final dark in [false, true]) {
    testWidgets('creation sheet exposes media limits at large text, dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FavoriteUiRepository();
      addTearDown(repo.dispose);
      await tester.pumpWidget(favoriteUiHost(FavoritesPage(repository: repo),
          dark: dark, textScale: 2));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('favorites-add-fab')));
      await tester.pumpAndSettle();
      expect(find.textContaining('H.264'), findsOneWidget);
      expect(find.textContaining('100 MiB'), findsNWidgets(2));
      expect(find.textContaining('20 MiB'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsNothing);
    });
  }

  testWidgets('processing after upload is not shown as saved', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(favoriteUiHost(
        const Scaffold(body: FavoriteMediaProgress(progress: 1)),
        dark: true,
        textScale: 2));
    await tester.pump();
    expect(find.textContaining('正在校验并保存'), findsOneWidget);
    expect(find.textContaining('暂未收藏成功'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        isNull);
    expect(find.bySemanticsLabel(RegExp('.*正在校验并保存.*')), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
      'errors explain recovery without pretending to know codec or timeout',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(favoriteUiHost(Builder(builder: (value) {
      context = value;
      return const Scaffold();
    })));
    String message(Object error) =>
        FavoriteMediaFeedback.failureMessage(context, error,
            kind: FavoriteKind.video);
    expect(
        message(const FavoriteApiException(20058, 'raw')), contains('100 MiB'));
    expect(
        message(const FavoriteApiException(20058, 'raw')), contains('24 小时'));
    final invalid =
        message(const FavoriteApiException(20059, 'private/url?token=secret'));
    expect(invalid, contains('H.264'));
    expect(invalid, contains('封面处理'));
    expect(invalid, isNot(contains('超时')));
    expect(invalid, isNot(contains('secret')));
    expect(message(const FavoriteApiException(20060, 'raw')), contains('删除'));
    expect(message(const FavoriteApiException(20065, 'raw')), contains('一分钟'));
    expect(
        message(const FavoriteApiException('NETWORK_ERROR', 'raw',
            isUncertain: true)),
        contains('避免重复添加'));
    expect(
        message(const FavoriteApiException('UPLOAD_FAILED', 'raw',
            isUncertain: true)),
        contains('检查网络'));
  });

  testWidgets(
      'failure stays readable until dismissed; cancellation stays silent',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(favoriteUiHost(Builder(builder: (value) {
      context = value;
      return const Scaffold();
    }), dark: true, textScale: 2));
    final shown = FavoriteMediaFeedback.showFailure(
        context, const FavoriteApiException(20059, 'raw'),
        kind: FavoriteKind.video);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.textContaining('H.264'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await shown;
    await FavoriteMediaFeedback.showFailure(
        context, const FavoriteApiException('CANCELLED', '', isCancelled: true),
        kind: FavoriteKind.video);
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  });
}
