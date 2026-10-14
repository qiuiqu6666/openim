import 'dart:async';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/core/calling/data/call_state_runtime.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/calling/data/call_backend_api.dart';
import 'package:openim/core/calling/ios/ios_call_invitation.dart';
import 'package:openim/core/calling/ios/ios_voip_backend.dart';
import 'package:openim/core/push/apns/apns_platform.dart';

class FakeCallApi extends CallBackendApi {
  FakeCallApi()
      : super(
            accountID: 'callee',
            token: 'captured-session',
            deviceID: 'device_one',
            baseUrl: Config.callingUrl);
  int queries = 0;
  final actions = <String>[];
  final bindings = <String>[];
  Completer<void>? bindingGate;
  Completer<Map<String, dynamic>>? statusGate;
  Map<String, dynamic> value = {
    'state': 'ringing',
    'recipientUserID': 'callee',
    'callerName': '来电昵称',
    'invitation': {
      'roomID': 'room_1234',
      'inviterUserID': 'caller',
      'inviteeUserIDList': ['callee'],
      'mediaType': 'audio',
      'sessionType': 1,
      'initiateTime': DateTime.now().millisecondsSinceEpoch,
      'timeout': 30
    },
  };
  @override
  Future<Map<String, dynamic>> status(String room) async {
    queries++;
    return statusGate?.future ?? Map.of(value);
  }

  @override
  Future<void> bind(APNsDeviceToken token) async {
    bindings.add('binding');
    await bindingGate?.future;
    bindings.add('bound');
  }

  @override
  Future<void> unbind() async {
    bindings.add('unbound');
  }

  @override
  Future<Map<String, dynamic>> request(String path, Map<String, dynamic> body,
      {bool allowStale = false}) async {
    expect(path, 'action');
    actions.add(body['action'] as String);
    return {...value, 'state': 'rejected'};
  }
}

Future<void> flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeCallApi api;
  late CallStateRuntime runtime;
  late IOSVoIPBackend backend;
  late List<IOSCallInvitation> restored;
  late List<String> ended, names;
  late bool current;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'callee',
      'chatToken': 'captured-session',
      'imToken': 'im',
    }));
    api = FakeCallApi();
    runtime = CallStateRuntime(createApi: () async => api)..activate();
    restored = [];
    ended = [];
    names = [];
    current = true;
    backend = IOSVoIPBackend(
        createApi: () async => api,
        runtime: runtime,
        restore: (v) {
          restored.add(v);
          return true;
        },
        endRemote: (room) async {
          ended.add(room);
        },
        updateName: (room, name) async {
          names.add(name);
        },
        isSessionCurrent: () => current,
        pollInterval: const Duration(milliseconds: 20));
    await backend.start('callee');
  });
  tearDown(() async {
    await backend.stop(logout: false);
    runtime.close();
  });

  test('cold recovery requires server invitation and retains nickname',
      () async {
    expect(await backend.recover('room_1234'), isTrue);
    expect(restored.single.invitation.inviterUserID, 'caller');
    expect(restored.single.callerName, '来电昵称');
    expect(names, ['来电昵称']);
    expect(ended, isEmpty);
  });
  test('cancelled, expired and already answered calls are never restored',
      () async {
    for (final state in ['cancelled', 'expired', 'accepted']) {
      runtime.reset();
      runtime.activate();
      api.value['state'] = state;
      api.value['answeredDeviceID'] = 'device_two';
      expect(await backend.recover('room_1234'), isFalse);
    }
    expect(restored, isEmpty);
    expect(ended.length, 3);
  });
  test('wrong recipient or room cannot be recovered from server payload',
      () async {
    api.value['recipientUserID'] = 'other';
    expect(await backend.recover('room_1234'), isFalse);
    api.value['recipientUserID'] = 'callee';
    expect(await backend.recover('room_other'), isFalse);
    expect(restored, isEmpty);
  });
  test('overlapping push and answer recovery share one query', () async {
    api.statusGate = Completer();
    final one = backend.recover('room_1234'),
        two = backend.recover('room_1234');
    api.statusGate!.complete(api.value);
    expect(await one, isTrue);
    expect(await two, isTrue);
    expect(api.queries, 1);
    expect(restored.length, 1);
  });
  test('logout during status lookup cannot restore previous account call',
      () async {
    api.statusGate = Completer();
    final pending = backend.recover('room_1234');
    current = false;
    await backend.stop(logout: true);
    api.statusGate!.complete(api.value);
    expect(await pending, isFalse);
    expect(restored, isEmpty);
    expect(ended, isEmpty);
  });
  test('native rejection fences an in-flight recovery', () async {
    api.statusGate = Completer();
    final pending = backend.recover('room_1234');
    final rejecting = backend.rejectCold('room_1234');
    api.statusGate!.complete(api.value);
    await rejecting;
    expect(await pending, isFalse);
    expect(restored, isEmpty);
    expect(api.actions, ['reject']);
  });
  test('logout unbinds after a pending registration completes', () async {
    api.bindingGate = Completer();
    backend.bind(APNsDeviceToken(
        token: 'ab' * 32,
        bundleID: 'vip.99chat.ios',
        environment: 'production'));
    await flush();
    final stopping = backend.stop(logout: true);
    await flush();
    expect(api.bindings, ['binding']);
    api.bindingGate!.complete();
    await stopping;
    expect(api.bindings, ['binding', 'bound', 'unbound']);
  });
  test('logout upgrades pending SDK pause and still unbinds', () async {
    api.bindingGate = Completer();
    backend.bind(APNsDeviceToken(
        token: 'ab' * 32,
        bundleID: 'vip.99chat.ios',
        environment: 'production'));
    await flush();
    final pause = backend.stop(logout: false);
    final logout = backend.stop(logout: true);
    api.bindingGate!.complete();
    await Future.wait([pause, logout]);
    expect(api.bindings, ['binding', 'bound', 'unbound']);
  });

  test('logout after completed SDK pause uses captured old credential',
      () async {
    await backend.stop(logout: false);
    await backend.stop(logout: true);
    expect(api.bindings, ['unbound']);
  });

  test('other device acceptance closes this system ringing surface', () async {
    runtime.onState = (state, device) async {
      if (state.terminal || state.answeredElsewhere(api.accountID, device)) {
        await backend.endRemote(state.room);
      }
    };
    backend.monitor('room_1234', incoming: true);
    api.value['state'] = 'accepted';
    api.value['answeredDeviceID'] = 'device_two';
    await runtime.status('room_1234');
    await flush();
    expect(ended, ['room_1234']);
    expect(restored, isEmpty);
  });
  test('server cancellation closes an admitted incoming call', () async {
    expect(await backend.recover('room_1234'), isTrue);
    runtime.onState = (state, device) async {
      if (state.terminal) await backend.endRemote(state.room);
    };
    api.value['state'] = 'cancelled';
    await runtime.status('room_1234');
    await flush();
    expect(ended, ['room_1234']);
  });
}
