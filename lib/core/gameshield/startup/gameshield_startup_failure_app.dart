import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart' show Config;
import '../../../theme/app_theme_data.dart';

/// A failed protected startup never mounts ChatApp or creates its SDK owners.
class GameShieldStartupFailureApp extends StatefulWidget {
  const GameShieldStartupFailureApp({super.key, required this.onRetry});
  final Future<void> Function() onRetry;
  @override
  State<GameShieldStartupFailureApp> createState() => _FailureState();
}

class _FailureState extends State<GameShieldStartupFailureApp> {
  bool _retrying = false;
  Future<void> _retry() async {
    if (_retrying) return;
    setState(() {
      _retrying = true;
    });
    try {
      await widget.onRetry();
    } finally {
      if (mounted) {
        setState(() {
          _retrying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ScreenUtilInit(
      designSize: const Size(Config.uiW, Config.uiH),
      builder: (_, __) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppThemeData(Brightness.light),
            darkTheme: buildAppThemeData(Brightness.dark),
            home: Builder(builder: (context) {
              final english = WidgetsBinding
                      .instance.platformDispatcher.locale.languageCode !=
                  'zh';
              final text = Theme.of(context).textTheme;
              return Scaffold(
                  body: SafeArea(
                      child: Center(
                          child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(english ? 'Unable to connect' : '暂时无法连接',
                          style: text.headlineSmall,
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      Text(
                          english
                              ? 'Check your network and try again.'
                              : '请检查网络后重试。',
                          style: text.bodyLarge,
                          textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      FilledButton(
                          onPressed: _retrying ? null : _retry,
                          child: Text(english
                              ? (_retrying ? 'Connecting…' : 'Retry')
                              : (_retrying ? '连接中…' : '重试'))),
                    ])),
              ))));
            }),
          ));
}
