import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/mine/settings/pages/edit_nickname_page.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim_common/openim_common.dart';

class _Service extends StubSettingsService {
  Object? error;
  String? submitted;
  @override
  bool get isProfileBackendAvailable => true;
  @override
  Future<void> updateNickname(String nickname) async {
    submitted = nickname;
    if (error != null) throw error!;
  }
}

class _CheckingService extends _Service {
  final names = <String>[];
  final requests = <Completer<NicknameCheckResult>>[];
  @override
  bool get supportsNicknameCheck => true;
  @override
  Future<NicknameCheckResult> checkNickname(String nickname) {
    names.add(nickname);
    final request = Completer<NicknameCheckResult>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  testWidgets(
      'live check debounces original text, ignores stale results and retries',
      (tester) async {
    final store = SettingsDraftStore()..setProfileNickname('原昵称');
    final service = _CheckingService();
    addTearDown(store.dispose);
    addTearDown(Get.reset);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: EditNicknamePage(
            initialNickname: '原昵称', service: service, store: store),
      ),
    ));
    expect(service.names, ['原昵称']);
    service.requests[0].complete(NicknameCheckResult(
        occupied: false,
        nextUpdateTime: DateTime(2030, 1, 2, 3, 4, 5).millisecondsSinceEpoch));
    await tester.pumpAndSettle();
    expect(find.textContaining('2030-01-02 03:04:05'), findsOneWidget);
    expect(find.text('昵称未被占用'), findsNothing);
    await tester.enterText(find.byType(TextField), ' Old ');
    await tester.pump(const Duration(milliseconds: 349));
    expect(service.names.length, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(service.names.last, ' Old ');
    await tester.enterText(find.byType(TextField), ' New ');
    await tester.pump(const Duration(milliseconds: 350));
    service.requests[2].complete(
        const NicknameCheckResult(occupied: false, nextUpdateTime: 0));
    await tester.pumpAndSettle();
    service.requests[1]
        .complete(const NicknameCheckResult(occupied: true, nextUpdateTime: 0));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('昵称已被占用，请换一个昵称'), findsNothing);
    await tester.enterText(find.byType(TextField), 'taken');
    await tester.pump(const Duration(milliseconds: 350));
    service.requests[3]
        .complete(const NicknameCheckResult(occupied: true, nextUpdateTime: 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    expect(service.submitted, isNull);
    await tester.enterText(find.byType(TextField), 'retry');
    await tester.pump(const Duration(milliseconds: 350));
    service.requests[4].completeError(StateError('network'));
    await tester.pumpAndSettle();
    expect(find.text('重新检查'), findsOneWidget);
    await tester.tap(find.text('重新检查'));
    service.requests[5].complete(
        const NicknameCheckResult(occupied: false, nextUpdateTime: 0));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(service.names.last, 'retry');
    service.requests[6].complete(NicknameCheckResult(
        occupied: false,
        nextUpdateTime: DateTime.now().millisecondsSinceEpoch + 500));
    await tester.pump();
    expect(find.textContaining('下次可修改时间：'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(service.requests.length, 8);
    service.requests[7].complete(
        const NicknameCheckResult(occupied: false, nextUpdateTime: 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('下次可修改时间：'), findsNothing);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(service.submitted, 'retry');
    expect(store.profileNickname, 'retry');
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  final cases = <Object, String>{
    (20018, 'NicknameAlreadyUsed'): '昵称已被占用，请换一个昵称',
    (20019, 'NicknameUpdateTooFrequent'): '7天内只能修改一次昵称，请稍后再试',
    (1001, 'nickname can not be empty'): '昵称不能为空',
    (1001, 'Nickname rejected by server'): 'Nickname rejected by server',
    (
      1001,
      'Error: json: cannot unmarshal object into Go value of type string /tmp/server/stack'
    ): '服务器处理失败，请稍后重试（错误码：1001）',
  };
  for (final entry in cases.entries) {
    testWidgets('nickname failure preserves input and shows ${entry.key}',
        (tester) async {
      final store = SettingsDraftStore()..setProfileNickname('原昵称');
      final service = _Service()..error = entry.key;
      addTearDown(store.dispose);
      addTearDown(() async {
        await EasyLoading.dismiss(animation: false);
        Get.reset();
      });
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: EasyLoading.init(),
          home: EditNicknamePage(
              initialNickname: '原昵称', service: service, store: store),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '秋啦啦啦啦');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(service.submitted, '秋啦啦啦啦');
      expect(store.profileNickname, '原昵称');
      expect(find.text('秋啦啦啦啦'), findsOneWidget);
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('保存失败，请稍后重试'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      // A failed request must leave the editor usable for a successful retry.
      service.error = null;
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(store.profileNickname, '秋啦啦啦啦');
    });
  }
}
