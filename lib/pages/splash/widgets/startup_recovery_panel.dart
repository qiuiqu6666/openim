import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/localization.dart';
import '../../../core/server_nodes/startup/startup_network_preparation.dart';
import '../../../core/server_nodes/startup/startup_state.dart';

/// Inline recovery, not a modal: preserves the launch artwork and system back.
class StartupRecoveryPanel extends StatelessWidget {
  const StartupRecoveryPanel({super.key, required this.network});
  final StartupNetworkPreparation network;

  String _copy(String zh, String en) =>
      Get.locale?.languageCode == 'en' ? en : AppCopy.text(zh);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<StartupState>(
      valueListenable: network.state,
      builder: (context, state, _) {
        if (!state.showDetails ||
            (network.ready &&
                !network.sdkRecoveryVisible &&
                !network.loginRecoveryVisible)) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        final unavailable = state.stage == StartupStage.unavailable;
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTokens.s7),
              child: Material(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppTokens.rMd),
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.s5),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Semantics(
                        liveRegion: true,
                        child: Text(
                            network.sdkRecoveryVisible
                                ? _copy('聊天服务初始化未完成，请重试',
                                    'Chat service initialization is incomplete. Please retry.')
                                : unavailable
                                    ? _copy('暂时无法连接，网络恢复后将自动重试',
                                        'Unable to connect. We will retry automatically when the network recovers.')
                                    : _copy('正在连接…', 'Connecting…'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium)),
                    if (network.sdkRecoveryVisible && state.showActions) ...[
                      const SizedBox(height: AppTokens.s3),
                      Wrap(
                          alignment: WrapAlignment.center,
                          spacing: AppTokens.s3,
                          runSpacing: AppTokens.s3,
                          children: [
                            TextButton(
                                onPressed: () => network.retry(),
                                child: Text(_copy('重试', 'Retry')))
                          ]),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        );
      });
}
