import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/network/transport_state.dart';

void main() {
  test('stale OS reads cannot overwrite a new transport event or resume',
      () async {
    final state = NetworkTransportState();
    final stale = Completer<List<ConnectivityResult>>();
    final reading = state.refresh(() => stale.future);
    state.update([ConnectivityResult.mobile]);
    stale.complete([ConnectivityResult.none]);
    expect(await reading, false);
    expect(state.online, true);

    final backgroundRead = Completer<List<ConnectivityResult>>();
    final old = state.refresh(() => backgroundRead.future);
    state.invalidateSnapshot();
    expect(await state.refresh(() async => [ConnectivityResult.wifi]), true);
    backgroundRead.complete([ConnectivityResult.none]);
    expect(await old, false);
    expect(state.online, true);
  });
  test('unknown and equivalent snapshots cannot cause reconnect storms', () {
    final state = NetworkTransportState();
    expect(state.update([]), false);
    expect(state.online, true);
    expect(
        state.update([ConnectivityResult.wifi, ConnectivityResult.vpn]), true);
    expect(
        state.update([
          ConnectivityResult.vpn,
          ConnectivityResult.wifi,
          ConnectivityResult.none,
          ConnectivityResult.wifi
        ]),
        false);
    expect(state.update([]), false);
    expect(state.online, true);
    expect(state.update([ConnectivityResult.none]), true);
    expect(state.online, false);
    expect(state.update([]), false);
    expect(state.online, false);
    expect(state.update([ConnectivityResult.none]), false);
    expect(state.update([ConnectivityResult.mobile]), true);
    expect(state.online, true);
  });
}
