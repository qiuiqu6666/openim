import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/server_nodes/manual_node_switch_runtime.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';
import 'package:openim_common/openim_common.dart';

/// Optional diagnostic run: forwards every byte to the actual native SDK.
/// Only failed method names/codes are retained; never arguments or contents.
class LiveSdkReconnectProbe {
  final failures = <Map<String, String>>[];
  static const channel = 'flutter_openim_sdk';
  void attach(TestDefaultBinaryMessenger messenger) {
    const codec = StandardMethodCodec();
    messenger.setMockMessageHandler(channel, (data) async {
      final response = await messenger.delegate.send(channel, data);
      if (response != null &&
          response.lengthInBytes > 0 &&
          response.getUint8(0) == 1) {
        try {
          codec.decodeEnvelope(response);
        } on PlatformException catch (error) {
          final method = codec.decodeMethodCall(data!).method;
          if (failures.length < 200) {
            failures.add({'method': method, 'code': error.code});
          }
        }
      }
      return response;
    });
  }

  Future<void> reconnect() {
    final owner = (DataSp.userID, DataSp.imToken);
    return ManualNodeSwitchRuntime.reconnect(
        NodeEndpoint.current(), () => owner == (DataSp.userID, DataSp.imToken));
  }
}
