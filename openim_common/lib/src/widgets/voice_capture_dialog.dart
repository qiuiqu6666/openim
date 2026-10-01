import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:openim_common/openim_common.dart';

class VoiceCaptureDialog extends StatefulWidget {
  const VoiceCaptureDialog({super.key});
  @override
  State<VoiceCaptureDialog> createState() => _VoiceCaptureDialogState();
}

class _VoiceCaptureDialogState extends State<VoiceCaptureDialog>
    with WidgetsBindingObserver {
  final recorder = AudioRecorder();
  final player = AudioPlayer();
  final watch = Stopwatch();
  Timer? timer;
  String? path;
  bool recording = false, busy = false, accepted = false;
  Future<void> start() async {
    setState(() => busy = true);
    try {
      if (!await recorder.hasPermission()) {
        throw StateError('microphone');
      }
      final dir = Directory('${Config.cachePath}/outgoing_media');
      await dir.create(recursive: true);
      path = '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await recorder.start(const RecordConfig(), path: path!);
      watch.start();
      if (!mounted) {
        await recorder.cancel();
        return;
      }
      setState(() => recording = true);
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (watch.elapsed.inSeconds >= 60) {
          stop();
        } else if (mounted) {
          setState(() {});
        }
      });
    } catch (_) {
      if (mounted) IMViews.showToast(StrRes.voiceCaptureFailed);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> stop() async {
    if (busy || !recording) return;
    setState(() => busy = true);
    timer?.cancel();
    watch.stop();
    try {
      path = await recorder.stop();
    } catch (_) {
      path = null;
    }
    if (mounted)
      setState(() {
        recording = false;
        busy = false;
      });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && recording) stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    player.dispose();
    recorder.dispose().then((_) async {
      if (!accepted && path != null) {
        final file = File(path!);
        if (await file.exists()) await file.delete();
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(StrRes.voiceCapture),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${watch.elapsed.inSeconds}s / 60s'),
          if (path == null && !recording)
            TextButton(
                onPressed: busy ? null : start, child: Text(StrRes.voiceStart)),
          if (recording)
            TextButton(
                onPressed: busy ? null : stop, child: Text(StrRes.voiceStop)),
          if (path != null && !recording && !busy)
            TextButton(
                onPressed: () async {
                  try {
                    await player.setFilePath(path!);
                    if (mounted) await player.play();
                  } catch (_) {
                    if (mounted) IMViews.showToast(StrRes.voiceCaptureFailed);
                  }
                },
                child: Text(StrRes.voicePreview)),
        ]),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: Text(StrRes.cancel)),
          TextButton(
              onPressed: busy ||
                      recording ||
                      path == null ||
                      watch.elapsedMilliseconds < 1000
                  ? null
                  : () {
                      accepted = true;
                      Navigator.pop(context, {
                        'path': path!,
                        'duration': (watch.elapsedMilliseconds / 1000).ceil()
                      });
                    },
              child: Text(StrRes.send)),
        ],
      ));
}
