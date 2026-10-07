import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/chat/group_setup/edit_name/edit_name_logic.dart';
import 'package:openim/pages/chat/group_setup/edit_name/edit_name_view.dart';
import 'package:openim/pages/chat/group_setup/group_setup_logic.dart';
import 'package:openim/pages/contacts/user_profile_panel/set_remark/set_remark_view.dart';
import 'package:openim_common/openim_common.dart';

const _sdk = MethodChannel('flutter_openim_sdk');
const _groupID = 'group-save-test';
const _viewerID = 'im_viewer';

class _IM extends GetxController implements IMController {
  @override
  final userInfo = UserFullInfo(userID: _viewerID, nickname: '我').obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GroupSetup extends GetxController implements GroupSetupLogic {
  _GroupSetup({String name = '测试群聊', String? memberName = '我的群昵称'}) {
    groupInfo = GroupInfo(groupID: _groupID, groupName: name).obs;
    myGroupMembersInfo = GroupMembersInfo(
      groupID: _groupID,
      userID: _viewerID,
      nickname: memberName,
    ).obs;
  }

  @override
  late Rx<GroupInfo> groupInfo;

  @override
  late Rx<GroupMembersInfo> myGroupMembersInfo;

  @override
  final IMController imLogic = _IM();

  @override
  String? get myGroupNickname {
    final name = myGroupMembersInfo.value.nickname?.trim();
    return name == null ||
            name.isEmpty ||
            name == imLogic.userInfo.value.nickname
        ? null
        : name;
  }

  int avatarChanges = 0;

  @override
  void modifyGroupAvatar() {
    avatarChanges++;
    groupInfo.update((group) => group!.faceURL = 'updated-avatar');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<EditGroupNameLogic> _open(
  WidgetTester tester, {
  _GroupSetup? setup,
  EditNameType type = EditNameType.groupNickname,
  bool dark = false,
  bool nestedParent = false,
}) async {
  Styles.isDark = dark;
  Get.put<GroupSetupLogic>(setup ?? _GroupSetup());
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      locale: const Locale('zh', 'CN'),
      translations: TranslationService(),
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: EasyLoading.init(),
      home: Scaffold(body: Text(nestedParent ? 'root' : 'origin')),
      getPages: [
        GetPage(
          name: '/parent',
          page: () => const Scaffold(body: Text('origin')),
        ),
        GetPage(
          name: '/edit-name',
          binding: BindingsBuilder(() {
            Get.put<EditGroupNameLogic>(EditGroupNameLogic());
          }),
          page: EditGroupNamePage.new,
        ),
        GetPage(
          name: '/another',
          page: () => const Scaffold(body: Text('another page')),
        ),
      ],
    ),
  ));
  if (nestedParent) {
    Get.toNamed<void>('/parent');
    await tester.pumpAndSettle();
  }
  Get.toNamed<void>('/edit-name', arguments: {'type': type});
  await tester.pumpAndSettle();
  addTearDown(() async {
    await LoadingView.singleton.dismiss();
    await EasyLoading.dismiss(animation: false);
    await tester.pumpWidget(const SizedBox());
    Get.reset();
    Styles.isDark = false;
  });
  return Get.find<EditGroupNameLogic>();
}

Future<void> _startRequest(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 3));
  await tester.pump();
  await tester.pump();
}

Future<void> _finishRequest(
  WidgetTester tester,
  Completer<void> gate,
  Future<void> pending,
) async {
  await tester.runAsync(() async {
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await tester.pumpAndSettle();
  await pending;
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  late Completer<void> gate;
  var reject = false;

  setUp(() {
    Get.reset();
    Get.testMode = true;
    OpenIM.iMManager.userID = _viewerID;
    calls = [];
    gate = Completer<void>();
    reject = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdk, (call) async {
      if (call.method != 'setGroupInfo' &&
          call.method != 'setGroupMemberInfo') {
        throw StateError('Unexpected native method: ${call.method}');
      }
      calls.add(call);
      await gate.future;
      if (reject) throw PlatformException(code: 'save_rejected');
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdk, null);
  });

  for (final dark in [false, true]) {
    for (final memberName in ['我', '', null]) {
      testWidgets(
          'member nickname uses its original default as a placeholder ($memberName, dark=$dark)',
          (tester) async {
        final logic = await _open(tester,
            setup: _GroupSetup(memberName: memberName),
            type: EditNameType.myGroupMemberNickname,
            dark: dark);
        final field = find.byType(TextField);
        expect(logic.inputCtrl.text, isEmpty);
        final input = tester.widget<TextField>(field);
        expect(input.controller!.text, isEmpty);
        expect(input.decoration!.hintText, '我');
        expect(find.text('0/30'), findsOneWidget);
        expect(tester.testTextInput.isVisible, isFalse);
        await tester.tap(field);
        await tester.pump();
        expect(tester.testTextInput.isVisible, isTrue);
        expect(input.controller!.selection.isValid, isTrue);
        await logic.save();
        await tester.pumpAndSettle();
        expect(calls, isEmpty);
        expect(find.text('origin'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('avatar-only save does not rename the group (dark=$dark)',
        (tester) async {
      final setup = _GroupSetup();
      await _open(tester, setup: setup, dark: dark);
      await tester.tap(find.byType(AvatarView));
      await tester.pump();
      expect(setup.avatarChanges, 1);
      expect(tester.widget<AvatarView>(find.byType(AvatarView)).url,
          'updated-avatar');
      await tester.tap(find.text(StrRes.determine));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text('origin'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unchanged group name closes without writing', (tester) async {
    final logic = await _open(tester, nestedParent: true);
    await logic.save();
    await logic.save();
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.text('origin'), findsOneWidget);
  });

  testWidgets('reverting the draft and whitespace remain unchanged',
      (tester) async {
    final logic = await _open(tester, setup: _GroupSetup(name: ' 测试群聊 '));
    await tester.enterText(find.byType(TextField), '新群名');
    await tester.enterText(find.byType(TextField), '  测试群聊  ');
    await logic.save();
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.text('origin'), findsOneWidget);
  });

  testWidgets('an external name update is not overwritten by unchanged draft',
      (tester) async {
    final setup = _GroupSetup();
    final logic = await _open(tester, setup: setup);
    setup.groupInfo.update((group) => group!.groupName = '其他成员修改后的群名');
    await tester.pump();
    expect(logic.inputCtrl.text, '测试群聊');
    await logic.save();
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(setup.groupInfo.value.groupName, '其他成员修改后的群名');
  });

  testWidgets('an actual rename sends only the changed name and group ID',
      (tester) async {
    final logic = await _open(tester);
    await tester.enterText(find.byType(TextField), '  新群名  ');
    final pending = logic.save();
    await _startRequest(tester);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'setGroupInfo');
    expect((calls.single.arguments as Map)['groupInfo'],
        {'groupID': _groupID, 'groupName': '新群名'});
    await _finishRequest(tester, gate, pending);
    expect(find.text('origin'), findsOneWidget);
  });

  testWidgets('same member nickname does not send a member update',
      (tester) async {
    final logic = await _open(tester, type: EditNameType.myGroupMemberNickname);
    await logic.save();
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.text('origin'), findsOneWidget);
  });

  testWidgets('changed member nickname updates the current member only',
      (tester) async {
    final logic = await _open(tester, type: EditNameType.myGroupMemberNickname);
    await tester.enterText(find.byType(TextField), ' 新昵称 ');
    final pending = logic.save();
    await _startRequest(tester);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'setGroupMemberInfo');
    expect((calls.single.arguments as Map)['info'],
        {'groupID': _groupID, 'userID': _viewerID, 'nickname': '新昵称'});
    await _finishRequest(tester, gate, pending);
    expect(find.text('origin'), findsOneWidget);
  });

  testWidgets(
      'prefilled personal nickname remains editable as a group nickname',
      (tester) async {
    final logic = await _open(tester,
        setup: _GroupSetup(memberName: null),
        type: EditNameType.myGroupMemberNickname);
    expect(logic.inputCtrl.text, isEmpty);
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '群里使用的昵称');
    final pending = logic.save();
    await _startRequest(tester);
    expect(calls, hasLength(1));
    expect((calls.single.arguments as Map)['info'], {
      'groupID': _groupID,
      'userID': _viewerID,
      'nickname': '群里使用的昵称',
    });
    await _finishRequest(tester, gate, pending);
    expect(find.text('origin'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'existing group nickname supports append and middle edits ($dark)',
        (tester) async {
      final logic = await _open(tester,
          type: EditNameType.myGroupMemberNickname, dark: dark);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '我的群昵称');
      await tester.tap(find.byType(TextField));
      await tester.pump();
      field.controller!.selection =
          TextSelection.collapsed(offset: field.controller!.text.length);
      tester.testTextInput.enterText('我的群昵称追加');
      await tester.pump();
      expect(logic.inputCtrl.text, '我的群昵称追加');
      field.controller!.selection = const TextSelection.collapsed(offset: 2);
      tester.testTextInput.updateEditingValue(const TextEditingValue(
          text: '我的新群昵称追加', selection: TextSelection.collapsed(offset: 3)));
      await tester.pump();
      expect(logic.inputCtrl.text, '我的新群昵称追加');
      final pending = logic.save();
      await _startRequest(tester);
      expect(((calls.single.arguments as Map)['info'] as Map)['nickname'],
          '我的新群昵称追加');
      await _finishRequest(tester, gate, pending);
    });
  }

  testWidgets('saving gates repeat submissions and locks the editor',
      (tester) async {
    final logic = await _open(tester);
    await tester.enterText(find.byType(TextField), '新群名');
    final pending = logic.save();
    final duplicate = logic.save();
    await _startRequest(tester);
    await duplicate;
    expect(calls, hasLength(1));
    final editor = tester.widget<SetFriendRemarkPage>(
      find.byType(SetFriendRemarkPage),
    );
    expect(editor.saving, isTrue);
    expect(editor.onAvatarTap, isNull);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    await _finishRequest(tester, gate, pending);
  });

  testWidgets('a failed save stays editable and can be retried once',
      (tester) async {
    final logic = await _open(tester);
    await tester.enterText(find.byType(TextField), '新群名');
    reject = true;
    final pending = logic.save();
    await _startRequest(tester);
    await _finishRequest(tester, gate, pending);
    expect(calls, hasLength(1));
    expect(find.byType(EditGroupNamePage), findsOneWidget);
    expect(logic.inputCtrl.text, '新群名');
    expect(logic.saving.value, isFalse);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(
        tester
            .widget<SetFriendRemarkPage>(
              find.byType(SetFriendRemarkPage),
            )
            .onAvatarTap,
        isNotNull);
    reject = false;
    gate = Completer<void>();
    final retry = logic.save();
    await _startRequest(tester);
    expect(calls, hasLength(2));
    await _finishRequest(tester, gate, retry);
    expect(find.text('origin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late completion after disposal does not pop a new page',
      (tester) async {
    final logic = await _open(tester);
    await tester.enterText(find.byType(TextField), '新群名');
    final pending = logic.save();
    await _startRequest(tester);
    await LoadingView.singleton.dismiss();
    Get.offNamed<void>('/another');
    await tester.pumpAndSettle();
    expect(logic.isClosed, isTrue);
    expect(find.text('another page'), findsOneWidget);
    await _finishRequest(tester, gate, pending);
    expect(calls, hasLength(1));
    expect(find.text('another page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
