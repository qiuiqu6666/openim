import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../im_callback.dart';

/// The navigation title represents API reachability and SDK transport only.
class ConnectionHealthTitle extends StatelessWidget {
  const ConnectionHealthTitle(
      {super.key,
      required this.title,
      required this.connection,
      this.apiAvailable,
      this.keyPrefix = 'main-tab-title'});

  final String title;
  final IMSdkStatus? connection;
  final ValueListenable<bool?>? apiAvailable;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    Widget render(bool? api) {
      final failed = api == false || connection == IMSdkStatus.connectionFailed;
      final checking = !failed &&
          (api == null ||
              connection == null ||
              connection == IMSdkStatus.connecting);
      final chinese = Localizations.localeOf(context).languageCode == 'zh';
      return MainTabTitle(
          title: title,
          keyPrefix: keyPrefix,
          busy: checking,
          busyLabel: StrRes.connecting,
          failed: failed,
          failureLabel: api == false
              ? (chinese ? '服务连接异常' : 'Service unavailable')
              : StrRes.connectionFailed);
    }

    final source = apiAvailable;
    if (source == null) return render(true);
    return ValueListenableBuilder<bool?>(
        valueListenable: source, builder: (context, value, _) => render(value));
  }
}
