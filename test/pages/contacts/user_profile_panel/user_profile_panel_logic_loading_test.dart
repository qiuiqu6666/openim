import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/chat/navigation/chat_message_navigation.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim/pages/contacts/user_profile_panel/user_profile _panel_binding.dart';
import 'package:openim/pages/contacts/user_profile_panel/user_profile _panel_logic.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _peer = 'profile-loading-peer';
const _sdk = MethodChannel('flutter_openim_sdk');

class _App extends GetxController implements AppController {
  @override
  final clientConfigMap = <String, dynamic>{}.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController with IMCallback implements IMController {
  @override
  void onClose() {
    close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conversations extends GetxController implements ConversationLogic {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Contacts extends GetxController implements ContactsLogic {
  _Contacts({this.active = true});
  final bool active;
  final _owner = OpenIM.iMManager.userID;
  final _token = DataSp.chatToken;
  @override
  final friends = <ISUserInfo>[].obs;
  @override
  bool get isCurrentSession =>
      active && _owner == OpenIM.iMManager.userID && _token == DataSp.chatToken;
  @override
  void setProfilePresence(Object owner, String? peerUserID) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Profile and common-group HTTP both use the real shared Dio instance. Keeping
// the adapter local verifies controller sequencing without real network calls.
class _Http implements HttpClientAdapter {
  final profileReplies = <Completer<ResponseBody>>[];
  bool gateProfiles = false;
  bool gateExtensions = false;
  String extension = '{"signature":"A stable signature"}';
  final extensionReplies = <Completer<ResponseBody>>[];
  final extensionRequests = <RequestOptions>[];

  ResponseBody extensionResponse(String ex) => ResponseBody.fromString(
        jsonEncode({
          'errCode': 0,
          'data': {
            'usersInfo': [
              {'userID': _peer, 'ex': ex}
            ]
          }
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      );

  ResponseBody profile(String id) => ResponseBody.fromString(
        jsonEncode({
          'errCode': 0,
          'data': {
            'users': [
              {'userID': id, 'account': 'chat-number', 'gender': 1}
            ]
          }
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      );

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.path.endsWith('/user/get_users_info')) {
      extensionRequests.add(options);
      if (gateExtensions) {
        final reply = Completer<ResponseBody>();
        extensionReplies.add(reply);
        return reply.future;
      }
      return extensionResponse(extension);
    }
    if (options.method == 'GET') {
      return ResponseBody.fromString(
        jsonEncode({
          'errCode': 0,
          'data': {'total': 2}
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      );
    }
    final ids = (options.data as Map)['userIDs'] as List;
    if (gateProfiles) {
      final reply = Completer<ResponseBody>();
      profileReplies.add(reply);
      return reply.future;
    }
    return profile(ids.single as String);
  }

  @override
  void close({bool force = false}) {}
}

class _FirstFrame {
  _FirstFrame(UserProfilePanelLogic logic)
      : ready = logic.profileLayoutReady.value,
        failed = logic.initialProfileFailed.value,
        friendship = logic.isFriendship,
        nickname = logic.userInfo.value.nickname,
        avatar = logic.userInfo.value.faceURL,
        remark = logic.userInfo.value.remark;
  final bool ready;
  final bool failed;
  final bool friendship;
  final String? nickname;
  final String? avatar;
  final String? remark;
}

// Use the actual route, binding and controller. The probe omits unrelated image
// and call widgets, and records layout state before the first onReady query.
class _Probe extends StatelessWidget {
  const _Probe(this.onFirstFrame);
  final void Function(UserProfilePanelLogic) onFirstFrame;
  @override
  Widget build(BuildContext context) {
    final logic = Get.find<UserProfilePanelLogic>(tag: GetTags.userProfile);
    onFirstFrame(logic);
    return Scaffold(
      body: Obx(() => Text(logic.profileLayoutReady.value
          ? (logic.isFriendship ? 'friend-ready' : 'profile-ready')
          : (logic.initialProfileFailed.value ? 'initial-error' : 'loading'))),
    );
  }
}

Future<void> _login(String id, String token) async {
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': id,
    'chatToken': token,
    'imToken': '$id-im',
  }));
}

String _friend({String nickname = 'SDK friend'}) => jsonEncode([
      {'userID': _peer, 'nickname': nickname, 'remark': 'SDK remark'}
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _IM im;
  late _Http adapter;
  late List<Completer<String>> friendReplies;
  late List<String> nativeMethods;
  late List<Map<dynamic, dynamic>> friendArguments;
  late Dio previousDio;
  UserProfilePanelLogic? logic;
  _FirstFrame? firstFrame;
  var tagCreated = false;
  var blacklist = '[]';

  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await _login('me', 'me-chat');
    OpenIM.iMManager.userID = 'me';
    UserCacheManager().removeUserInfo(_peer);
    UserCacheManager().removeUserInfo('me');
    Get.put<AppController>(_App());
    im = Get.put<IMController>(_IM()) as _IM;
    Get.put<ConversationLogic>(_Conversations());
    previousDio = http.dio;
    adapter = _Http();
    http.dio = Dio(BaseOptions(baseUrl: 'http://profile.test'))
      ..httpClientAdapter = adapter;
    friendReplies = [];
    nativeMethods = [];
    friendArguments = [];
    blacklist = '[]';
    logic = null;
    firstFrame = null;
    tagCreated = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdk, (call) {
      nativeMethods.add(call.method);
      switch (call.method) {
        case 'getFriendsInfo':
          friendArguments.add(call.arguments as Map);
          final reply = Completer<String>();
          friendReplies.add(reply);
          return reply.future;
        case 'getBlacklist':
          return Future.value(blacklist);
        case 'getUsersInfo':
          return Future.value(jsonEncode([
            {
              'userID': _peer,
              'nickname': 'SDK profile',
              'ex': jsonEncode({'signature': 'A stable signature'})
            }
          ]));
        case 'getSelfUserInfo':
          return Future.value(
              jsonEncode({'userID': 'me', 'nickname': 'SDK self'}));
        default:
          throw StateError('Unexpected native profile call: ${call.method}');
      }
    });
  });

  tearDown(() async {
    if (logic != null && !logic!.isClosed) logic!.onDelete();
    for (final reply in friendReplies) {
      if (!reply.isCompleted) reply.complete('[]');
    }
    for (final reply in adapter.extensionReplies) {
      if (!reply.isCompleted) reply.complete(adapter.extensionResponse(''));
    }
    for (final reply in adapter.profileReplies) {
      if (!reply.isCompleted) reply.complete(adapter.profile(_peer));
    }
    Get.reset();
    if (tagCreated) GetTags.destroyUserProfileTag();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdk, null);
    http.dio.close(force: true);
    http.dio = previousDio;
    UserCacheManager().removeUserInfo(_peer);
    UserCacheManager().removeUserInfo('me');
  });

  Future<void> open(WidgetTester tester,
      {String id = _peer, bool fromGroupCard = false}) async {
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: '/',
      getPages: [
        GetPage(name: '/', page: () => const Scaffold()),
        GetPage(
          name: AppRoutes.myProfile,
          page: () => const Scaffold(body: Text('my-profile')),
        ),
        GetPage(
          name: AppRoutes.userProfilePanel,
          binding: UserProfilePanelBinding(),
          page: () => _Probe((value) {
            logic = value;
            firstFrame ??= _FirstFrame(value);
          }),
        ),
      ],
    ));
    if (fromGroupCard) {
      ChatMessageNavigation(
        isClosed: () => false,
        isGroupChat: () => true,
        isSingleChat: () => false,
        isAdminOrOwner: () => false,
        groupID: () => 'source-group',
        groupInfo: () => GroupInfo(groupID: 'source-group', lookMemberInfo: 1),
      ).viewUserInfo(
        UserInfo(userID: id, nickname: 'Route name', faceURL: 'route-avatar'),
        isCard: true,
        inviteCode: 'card-invite',
      );
    } else {
      AppNavigator.startUserProfilePane(
          userID: id, nickname: 'Route name', faceURL: 'route-avatar');
    }
    tagCreated = !AppNavigator.isCurrentUser(id);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    if (AppNavigator.isCurrentUser(id)) return;
    expect(logic, isNotNull);
    expect(logic!.userInfo.value.userID, id);
  }

  _Contacts contacts({bool active = true, bool hasPeer = true}) {
    final directory = _Contacts(active: active);
    if (hasPeer) {
      directory.friends.add(ISUserInfo.fromJson({
        'userID': _peer,
        'nickname': 'Directory friend',
        'faceURL': 'directory-avatar',
        'remark': 'Directory remark',
        'gender': 1,
      }));
    }
    Get.put<ContactsLogic>(directory);
    return directory;
  }

  testWidgets('opening profile replaces cached signature with server extension',
      (tester) async {
    contacts();
    UserCacheManager().addOrUpdateUserInfo(
        _peer,
        UserFullInfo()
          ..userID = _peer
          ..ex = '{"signature":"old"}');
    adapter.extension = '{"signature":"new"}';
    await open(tester);
    friendReplies.single.complete(_friend());
    await tester.pumpAndSettle();
    expect(logic!.userInfo.value.ex, adapter.extension);
    expect(UserCacheManager().getUserInfo(_peer)!.ex, adapter.extension);
    expect(adapter.extensionRequests.single.headers['token'], 'me-im');
    expect(adapter.extensionRequests.single.data, {
      'userIDs': [_peer]
    });
  });

  testWidgets('friend update refreshes signature and supports clearing',
      (tester) async {
    contacts();
    await open(tester);
    friendReplies.single.complete(_friend());
    await tester.pumpAndSettle();
    for (final ex in ['{"signature":"changed"}', '']) {
      adapter.extension = ex;
      im.friendInfoChanged(FriendInfo(userID: _peer, ex: 'relationship-only'));
      await tester.pumpAndSettle();
      expect(logic!.userInfo.value.ex, ex);
      expect(logic!.profileLayoutReady.value, isTrue);
      expect(UserCacheManager().getUserInfo(_peer)!.ex, ex);
    }
  });

  testWidgets('newer signature response wins over delayed opening request',
      (tester) async {
    contacts();
    adapter.gateExtensions = true;
    await open(tester);
    friendReplies.single.complete(_friend());
    await tester.pumpAndSettle();
    im.friendInfoChanged(FriendInfo(userID: _peer));
    await tester.pumpAndSettle();
    expect(adapter.extensionReplies, hasLength(2));
    adapter.extensionReplies.last.complete(adapter.extensionResponse('new'));
    await tester.pumpAndSettle();
    adapter.extensionReplies.first.complete(adapter.extensionResponse('old'));
    await tester.pumpAndSettle();
    expect(logic!.userInfo.value.ex, 'new');
  });

  testWidgets('foreground refreshes personal profile without restarting app',
      (tester) async {
    contacts();
    await open(tester);
    friendReplies.single.complete(_friend());
    await tester.pumpAndSettle();
    adapter.extension = '{"signature":"foreground"}';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(logic!.userInfo.value.ex, adapter.extension);
  });

  testWidgets('failed refresh retains confirmed signature', (tester) async {
    contacts();
    await open(tester);
    friendReplies.single.complete(_friend());
    await tester.pumpAndSettle();
    final confirmed = logic!.userInfo.value.ex;
    adapter.gateExtensions = true;
    im.friendInfoChanged(FriendInfo(userID: _peer));
    await tester.pumpAndSettle();
    adapter.extensionReplies.single.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(logic!.userInfo.value.ex, confirmed);
    expect(logic!.initialProfileFailed.value, isFalse);
  });

  testWidgets('closed profile ignores pending extension', (tester) async {
    contacts();
    adapter.gateExtensions = true;
    await open(tester);
    friendReplies.single.complete(_friend());
    await tester.pumpAndSettle();
    final previous = logic!.userInfo.value.ex;
    logic!.onDelete();
    adapter.extensionReplies.single.complete(adapter.extensionResponse('late'));
    await tester.pumpAndSettle();
    expect(logic!.userInfo.value.ex, previous);
  });

  testWidgets('changed account ignores pending extension', (tester) async {
    contacts();
    adapter.gateExtensions = true;
    await open(tester);
    friendReplies.single.complete(_friend());
    await tester.pumpAndSettle();
    await _login('other', 'other-chat');
    OpenIM.iMManager.userID = 'other';
    adapter.extensionReplies.single.complete(adapter.extensionResponse('late'));
    await tester.pumpAndSettle();
    expect(logic!.userInfo.value.ex, isNot('late'));
  });

  testWidgets(
      'group card opens a personal profile with the returned public account',
      (tester) async {
    contacts();
    await open(tester, fromGroupCard: true);
    expect(logic!.isGroupMemberPage, isFalse);
    expect(logic!.groupID, isNull);
    expect(logic!.addSource, FriendAddSource.card);
    expect(logic!.friendAddFields, {'inviteCode': 'card-invite'});
    friendReplies.single.complete(_friend());
    await tester.pumpAndSettle();
    expect(logic!.displayedUserID, 'chat-number');
    expect(logic!.userInfo.value.userID, _peer);
    expect(logic!.isFriendship, isTrue);
  });

  testWidgets('current directory seeds the friend layout before SDK replies',
      (tester) async {
    contacts();
    await open(tester);
    expect(firstFrame!.ready, isTrue);
    expect(firstFrame!.friendship, isTrue);
    expect(firstFrame!.nickname, 'Directory friend');
    expect(firstFrame!.avatar, 'directory-avatar');
    expect(firstFrame!.remark, 'Directory remark');
    expect(friendReplies, hasLength(1));
    expect(friendArguments.single['userIDList'], [_peer]);
    expect(find.text('friend-ready'), findsOneWidget);
  });

  testWidgets(
      'cached friend deletion cannot override a current directory friend',
      (tester) async {
    contacts();
    im.friendDeleted(FriendInfo(userID: _peer));
    await open(tester);
    expect(firstFrame!.ready, isTrue);
    expect(firstFrame!.friendship, isTrue);
    expect(logic!.isFriendship, isTrue);
    expect(logic!.userInfo.value.remark, 'Directory remark');
    expect(find.text('friend-ready'), findsOneWidget);
    expect(friendReplies, hasLength(1));
    friendReplies.single.complete(_friend());
    await tester.pumpAndSettle();
    expect(logic!.isFriendship, isTrue);
    expect(logic!.userInfo.value.remark, 'SDK remark');
  });

  testWidgets('cached friend addition cannot resolve an unknown relationship',
      (tester) async {
    contacts(hasPeer: false);
    im.friendAdded(FriendInfo(userID: _peer));
    await open(tester);
    expect(firstFrame!.ready, isFalse);
    expect(firstFrame!.friendship, isFalse);
    expect(logic!.profileLayoutReady.value, isFalse);
    expect(logic!.isFriendship, isFalse);
    expect(find.text('loading'), findsOneWidget);
    expect(friendReplies, hasLength(1));
    friendReplies.single.complete('[]');
    await tester.pumpAndSettle();
    expect(logic!.profileLayoutReady.value, isTrue);
    expect(logic!.isFriendship, isFalse);
    expect(find.text('profile-ready'), findsOneWidget);
  });

  testWidgets('unknown directory relation stays loading until SDK confirmation',
      (tester) async {
    contacts(hasPeer: false);
    await open(tester);
    expect(firstFrame!.ready, isFalse);
    expect(firstFrame!.failed, isFalse);
    expect(find.text('loading'), findsOneWidget);
    friendReplies.single.complete('[]');
    await tester.pumpAndSettle();
    expect(logic!.profileLayoutReady.value, isTrue);
    expect(logic!.isFriendship, isFalse);
    expect(logic!.initialProfileFailed.value, isFalse);
  });

  testWidgets('a stale directory cannot seed friendship in a new session',
      (tester) async {
    contacts(active: false);
    await open(tester);
    expect(firstFrame!.ready, isFalse);
    expect(firstFrame!.friendship, isFalse);
    expect(firstFrame!.nickname, 'Route name');
    expect(firstFrame!.remark, isNull);
    expect(logic!.profileLayoutReady.value, isFalse);
  });

  testWidgets('global profile cache is not authority for relation or remark',
      (tester) async {
    UserCacheManager().addOrUpdateUserInfo(
        _peer,
        UserFullInfo.fromJson({
          'userID': _peer,
          'nickname': 'Cached name',
          'remark': 'Old account private remark',
          'account': 'Old account private ID',
          'isFriendship': true,
          'isBlacklist': true,
        }));
    await open(tester);
    expect(firstFrame!.ready, isFalse);
    expect(firstFrame!.friendship, isFalse);
    expect(logic!.isFriendship, isFalse);
    expect(logic!.userInfo.value.remark, isNull);
    expect(logic!.userInfo.value.account, isNull);
    expect(logic!.userInfo.value.isBlacklist, isFalse);
  });

  testWidgets('SDK friend and blacklist confirmation completes unknown layout',
      (tester) async {
    blacklist = jsonEncode([
      {'userID': _peer, 'nickname': 'Blocked friend'}
    ]);
    await open(tester);
    friendReplies.single.complete(_friend());
    await tester.pumpAndSettle();
    expect(logic!.profileLayoutReady.value, isTrue);
    expect(logic!.isFriendship, isTrue);
    expect(logic!.userInfo.value.remark, 'SDK remark');
    expect(logic!.userInfo.value.isBlacklist, isTrue);
    expect(logic!.userInfo.value.account, 'chat-number');
    expect(logic!.initialProfileFailed.value, isFalse);
  });

  testWidgets('live friend identity updates both the profile and its cache',
      (tester) async {
    await open(tester);
    friendReplies.single.complete(_friend());
    await tester.pumpAndSettle();
    im.friendInfoChanged(FriendInfo(
      userID: _peer,
      nickname: 'New nickname',
      faceURL: 'new-avatar',
      remark: 'My remark',
    ));
    await tester.pumpAndSettle();
    expect(logic!.userInfo.value.nickname, 'New nickname');
    expect(logic!.userInfo.value.faceURL, 'new-avatar');
    expect(logic!.userInfo.value.remark, 'My remark');
    expect(UserCacheManager().getUserInfo(_peer)!.faceURL, 'new-avatar');

    im.friendInfoChanged(FriendInfo(
      userID: _peer,
      nickname: 'New nickname',
      faceURL: '',
      remark: '',
    ));
    await tester.pumpAndSettle();
    expect(logic!.userInfo.value.faceURL, '');
    expect(logic!.userInfo.value.remark, '');
  });

  testWidgets('live identity survives an older in-flight friend snapshot',
      (tester) async {
    await open(tester);
    im.friendInfoChanged(FriendInfo(
      userID: _peer,
      nickname: 'Latest nickname',
      faceURL: 'latest-avatar',
      remark: 'Latest remark',
    ));
    await tester.pump();
    friendReplies.single.complete(_friend(nickname: 'Old nickname'));
    await tester.pumpAndSettle();
    expect(logic!.userInfo.value.nickname, 'Latest nickname');
    expect(logic!.userInfo.value.faceURL, 'latest-avatar');
    expect(logic!.userInfo.value.remark, 'Latest remark');
    expect(logic!.userInfo.value.account, 'chat-number');
    expect(logic!.profileLayoutReady.value, isTrue);
    expect(UserCacheManager().getUserInfo(_peer)!.nickname, 'Latest nickname');
  });

  testWidgets('self navigation opens own profile without a peer profile query',
      (tester) async {
    await open(tester, id: 'me');
    await tester.pumpAndSettle();
    expect(find.text('my-profile'), findsOneWidget);
    expect(logic, isNull);
    expect(firstFrame, isNull);
    expect(nativeMethods, isEmpty);
    expect(friendReplies, isEmpty);
  });

  testWidgets(
      'unknown SDK failure stays unresolved and an explicit retry works',
      (tester) async {
    await open(tester);
    friendReplies.single.completeError(
        PlatformException(code: '500', message: 'SDK unavailable'));
    await tester.pumpAndSettle();
    expect(logic!.profileLayoutReady.value, isFalse);
    expect(logic!.initialProfileFailed.value, isTrue);
    expect(find.text('initial-error'), findsOneWidget);
    final retry = logic!.retryInitialProfile();
    await tester.pump();
    expect(logic!.initialProfileFailed.value, isFalse);
    expect(logic!.profileLayoutReady.value, isFalse);
    expect(friendReplies, hasLength(2));
    friendReplies.last.complete(_friend());
    await tester.pumpAndSettle();
    await retry;
    expect(logic!.profileLayoutReady.value, isTrue);
    expect(logic!.isFriendship, isTrue);
  });

  testWidgets('known friend presentation survives an initial SDK outage',
      (tester) async {
    contacts();
    await open(tester);
    friendReplies.single.completeError(
        PlatformException(code: '500', message: 'SDK unavailable'));
    await tester.pumpAndSettle();
    expect(logic!.profileLayoutReady.value, isTrue);
    expect(logic!.isFriendship, isTrue);
    expect(logic!.initialProfileFailed.value, isFalse);
    expect(logic!.userInfo.value.remark, 'Directory remark');
  });

  testWidgets('closing the controller discards a late friend reply',
      (tester) async {
    await open(tester);
    logic!.onDelete();
    friendReplies.single.complete(_friend());
    await tester.pumpAndSettle();
    expect(logic!.isClosed, isTrue);
    expect(logic!.profileLayoutReady.value, isFalse);
    expect(logic!.isFriendship, isFalse);
    expect(nativeMethods, isNot(contains('getBlacklist')));
    expect(UserCacheManager().getUserInfo(_peer), isNull);
  });

  testWidgets('switching accounts discards the previous relation response',
      (tester) async {
    await open(tester);
    await _login('next-account', 'next-chat');
    OpenIM.iMManager.userID = 'next-account';
    friendReplies.single.complete(_friend());
    await tester.pumpAndSettle();
    expect(logic!.profileLayoutReady.value, isFalse);
    expect(logic!.isFriendship, isFalse);
    expect(nativeMethods, isNot(contains('getBlacklist')));
    expect(UserCacheManager().getUserInfo(_peer), isNull);
  });

  testWidgets(
      'rotating the same account token discards its older relation read',
      (tester) async {
    await open(tester);
    await _login('me', 'rotated-chat');
    friendReplies.single.complete(_friend());
    await tester.pumpAndSettle();
    expect(logic!.profileLayoutReady.value, isFalse);
    expect(logic!.isFriendship, isFalse);
    expect(nativeMethods, isNot(contains('getBlacklist')));
  });

  testWidgets('friend deletion prevents an older snapshot restoring friendship',
      (tester) async {
    contacts();
    im.friendDeleted(FriendInfo(userID: _peer));
    await open(tester);
    expect(logic!.isFriendship, isTrue);
    expect(friendReplies, hasLength(1));
    im.friendDeleted(FriendInfo(userID: _peer));
    await tester.pump();
    expect(friendReplies, hasLength(2));
    expect(logic!.isFriendship, isFalse);
    friendReplies.last.complete('[]');
    await tester.pumpAndSettle();
    friendReplies.first.complete(_friend(nickname: 'Obsolete friend'));
    await tester.pumpAndSettle();
    expect(logic!.isFriendship, isFalse);
    expect(logic!.userInfo.value.nickname, 'SDK profile');
    expect(logic!.userInfo.value.remark, isNull);
  });

  testWidgets('friend addition wins over an in-flight older nonfriend read',
      (tester) async {
    im.friendAdded(FriendInfo(userID: _peer));
    await open(tester);
    expect(logic!.isFriendship, isFalse);
    expect(logic!.profileLayoutReady.value, isFalse);
    expect(friendReplies, hasLength(1));
    im.friendAdded(FriendInfo(userID: _peer, nickname: 'Added friend'));
    await tester.pumpAndSettle();
    expect(logic!.isFriendship, isTrue);
    expect(logic!.profileLayoutReady.value, isTrue);
    friendReplies.single.complete('[]');
    await tester.pumpAndSettle();
    expect(logic!.isFriendship, isTrue);
    expect(nativeMethods, isNot(contains('getBlacklist')));
  });

  testWidgets('late full-profile data cannot write after token rotation',
      (tester) async {
    adapter.gateProfiles = true;
    await open(tester);
    friendReplies.single.complete(_friend());
    await tester.pumpAndSettle();
    expect(adapter.profileReplies, hasLength(1));
    expect(logic!.profileLayoutReady.value, isTrue);
    expect(logic!.userInfo.value.account, isNull);
    await _login('me', 'rotated-chat');
    adapter.profileReplies.single.complete(adapter.profile(_peer));
    await tester.pumpAndSettle();
    expect(logic!.userInfo.value.account, isNull);
  });
}
