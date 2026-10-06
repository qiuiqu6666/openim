import 'dart:io';
import 'dart:ui' as ui;

import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim/pages/contacts/presence_store.dart';
import 'package:openim/pages/contacts/star_friend_store.dart';
import 'package:openim/pages/contacts/select_contacts/friend_list/friend_list_logic.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_view.dart';
import 'package:openim_common/openim_common.dart';

const contactCardPickerPreviewKey = ValueKey('contact-card-picker-preview');

// Keep the actual selection/confirmation behavior; only the SDK initialization
// and conversation lookup lifecycle are bypassed by this test fixture.
class _Selection extends SelectContactsLogic {
  _Selection() {
    action = SelAction.carte;
    openSelectedSheet = false;
    cardRecipientName = '当前聊天对象';
  }

  @override
  // The fixture supplies route arguments directly to avoid SDK initialization.
  // ignore: must_call_super
  void onInit() {}

  @override
  void onReady() {}
}

class _Friends extends GetxController
    implements SelectContactsFromFriendsLogic {
  _Friends(List<ISUserInfo> friends) : friendList = friends.obs;

  @override
  final RxList<ISUserInfo> friendList;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Presence implements PresenceStore {
  @override
  final users = <String, UserPresence>{}.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Stars implements StarFriendStore {
  @override
  final records = <String, StarFriend>{}.obs;

  @override
  bool isStarred(String id) => records[id]?.starred == true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ContactCardPickerContacts extends GetxController
    implements ContactsLogic {
  ContactCardPickerContacts() {
    final lastSeen = DateTime.now()
        .subtract(const Duration(hours: 3))
        .millisecondsSinceEpoch;
    presence.users.addAll({
      '1001': UserPresence(true, null),
      '1002': UserPresence(false, lastSeen),
      '2001': UserPresence(true, lastSeen, showLastSeen: false),
      '3001': UserPresence(false, null),
    });
    stars.records['1001'] = StarFriend.fromJson({
      'friendUserID': '1001',
      'starred': true,
      'version': 1,
      'updatedAt': 10,
    });
  }

  @override
  bool get isCurrentSession => true;

  @override
  final PresenceStore presence = _Presence();

  @override
  final StarFriendStore stars = _Stars();

  final batches = <({Object owner, Set<String>? ids})>[];
  final owners = <Object, Set<String>>{};

  @override
  void setDirectoryPresenceVisible(Object owner, Set<String>? userIDs) {
    final ids = userIDs == null ? null : Set<String>.of(userIDs);
    batches.add((owner: owner, ids: ids));
    if (ids == null) {
      owners.remove(owner);
    } else {
      owners[owner] = ids;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<ISUserInfo> cardPickerFriends() {
  final data = [
    ISUserInfo.fromJson({
      'userID': '1001',
      'nickname': 'Alberto',
      'remark': 'Alice',
      'tagIndex': 'A',
      'namePinyin': 'ALICE'
    }),
    ISUserInfo.fromJson({
      'userID': '1002',
      'nickname': 'Ada Lovelace',
      'remark': 'Aster',
      'tagIndex': 'A',
      'namePinyin': 'ASTER'
    }),
    ISUserInfo.fromJson({
      'userID': '2001',
      'nickname': 'Bob',
      'tagIndex': 'B',
      'namePinyin': 'BOB'
    }),
    ISUserInfo.fromJson({
      'userID': '3001',
      'nickname': '张三',
      'tagIndex': 'Z',
      'namePinyin': 'ZHANG SAN'
    }),
  ];
  SuspensionUtil.setShowSuspensionStatus(data);
  return data;
}

class ContactCardPickerFixture {
  ContactCardPickerFixture({List<ISUserInfo>? data, bool withPresence = false})
      : friends = _Friends(data ?? cardPickerFriends()),
        contacts = withPresence ? ContactCardPickerContacts() : null;

  final SelectContactsFromFriendsLogic friends;
  final SelectContactsLogic selection = _Selection();
  final ContactCardPickerContacts? contacts;
  UserInfo? result;
  int returns = 0;

  Future<void> mount(WidgetTester tester,
      {Brightness brightness = Brightness.light,
      Size size = const Size(375, 812),
      double textScale = 1}) async {
    Get.put<SelectContactsLogic>(selection, permanent: true);
    Get.put<SelectContactsFromFriendsLogic>(friends, permanent: true);
    if (contacts != null) Get.put<ContactsLogic>(contacts!, permanent: true);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final wasDark = Styles.isDark;
    Styles.isDark = brightness == Brightness.dark;
    addTearDown(() => Styles.isDark = wasDark);
    final font = const bool.fromEnvironment('CONTACT_CARD_PICKER_PREVIEW')
        ? 'ContactCardPickerPreviewFont'
        : null;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        theme: ThemeData(brightness: brightness, fontFamily: font),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: Scaffold(
            body: Center(
                child: TextButton(
          key: const ValueKey('open-contact-card-picker'),
          onPressed: () async {
            result = await Get.to<UserInfo>(
                () => RepaintBoundary(
                      key: contactCardPickerPreviewKey,
                      child: SelectContactsPage(),
                    ),
                transition: Transition.noTransition);
            returns++;
          },
          child: const Text('父聊天页面'),
        ))),
      ),
    ));
    await tester.pumpAndSettle();
    addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
    await tester.tap(find.byKey(const ValueKey('open-contact-card-picker')));
    await tester.pumpAndSettle();
  }
}

Future<void> loadContactCardPickerPreviewFont() async {
  if (!const bool.fromEnvironment('CONTACT_CARD_PICKER_PREVIEW')) return;
  for (final font in {
    'ContactCardPickerPreviewFont': 'C:/Windows/Fonts/msyh.ttc',
    'MaterialIcons':
        'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    final loader = FontLoader(font.key)
      ..addFont(File(font.value)
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
    await loader.load();
  }
  final cupertino = FontLoader('packages/cupertino_icons/CupertinoIcons')
    ..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'));
  await cupertino.load();
}

Future<void> captureContactCardPicker(
    WidgetTester tester, Brightness brightness,
    {bool large = false}) async {
  if (!const bool.fromEnvironment('CONTACT_CARD_PICKER_PREVIEW')) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(contactCardPickerPreviewKey));
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final suffix = large ? '-large' : '';
    await File('.dart_tool/contact-card-picker-${brightness.name}$suffix.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
