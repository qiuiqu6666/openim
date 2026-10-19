import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import '../widgets/settings_widgets.dart';
import 'diagnostic_logging_controller.dart';

class DiagnosticLoggingPage extends StatefulWidget {
  const DiagnosticLoggingPage({super.key, this.controller});
  final DiagnosticLoggingController? controller;

  @override
  State<DiagnosticLoggingPage> createState() => _DiagnosticLoggingPageState();
}

class _DiagnosticLoggingPageState extends State<DiagnosticLoggingPage>
    with WidgetsBindingObserver {
  late final DiagnosticLoggingController _controller;

  @override
  void initState() {
    super.initState();
    final manager = OpenIM.iMManager.diagnosticLoggingManager;
    _controller = widget.controller ??
        DiagnosticLoggingController(
            read: manager.remainingSeconds, write: manager.setDuration);
    WidgetsBinding.instance.addObserver(this);
    _controller.refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.setActive(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      _controller.setActive(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final seconds = _controller.remaining ?? 0;
          final status = _controller.failed
              ? settingsText(context, zh: '状态暂时无法确认', en: 'Status unavailable')
              : _controller.busy
                  ? settingsText(context, zh: '正在确认…', en: 'Checking…')
                  : seconds > 0
                      ? settingsText(context,
                          zh: '详细诊断已开启，约 ${(seconds / 60).ceil()} 分钟后自动关闭',
                          en: 'Detailed diagnostics on · about ${(seconds / 60).ceil()} min remaining')
                      : settingsText(context, zh: '精简模式', en: 'Compact mode');
          return SettingsScaffold(
            title: settingsText(context, zh: '日志诊断', en: 'Log Diagnostics'),
            children: [
              SettingsGroup(children: [
                MergeSemantics(
                    child: SettingsSwitchCell(
                  title: settingsText(context,
                      zh: '临时详细诊断', en: 'Temporary Diagnostics'),
                  subtitle: status,
                  value: seconds > 0,
                  enabled: !_controller.busy &&
                      !_controller.failed &&
                      _controller.remaining != null,
                  onChanged: _controller.setEnabled,
                  showDivider: false,
                )),
              ]),
              SettingsSectionText(settingsText(context,
                  zh: '平时只记录关键运行信息。遇到问题时，可开启 10 分钟详细诊断，重现问题后再通过意见反馈上传日志。也可以随时关闭。',
                  en: 'Normally, only key events are recorded. Enable detailed diagnostics for 10 minutes, reproduce the issue, then upload logs through Feedback. You can turn it off at any time.')),
              SettingsSectionText(settingsText(context,
                  zh: '开启此开关不会自动上传日志。应用进程重新启动后，恢复精简模式。',
                  en: 'This switch does not upload logs. A fresh app process starts in compact mode.')),
              if (_controller.failed) ...[
                SettingsSectionText(settingsText(context,
                    zh: '无法读取或更新诊断状态，请重试。若仍失败，请确认已安装最新版本。',
                    en: 'Could not read or update diagnostics. Retry, or check that the latest app version is installed.')),
                SettingsPrimaryButton(
                  text: settingsText(context, zh: '重试', en: 'Retry'),
                  loading: _controller.busy,
                  onPressed: _controller.refresh,
                ),
              ],
            ],
          );
        },
      );
}
