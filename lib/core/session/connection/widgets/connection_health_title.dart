import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../im_callback.dart';
import 'connection_latency_badge.dart';

/// The navigation title represents API reachability and SDK transport only.
class ConnectionHealthTitle extends StatelessWidget {
  const ConnectionHealthTitle(
      {super.key,
      required this.title,
      required this.connection,
      this.apiAvailable,
      this.recovering,
      this.connectionVerified,
      this.latencyMs,
      this.routeMarker,
      this.keyPrefix = 'main-tab-title'});

  final String title;
  final IMSdkStatus? connection;
  final ValueListenable<bool?>? apiAvailable;
  final ValueListenable<bool>? recovering;
  final ValueListenable<bool>? connectionVerified;
  final ValueListenable<int?>? latencyMs;
  final String? Function()? routeMarker;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    Widget render(bool? api, bool recovering, bool verified) {
      final failed = api == false || connection == IMSdkStatus.connectionFailed;
      final checking = !failed &&
          (!verified ||
              recovering ||
              api == null ||
              connection != IMSdkStatus.connectionSucceeded);
      final chinese = Localizations.localeOf(context).languageCode == 'zh';
      final heading = MainTabTitle(
          title: title,
          keyPrefix: keyPrefix,
          busy: latencyMs == null && checking,
          busyLabel: StrRes.connecting,
          failed: latencyMs == null && failed,
          failureLabel: api == false
              ? (chinese ? '服务连接异常' : 'Service unavailable')
              : StrRes.connectionFailed);
      final latency = latencyMs;
      if (latency == null) return heading;
      return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(flex: 2, child: heading),
            const SizedBox(width: AppTokens.s3),
            Flexible(
                flex: 3,
                child: ValueListenableBuilder<int?>(
                  valueListenable: latency,
                  builder: (context, value, _) {
                    final marker = routeMarker?.call();
                    return Transform.translate(
                      offset: const Offset(0, AppTokens.s2),
                      child: ConnectionLatencyBadge(
                        latencyMs: value,
                        failed: failed,
                        checking: checking,
                        marker: marker,
                        textKey: ValueKey('$keyPrefix-latency'),
                      ),
                    );
                  },
                )),
          ]);
    }

    final source = apiAvailable;
    return ValueListenableBuilder<int>(
      valueListenable: Config.networkRouteRevision,
      builder: (context, _, child) {
        Widget withVerification(bool? api, bool recovering) =>
            connectionVerified == null
                ? render(api, recovering, true)
                : ValueListenableBuilder<bool>(
                    valueListenable: connectionVerified!,
                    builder: (context, value, _) =>
                        render(api, recovering, value));
        Widget withRecovery(bool? api) => recovering == null
            ? withVerification(api, false)
            : ValueListenableBuilder<bool>(
                valueListenable: recovering!,
                builder: (context, value, _) => withVerification(api, value));
        return source == null
            ? withRecovery(true)
            : ValueListenableBuilder<bool?>(
                valueListenable: source,
                builder: (context, value, _) => withRecovery(value));
      },
    );
  }
}
