import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/calling/preferences/call_notification_preferences.dart';
import 'package:openim/pages/chat/calling/preferences/call_notification_preference_binding.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:openim_live/openim_live.dart';
import 'package:openim_live/src/signaling/call_ringtone.dart';
import 'package:openim_live/src/widgets/incoming_call/incoming_call_quick_answer_sheet.dart';
import 'package:openim_live/src/pages/single/widgets/controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/waiting_tone_player.dart';

class _Live extends Object with OpenIMLive {
  _Live(this.sound);
  final CallRingtone sound;
  IncomingCallPreferences Function(String)? preferences;
  @override
  CallRingtone get callRingtone => sound;
  @override
  IncomingCallPreferences preferencesForIncomingCall(String accountID) =>
      preferences?.call(accountID) ?? const IncomingCallPreferences();
  @override
  Future<UserInfo?> onSyncUserInfo(String userID) async =>
      UserInfo(userID: userID, nickname: 'Local call peer');
}

class _CertificateAdapter implements HttpClientAdapter {
  Completer<void>? gate;
  bool fail = false;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
      Future<void>? cancelFuture) async {
    requests++;
    await gate?.future;
    if (fail) {
      throw DioException.connectionTimeout(
          requestOptions: options, timeout: const Duration(seconds: 30));
    }
    return ResponseBody.fromString(
        jsonEncode({
          'errCode': 0,
          'errMsg': '',
          'data': {'token': 'local-test-token', 'liveURL': 'wss://rtc.test'},
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });
  }

  @override
  void close({bool force = false}) {}
}

SignalingInfo _signal(
        {String inviter = 'alice',
        String actor = 'alice',
        String room = 'ringback-test-room'}) =>
    SignalingInfo(
        userID: actor,
        invitation: InvitationInfo(
          roomID: room,
          inviterUserID: inviter,
          inviteeUserIDList: [inviter == 'alice' ? 'bob' : 'alice'],
          mediaType: 'audio',
          sessionType: ConversationType.single,
          timeout: 30,
          initiateTime: DateTime.now().millisecondsSinceEpoch,
        ));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const imChannel = MethodChannel('flutter_openim_sdk');
  const wakelockChannel =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late WaitingTonePlayerProbe player;
  late _Live live;
  late _CertificateAdapter certificates;
  Completer<void>? inviteGate;
  bool failInvite = false;
  var sends = 0;

  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'alice',
      'chatToken': 'local-chat-token',
      'imToken': 'local-im-token',
    }));
    OpenIM.iMManager.userID = 'alice';
    player = WaitingTonePlayerProbe();
    live = _Live(CallRingtone(createPlayer: () => player));
    certificates = _CertificateAdapter();
    http.dio = Dio();
    HttpUtil.init();
    http.dio.httpClientAdapter = certificates;
    inviteGate = null;
    failInvite = false;
    sends = 0;
    messenger.setMockMethodCallHandler(imChannel, (call) async {
      final args = call.arguments as Map;
      if (call.method == 'createCustomMessage') {
        return jsonEncode({
          'clientMsgID': 'local-message',
          'sendID': OpenIM.iMManager.userID,
          'contentType': 110,
          'customElem': {
            'data': args['data'],
            'extension': '',
            'description': ''
          },
        });
      }
      if (call.method == 'sendMessage') {
        sends++;
        final message = args['message'] as Map;
        final signal =
            jsonDecode(message['customElem']['data'] as String) as Map;
        if (signal['customType'] == CustomMessageType.callingInvite) {
          await inviteGate?.future;
          if (failInvite) throw PlatformException(code: '10000');
        }
        return jsonEncode(message);
      }
      if (call.method == 'insertSingleMessageToLocalStorage') {
        return jsonEncode(args['message']);
      }
      throw StateError('Unexpected native operation ${call.method}');
    });
    messenger.setMockMessageHandler(wakelockChannel,
        (_) async => const StandardMessageCodec().encodeMessage([null]));
    live.onInitLive();
    live.backgroundSubject.add(true);
    await flushWaitingToneTasks();
  });

  tearDown(() async {
    await live.onCloseLive();
    http.dio.close(force: true);
    messenger.setMockMethodCallHandler(imChannel, null);
    messenger.setMockMessageHandler(wakelockChannel, null);
    OpenIM.iMManager.userID = '';
    Get.reset();
  });

  Future<void> mountHost(WidgetTester tester) async {
    // Bind the real Navigator explicitly for the controller's Get context.
    final navigator = GlobalKey<NavigatorState>();
    Get.addKey(navigator);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: Text('existing chat')),
    ));
    await tester.pump();
    expect(Get.key.currentState, isNotNull);
    expect(Get.overlayContext, isNotNull);
    // Recent Flutter versions resolve Overlay via an entry marker. Get's
    // context is an Overlay child outside that marker; the supplied context's
    // Navigator must still resolve its existing overlay for call presentation.
    expect(Navigator.maybeOf(Get.overlayContext!)?.overlay, isNotNull);
  }

  Future<void> beginUnMountedCall({String room = 'ringback-test-room'}) async {
    // Exercise the actual controller before the newly inserted overlay's next
    // frame. No camera, permission dialog or RTC connection is ever mounted.
    await live.call(
        callObj: CallObj.single,
        callType: CallType.audio,
        roomID: room,
        inviteeUserIDList: ['bob']);
    expect(live.isBusy, isTrue);
  }

  testWidgets('invite and credentials succeed before outgoing waiting sound',
      (tester) async {
    await mountHost(tester);
    await tester.runAsync(() async {
      await beginUnMountedCall();
      inviteGate = Completer<void>();
      certificates.gate = Completer<void>();
      final request = live.onDialSingle(_signal());
      await flushWaitingToneTasks();
      expect(sends, 1);
      expect(certificates.requests, 0);
      expect(player.starts, 0);
      inviteGate!.complete();
      await flushWaitingToneTasks();
      expect(certificates.requests, 1);
      expect(player.starts, 0);
      certificates.gate!.complete();
      final certificate = await request;
      expect(certificate.roomID, 'ringback-test-room');
      await flushWaitingToneTasks();
      expect(player.prepared, [CallWaitingTone.outgoing]);
      expect(player.starts, 1);
      await live.endLiveSession(notifyPeer: false);
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('audio preparation never blocks RTC credentials or call setup',
      (tester) async {
    await mountHost(tester);
    await tester.runAsync(() async {
      await beginUnMountedCall();
      player.loadGate = Completer<void>();
      final certificate = await live.onDialSingle(_signal());
      expect(certificate.token, 'local-test-token');
      await flushWaitingToneTasks();
      expect(player.assets, hasLength(1));
      expect(player.starts, 0);
      await live.endLiveSession(notifyPeer: false);
      player.loadGate!.complete();
      await flushWaitingToneTasks();
      expect(player.starts, 0);
    });
    await tester.pumpWidget(const SizedBox());
  });

  for (final inviteFailure in [true, false]) {
    testWidgets('${inviteFailure ? 'invite' : 'token'} failure stays silent',
        (tester) async {
      await mountHost(tester);
      await tester.runAsync(() async {
        await beginUnMountedCall();
        failInvite = inviteFailure;
        certificates.fail = !inviteFailure;
        await expectLater(live.onDialSingle(_signal()), throwsA(anything));
        await flushWaitingToneTasks();
        expect(player.assets, isEmpty);
        expect(player.starts, 0);
        await live.endLiveSession(notifyPeer: false);
      });
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final response in [CallState.beAccepted, CallState.beRejected]) {
    testWidgets('early $response prevents late credential completion ringing',
        (tester) async {
      await mountHost(tester);
      await tester.runAsync(() async {
        await beginUnMountedCall();
        certificates.gate = Completer<void>();
        final request = live.onDialSingle(_signal());
        await flushWaitingToneTasks();
        final reply = _signal(actor: 'bob');
        if (response == CallState.beAccepted) {
          live.inviteeAccepted(reply);
        } else {
          live.inviteeRejected(reply);
        }
        await flushWaitingToneTasks();
        certificates.gate!.complete();
        if (response == CallState.beAccepted) {
          expect((await request).token, 'local-test-token');
        } else {
          await expectLater(request, throwsA(isA<CallRequestCancelled>()));
        }
        await flushWaitingToneTasks();
        expect(player.starts, 0);
        await live.endLiveSession(notifyPeer: false);
      });
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final response in [
    CallState.beAccepted,
    CallState.beRejected,
    CallState.timeout,
    CallState.cancel,
    CallState.beHangup,
  ]) {
    testWidgets('$response stops playing outgoing waiting sound',
        (tester) async {
      await mountHost(tester);
      await tester.runAsync(() async {
        await beginUnMountedCall();
        await live.onDialSingle(_signal());
        await flushWaitingToneTasks();
        expect(player.starts, 1);
        final stops = player.stops;
        switch (response) {
          case CallState.beAccepted:
            live.inviteeAccepted(_signal(actor: 'bob'));
            break;
          case CallState.beRejected:
            live.inviteeRejected(_signal(actor: 'bob'));
            break;
          case CallState.timeout:
            await live.onTimeoutCancelled(_signal());
            break;
          case CallState.cancel:
            await live.onTapCancel(_signal());
            break;
          case CallState.beHangup:
            live.beHangup(_signal(actor: 'bob'));
            break;
          default:
            throw StateError('Unexpected test response');
        }
        await flushWaitingToneTasks();
        expect(player.stops, greaterThan(stops));
        expect(player.playback.single.isCompleted, isTrue);
        await live.endLiveSession(notifyPeer: false);
      });
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('playback failure does not fail a valid call certificate',
      (tester) async {
    await mountHost(tester);
    await tester.runAsync(() async {
      await beginUnMountedCall();
      player.failLoadOnce = true;
      final certificate = await live.onDialSingle(_signal());
      expect(certificate.token, 'local-test-token');
      await flushWaitingToneTasks();
      expect(live.isBusy, isTrue);
      expect(player.starts, 0);
      await live.endLiveSession(notifyPeer: false);
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a queued old-room response cannot stop the new room waiting tone',
      (tester) async {
    await mountHost(tester);
    await tester.runAsync(() async {
      await beginUnMountedCall();
      await live.onDialSingle(_signal());
      await flushWaitingToneTasks();
      await live.endLiveSession(notifyPeer: false);
      await beginUnMountedCall(room: 'new-ringback-room');
      await live.onDialSingle(_signal(room: 'new-ringback-room'));
      await flushWaitingToneTasks();
      expect(player.starts, 2);
      expect(player.playback.last.isCompleted, isFalse);
      final stops = player.stops;
      // The public stream can have an old response queued independently of the
      // already guarded inbound transport callback.
      live.signalingSubject
          .add(CallEvent(CallState.beAccepted, _signal(actor: 'bob')));
      await flushWaitingToneTasks();
      expect(player.stops, stops);
      expect(player.playback.last.isCompleted, isFalse);
      await live.endLiveSession(notifyPeer: false);
    });
    await tester.pumpWidget(const SizedBox());
  });

  for (final close in [true, false]) {
    testWidgets('${close ? 'controller close' : 'logout'} cancels a late tone',
        (tester) async {
      await mountHost(tester);
      await tester.runAsync(() async {
        await beginUnMountedCall();
        player.loadGate = Completer<void>();
        await live.onDialSingle(_signal());
        await flushWaitingToneTasks();
        if (close) {
          await live.onCloseLive();
          expect(player.disposals, 1);
        } else {
          await live.endLiveSession(notifyPeer: false);
        }
        player.loadGate!.complete();
        await flushWaitingToneTasks();
        expect(player.starts, 0);
        expect(live.isBusy, isFalse);
      });
      await tester.pumpWidget(const SizedBox());
    });
  }

  test('an incoming invitation only plays the retained incoming ringtone',
      () async {
    OpenIM.iMManager.userID = 'bob';
    live.receiveNewInvitation(_signal());
    await flushWaitingToneTasks();
    expect(player.prepared, [CallWaitingTone.incoming]);
    expect(player.assets.single.$2, 'openim_common');
    expect(player.starts, 1);
    await live.onTapReject(_signal());
    expect(player.playback.single.isCompleted, isTrue);
  });

  test('muting incoming calls leaves the invite available and uses its account',
      () async {
    OpenIM.iMManager.userID = 'bob';
    await SpUtil().putBool('99chat_settings_bob_call_ringtone_enabled', false);
    live.preferences = CallNotificationPreferences.read;
    live.receiveNewInvitation(_signal());
    await flushWaitingToneTasks();
    expect(live.isBusy, isTrue);
    expect(player.starts, 0);
    expect(player.assets, isEmpty);
    await live.onTapReject(_signal());
    expect(sends, 1, reason: 'The silent call still has a usable reject path');
  });

  test('changing an incoming ringtone cancels loading without losing the call',
      () async {
    OpenIM.iMManager.userID = 'bob';
    live.preferences = CallNotificationPreferences.read;
    final binding = CallNotificationPreferenceBinding(
      currentAccount: () => OpenIM.iMManager.userID,
      refresh: live.refreshIncomingCallPreferences,
    )..attach();
    addTearDown(binding.close);
    player.loadGate = Completer<void>();
    live.receiveNewInvitation(_signal());
    await flushWaitingToneTasks();
    expect(player.assets, hasLength(1));
    await SpUtil().putBool('99chat_settings_bob_call_ringtone_enabled', false);
    CallNotificationPreferences.notifyChanged('bob');
    await flushWaitingToneTasks();
    player.loadGate!.complete();
    await flushWaitingToneTasks();
    expect(player.starts, 0);
    expect(live.isBusy, isTrue);
    await SpUtil().putBool('99chat_settings_bob_call_ringtone_enabled', true);
    CallNotificationPreferences.notifyChanged('alice');
    await flushWaitingToneTasks();
    expect(player.starts, 0);
    CallNotificationPreferences.notifyChanged('bob');
    await flushWaitingToneTasks();
    expect(player.starts, 1);
    await live.onTapReject(_signal());
    final starts = player.starts;
    CallNotificationPreferences.notifyChanged('bob');
    await flushWaitingToneTasks();
    expect(player.starts, starts,
        reason: 'A terminal invite cannot ring again');
  });

  testWidgets('incoming mute keeps outgoing ringback available',
      (tester) async {
    await SpUtil()
        .putBool('99chat_settings_alice_call_ringtone_enabled', false);
    live.preferences = CallNotificationPreferences.read;
    await mountHost(tester);
    await tester.runAsync(() async {
      await beginUnMountedCall();
      await live.onDialSingle(_signal());
      await flushWaitingToneTasks();
      expect(player.prepared, [CallWaitingTone.outgoing]);
      expect(player.starts, 1);
      live.refreshIncomingCallPreferences();
      await flushWaitingToneTasks();
      expect(player.playback.single.isCompleted, isFalse);
      await live.endLiveSession(notifyPeer: false);
    });
    await tester.pumpWidget(const SizedBox());
  });

  for (final quickAnswer in [true, false]) {
    testWidgets(
        'background invite resumes with a usable entry, quick=$quickAnswer',
        (tester) async {
      OpenIM.iMManager.userID = 'bob';
      await tester.runAsync(() async {
        await SpUtil()
            .putBool('99chat_settings_bob_notify_quick_answer', quickAnswer);
        await SpUtil()
            .putBool('99chat_settings_bob_call_ringtone_enabled', false);
      });
      live.preferences = CallNotificationPreferences.read;
      final navigator = GlobalKey<NavigatorState>();
      Get.addKey(navigator);
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('existing conversation')),
        ),
      ));
      await tester.pump();
      live.receiveNewInvitation(_signal());
      live.receiveNewInvitation(_signal());
      await tester.pump();
      expect(OpenIMLiveClient().isBusy, isFalse);
      expect(live.isBusy, isTrue);
      live.backgroundSubject.add(false);
      await tester.pump();
      expect(OpenIMLiveClient().isBusy, isTrue);
      await tester.pump();
      expect(find.byType(IncomingCallQuickAnswerSheet),
          quickAnswer ? findsOneWidget : findsNothing);
      expect(find.byType(ControlsView),
          quickAnswer ? findsNothing : findsOneWidget);
      expect(player.starts, 0);
      live.invitationCancelled(_signal());
      await tester.pumpAndSettle();
      var ended = false;
      final ending = live.endLiveSession(notifyPeer: false).then((_) {
        ended = true;
      });
      // SDK subscriptions predate testWidgets' fake clock, while mounted room
      // cleanup uses it. Drain both zones without awaiting one behind the other.
      for (var cycle = 0; cycle < 4 && !ended; cycle++) {
        await tester.pump();
        await tester.runAsync(flushWaitingToneTasks);
      }
      expect(ended, isTrue, reason: 'Native cleanup must complete before exit');
      await ending;
      await tester.pumpWidget(const SizedBox());
      expect(live.isBusy, isFalse);
    });
  }

  test('a preference refresh cannot restart ringing after pickup starts',
      () async {
    OpenIM.iMManager.userID = 'bob';
    live.preferences = CallNotificationPreferences.read;
    live.receiveNewInvitation(_signal());
    await flushWaitingToneTasks();
    expect(player.starts, 1);
    certificates.gate = Completer<void>();
    final pickup = live.onTapPickup(_signal());
    await flushWaitingToneTasks();
    expect(player.playback.single.isCompleted, isTrue);
    await SpUtil().putBool('99chat_settings_bob_call_ringtone_enabled', false);
    live.refreshIncomingCallPreferences();
    await SpUtil().putBool('99chat_settings_bob_call_ringtone_enabled', true);
    live.refreshIncomingCallPreferences();
    certificates.gate!.complete();
    await pickup;
    live.refreshIncomingCallPreferences();
    await flushWaitingToneTasks();
    expect(player.starts, 1);
  });
}
