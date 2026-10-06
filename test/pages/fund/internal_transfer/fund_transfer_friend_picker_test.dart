import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/fund/internal_transfer/presentation/fund_transfer_friend_picker.dart';
import 'package:openim/pages/fund/internal_transfer/data/fund_transfer_recipient_source.dart';
import 'package:openim_common/openim_common.dart';

ISUserInfo friend(String id, String name,
        {String account = '', bool blocked = false, String? ex}) =>
    ISUserInfo.fromJson({
      'userID': id,
      'nickname': name,
      'account': account,
      'isBlacklist': blocked,
      if (ex != null) 'ex': ex,
    });

Future<GlobalKey<NavigatorState>> openPicker(
  WidgetTester tester,
  FundTransferFriendsLoader loader, {
  String Function()? owner,
  String? Function()? token,
  String Function()? server,
  FundTransferFriendAccountLoader? accountLoader,
  ValueChanged<FundTransferRecipient?>? onSelected,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('zh', 'CN'),
  double textScale = 1,
  EdgeInsets keyboard = EdgeInsets.zero,
  GlobalKey? boundaryKey,
  String? fontFamily,
}) async {
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      locale: locale,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(brightness: brightness, fontFamily: fontFamily),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: keyboard,
        ),
        child: boundaryKey == null
            ? child!
            : RepaintBoundary(key: boundaryKey, child: child!),
      ),
      navigatorKey: nav,
      home: const Scaffold(),
    ),
  ));
  nav.currentState!
      .push<FundTransferRecipient>(MaterialPageRoute(
        builder: (_) => FundTransferFriendPicker(
          friendsLoader: loader,
          ownerProvider: owner ?? () => 'me',
          tokenProvider: token ?? () => 'token',
          serverProvider: server ?? () => 'https://chat.example.test',
          accountLoader: accountLoader ?? (_) async => null,
        ),
      ))
      .then((value) => onSelected?.call(value));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  return nav;
}

Finder friendRow(String id) => find.byKey(ValueKey('fund-transfer-friend-$id'));

void main() {
  setUp(() {
    Get.testMode = true;
    Get.locale = const Locale('zh', 'CN');
  });
  tearDown(Get.reset);

  testWidgets('only unique eligible friends return their actual IM user ID',
      (tester) async {
    FundTransferRecipient? result;
    await openPicker(
      tester,
      (_, __) async => [
        friend('me', '自己'),
        friend('im_real_a', '小林', account: 'public-lin'),
        friend('im_real_a', '重复好友'),
        friend('', '无效好友'),
        friend('blocked', '已拉黑', blocked: true),
        friend('im_real_b', '阿明'),
      ],
      onSelected: (value) => result = value,
    );
    expect(find.text('选择收款人'), findsOneWidget);
    expect(friendRow('im_real_a'), findsOneWidget);
    expect(friendRow('im_real_b'), findsOneWidget);
    for (final name in ['自己', '重复好友', '无效好友', '已拉黑']) {
      expect(find.text(name), findsNothing);
    }
    expect(find.byType(AvatarView), findsNWidgets(2));
    await tester.tap(friendRow('im_real_a'));
    await tester.pumpAndSettle();
    expect(result?.userID, 'im_real_a');
    expect(result?.nickname, '小林');
    expect(result?.account, 'public-lin');
  });

  testWidgets('name and public account searches filter the loaded friends only',
      (tester) async {
    var calls = 0;
    await openPicker(tester, (_, __) async {
      calls++;
      return [
        friend('opaque-id-a', '小林', account: 'public-lin'),
        friend('opaque-id-b', '阿明', account: 'public-ming'),
      ];
    });
    for (final query in ['小林', '@PUBLIC-LIN']) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump();
      expect(friendRow('opaque-id-a'), findsOneWidget);
      expect(friendRow('opaque-id-b'), findsNothing);
    }
    await tester.enterText(find.byType(TextField), 'opaque-id-a');
    await tester.pump();
    expect(find.text('未找到相关好友'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(friendRow('opaque-id-b'), findsOneWidget);
    expect(calls, 1);
  });

  testWidgets('official services are absent from the list and local searches',
      (tester) async {
    await openPicker(
        tester,
        (_, __) async => [
              friend('99Message', '99Message', account: 'official-message'),
              friend('99Pay', '99Pay', account: 'official-pay'),
              friend('assistant', 'AI助理', account: 'official-assistant'),
              friend('custom-official', '官方服务',
                  account: 'official-custom', ex: '{"accountType":"official"}'),
              friend('personal', '秋啊', account: 'personal-qiu'),
            ]);
    expect(friendRow('personal'), findsOneWidget);
    for (final id in ['99Message', '99Pay', 'assistant', 'custom-official']) {
      expect(friendRow(id), findsNothing);
    }
    for (final query in ['99Message', '99Pay', 'AI助理', '@official-custom']) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump();
      expect(find.byType(ListTile), findsNothing);
      expect(find.text('未找到相关好友'), findsOneWidget);
    }
    await tester.enterText(find.byType(TextField), '秋啊');
    await tester.pump();
    expect(friendRow('personal'), findsOneWidget);
  });

  for (final name in ['99Message', '99Pay', 'AI助理', 'assistant']) {
    testWidgets('a personal friend named $name can still be selected',
        (tester) async {
      FundTransferRecipient? result;
      await openPicker(
        tester,
        (_, __) async => [
          friend('personal-id', name, account: 'personal-account'),
          friend('99Pay', '改名后的官方账号'),
        ],
        onSelected: (value) => result = value,
      );
      await tester.enterText(find.byType(TextField), name);
      await tester.pump();
      expect(friendRow('personal-id'), findsOneWidget);
      expect(friendRow('99Pay'), findsNothing);
      await tester.tap(friendRow('personal-id'));
      await tester.pumpAndSettle();
      expect(result?.userID, 'personal-id');
      expect(result?.nickname, name);
    });
  }

  testWidgets('loads every SDK page with raw offsets before local filtering',
      (tester) async {
    final offsets = <int>[];
    await openPicker(tester, (offset, count) async {
      offsets.add(offset);
      expect(count, 50);
      return offset == 0
          ? [for (var i = 0; i < 50; i++) friend('u$i', '好友$i')]
          : [friend('u0', '重复末页'), friend('last', '末页好友')];
    });
    await tester.enterText(find.byType(TextField), '末页');
    await tester.pumpAndSettle();
    expect(offsets, [0, 50]);
    expect(find.text('重复末页'), findsNothing);
    expect(friendRow('last'), findsOneWidget);
  });

  testWidgets('failed loading offers one retry and keeps private errors hidden',
      (tester) async {
    var attempts = 0;
    await openPicker(tester, (_, __) async {
      if (++attempts == 1) throw StateError('private backend error');
      return [friend('real', '恢复好友')];
    });
    expect(find.text('private backend error'), findsNothing);
    final retry = tester.widget<TextButton>(
        find.byKey(const ValueKey('fund-transfer-friend-retry')));
    expect(find.text('好友加载失败，请重试'), findsOneWidget);
    retry.onPressed!();
    retry.onPressed!();
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(friendRow('real'), findsOneWidget);
  });

  for (final changedField in ['owner', 'token', 'server']) {
    testWidgets('$changedField changes discard a late friend page',
        (tester) async {
      var owner = 'me';
      String? token = 'token';
      var server = 'https://chat.example.test';
      final pending = Completer<List<ISUserInfo>>();
      var requests = 0;
      await openPicker(tester, (_, __) {
        requests++;
        return pending.future;
      }, owner: () => owner, token: () => token, server: () => server);
      switch (changedField) {
        case 'owner':
          owner = 'other';
        case 'token':
          token = null;
        case 'server':
          server = 'https://another-chat.example.test';
      }
      pending.complete([friend('old', '旧账户好友')]);
      await tester.pumpAndSettle();
      expect(friendRow('old'), findsNothing);
      expect(find.text('账户已切换，请重新打开'), findsOneWidget);
      expect(requests, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('missing account is enriched without changing the receiver ID',
      (tester) async {
    FundTransferRecipient? result;
    final requests = <String>[];
    await openPicker(
      tester,
      (_, __) async => [friend('real_im_id', '阿明')],
      accountLoader: (id) async {
        requests.add(id);
        return 'aming-public';
      },
      onSelected: (value) => result = value,
    );
    await tester.tap(friendRow('real_im_id'));
    await tester.pumpAndSettle();
    expect(requests, ['real_im_id']);
    expect(result?.userID, 'real_im_id');
    expect(result?.account, 'aming-public');
  });

  testWidgets('optional profile failure still selects the actual friend',
      (tester) async {
    FundTransferRecipient? result;
    await openPicker(
      tester,
      (_, __) async => [friend('real_im_id', '阿明')],
      accountLoader: (_) async => throw StateError('offline'),
      onSelected: (value) => result = value,
    );
    await tester.tap(friendRow('real_im_id'));
    await tester.pumpAndSettle();
    expect(result?.userID, 'real_im_id');
    expect(result?.account, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session switch during profile lookup cannot return a recipient',
      (tester) async {
    var server = 'https://chat.example.test';
    final pending = Completer<String?>();
    FundTransferRecipient? result;
    await openPicker(
      tester,
      (_, __) async => [friend('real_im_id', '阿明')],
      server: () => server,
      accountLoader: (_) => pending.future,
      onSelected: (value) => result = value,
    );
    final row = tester.widget<ListTile>(friendRow('real_im_id'));
    row.onTap!();
    row.onTap!();
    server = 'https://another.example.test';
    pending.complete('old-public-account');
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.byType(FundTransferFriendPicker), findsOneWidget);
    expect(find.text('账户已切换，请重新打开'), findsOneWidget);
    expect(friendRow('real_im_id'), findsNothing);
  });

  testWidgets('disposed picker ignores a pending friend response',
      (tester) async {
    final pending = Completer<List<ISUserInfo>>();
    final nav = await openPicker(tester, (_, __) => pending.future);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    pending.complete([friend('late', '晚返回好友')]);
    await tester.pumpAndSettle();
    expect(find.byType(FundTransferFriendPicker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('$brightness supports narrow layout and large English text',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 740);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await openPicker(
        tester,
        (_, __) async => [
          friend('real', 'A very long recipient display name',
              account: 'long-public-account'),
        ],
        brightness: brightness,
        locale: const Locale('en', 'US'),
        textScale: 2,
      );
      expect(find.text('Select recipient'), findsOneWidget);
      expect(friendRow('real'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
