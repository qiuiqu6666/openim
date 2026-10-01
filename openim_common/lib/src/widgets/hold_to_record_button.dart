import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:openim_common/openim_common.dart';
import 'package:voice_note_kit/voice_note_kit.dart';
import 'package:voice_note_kit/recorder/voice_enums/voice_enums.dart';

class HoldToRecordButton extends StatefulWidget {
  const HoldToRecordButton(
      {super.key, required this.onRecorded, this.enabled = true});
  final Future<void> Function(String path, int seconds) onRecorded;
  final bool enabled;
  @override
  State<HoldToRecordButton> createState() => _HoldToRecordButtonState();
}

class _HoldToRecordButtonState extends State<HoldToRecordButton>
    with WidgetsBindingObserver {
  bool busy = false;
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Unmount the recorder when backgrounded, cancelling any active recording.
    if (mounted)
      setState(() => foreground = state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> recorded(File file) async {
    if (busy) return;
    setState(() => busy = true);
    final player = AudioPlayer();
    try {
      final duration = await player.setFilePath(file.path);
      if (duration == null || duration.inMilliseconds < 1000) {
        IMViews.showToast('录音时间太短');
        return;
      }
      if (!mounted || !foreground || !widget.enabled) return;
      final directory = Directory('${Config.cachePath}/outgoing_media');
      await directory.create(recursive: true);
      final saved = await file.copy(
          '${directory.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a');
      if (!mounted || !foreground || !widget.enabled) {
        await saved.delete();
        return;
      }
      await widget.onRecorded(
          saved.path, (duration.inMilliseconds / 1000).ceil().clamp(1, 60));
    } catch (_) {
      if (mounted) IMViews.showToast(StrRes.voiceCaptureFailed);
    } finally {
      await player.dispose();
      if (await file.exists()) await file.delete();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!foreground || !widget.enabled) return const SizedBox.shrink();
    return IgnorePointer(
        ignoring: busy,
        child: VoiceRecorderWidget(
          style: VoiceUIStyle.compact,
          idleText: busy ? '正在发送…' : '按住说话',
          borderRadius: 8,
          onRecorded: recorded,
          onError: (_) => IMViews.showToast(StrRes.voiceCaptureFailed),
          actionWhenCancel: () {},
          maxRecordDuration: const Duration(seconds: 60),
          permissionNotGrantedMessage: '请允许使用麦克风',
          recordCancelledMessage: '已取消录音',
          cancelDoneText: '已取消',
          dragToLeftText: '左滑取消，松开发送',
          iconSize: 22,
          timerFontSize: 12,
          backgroundColor: Styles.c_0089FF,
          iconColor: Styles.c_0089FF,
          containerColor: Styles.c_FFFFFF,
          borderColor: Colors.transparent,
          cancelHintColor: Styles.c_FF381F,
          idleWavesColor: Styles.c_8E9AB0,
          recordingWavesColor: Styles.c_0089FF,
          timerTextStyle: TextStyle(color: Styles.c_0C1C33, fontSize: 12),
          dragToLeftTextStyle: TextStyle(color: Styles.c_0C1C33, fontSize: 14),
        ));
  }
}
