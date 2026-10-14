import 'package:flutter/foundation.dart';

import '../server_nodes/node_availability_probe.dart';
import '../server_nodes/node_endpoint.dart';

/// Local listeners can be ready while native TCP/HELLO is still in flight.
/// Allow two 6-second dial attempts and a response, without delaying success.
class ShieldReadiness {
  static const timeout = Duration(seconds: 15);

  static Future<void> verify({NodeAvailabilityProbe? probe}) async {
    final result = await (probe ?? NodeAvailabilityProbe(timeout: timeout))
        .check(NodeEndpoint.shield);
    if (!result.available) {
      final details = result.serviceFailures.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join(', ');
      debugPrint('[Youmeng] business_probe_failed '
          '${result.latencyMs}ms $details');
      throw StateError('网络保护业务链路未就绪: $details');
    }
    debugPrint('[Youmeng] business_ready '
        'chat:10008 imApi:10002 imWs:10001 ${result.latencyMs}ms');
  }
}
