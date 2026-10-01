import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide Config;
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:open_filex/open_filex.dart';
import 'package:openim_common/openim_common.dart';

class ChatFileMessageView extends StatefulWidget {
  const ChatFileMessageView({super.key, required this.message});
  final Message message;
  @override
  State<ChatFileMessageView> createState() => _ChatFileMessageViewState();
}

class _ChatFileMessageViewState extends State<ChatFileMessageView> {
  bool _busy = false;
  bool _failed = false;
  bool _downloaded = false;
  double? _progress;
  File? _cachedFile;

  @override
  void initState() {
    super.initState();
    _checkLocalFile();
  }

  Future<void> _checkLocalFile() async {
    final path = widget.message.fileElem?.filePath;
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists() && mounted) {
      setState(() {
        _cachedFile = file;
        _downloaded = true;
      });
    }
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
      _progress = null;
    });
    try {
      final element = widget.message.fileElem!;
      File? file;
      bool fromCache = false;
      final path = _cachedFile?.path ?? element.filePath;
      if (path != null && path.isNotEmpty && await File(path).exists()) {
        file = File(path);
      } else {
        fromCache = true;
        final url = element.sourceUrl;
        if (url == null || url.isEmpty) throw StateError('Missing file URL');
        await for (final event
            in DefaultCacheManager().getFileStream(url, withProgress: true)) {
          if (!mounted) return;
          if (event is DownloadProgress) {
            setState(() => _progress = event.progress);
          }
          if (event is FileInfo) file = event.file;
        }
      }
      if (!mounted) return;
      if (file == null) throw StateError('Missing downloaded file');
      final name = element.fileName ?? '';
      // Cache URLs may have no extension; retain the platform file association.
      final extension =
          RegExp(r'\.([a-zA-Z0-9]{1,12})$').firstMatch(name)?.group(0);
      if (fromCache && extension != null && !file.path.endsWith(extension)) {
        file = await file.copy('${file.path}$extension');
      }
      if (!mounted) return;
      setState(() {
        _cachedFile = file;
        _downloaded = true;
      });
      final result = await OpenFilex.open(file.path,
          type: extension == null ? null : IMUtils.getMediaType(name));
      if (result.type != ResultType.done) throw StateError(result.message);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.message.fileElem!;
    final bytes = file.fileSize ?? 0;
    final size = bytes < 1024
        ? '$bytes B'
        : bytes < 1048576
            ? '${(bytes / 1024).toStringAsFixed(1)} KB'
            : '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return GestureDetector(
      onTap: _open,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
          width: 200.w,
          child: Row(children: [
            ChatAttachmentIcon(
                size: 32.w,
                child: Icon(Icons.insert_drive_file_outlined,
                    size: 20.w, color: Styles.c_0089FF)),
            8.horizontalSpace,
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(file.fileName ?? 'attachmentFile'.tr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Styles.ts_0C1C33_17sp.copyWith(
                          fontSize: 14.sp, fontWeight: FontWeight.w500)),
                  3.verticalSpace,
                  Wrap(spacing: 8.w, runSpacing: 2.h, children: [
                    Text(size, style: Styles.ts_8E9AB0_12sp.copyWith(fontSize: 11.sp)),
                    Text(
                        _busy
                            ? (_progress == null
                                ? 'attachmentLoading'.tr
                                : '${(_progress! * 100).round()}%')
                            : _failed
                                ? 'attachmentRetry'.tr
                                : _downloaded
                                    ? 'attachmentOpen'.tr
                                    : 'attachmentDownload'.tr,
                        style: Styles.ts_8E9AB0_12sp.copyWith(
                            fontSize: 11.sp,
                            color:
                                _failed ? Styles.c_FF381F : Styles.c_0089FF)),
                  ]),
                ])),
          ])),
    );
  }
}

class ChatVoiceMessageView extends StatefulWidget {
  const ChatVoiceMessageView(
      {super.key,
      required this.message,
      required this.isOutgoing,
      this.onPlayed,
      this.playback});
  final Message message;
  final bool isOutgoing;
  final Future<void> Function()? onPlayed;
  final VoicePlaybackController? playback;
  @override
  State<ChatVoiceMessageView> createState() => _ChatVoiceMessageViewState();
}

class _ChatVoiceMessageViewState extends State<ChatVoiceMessageView> {
  late VoicePlaybackController _playback;
  bool _heard = false;
  bool get _current =>
      _playback.current?.clientMsgID == widget.message.clientMsgID;
  bool get _loading => _current && _playback.loading;
  bool get _playing => _current && _playback.playing;
  bool get _failed => _current && _playback.failed;

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (_playing) _heard = true;
    });
  }

  List<double> _waveform = const [];
  static final Map<String, Future<List<double>>> _waveJobs = {};

  Future<void> _prepareWaveform() async {
    final sound = widget.message.soundElem;
    final key = widget.message.clientMsgID;
    if (sound == null || key == null) return;
    try {
      final job = _waveJobs.putIfAbsent(key, () async {
        final directory = Directory('${Config.cachePath}/voice_waveforms');
        await directory.create(recursive: true);
        final name = base64Url.encode(utf8.encode(key));
        final cache = File('${directory.path}/$name.json');
        if (await cache.exists()) {
          try {
            final values = (jsonDecode(await cache.readAsString()) as List)
                .map((v) => (v as num).toDouble())
                .toList();
            if (values.length == 16) return values;
          } catch (_) {}
        }
        final local = sound.soundPath;
        final File audio;
        if (local != null && local.isNotEmpty && await File(local).exists()) {
          audio = File(local);
        } else {
          final url = sound.sourceUrl;
          if (url == null || url.isEmpty) return <double>[];
          audio = await DefaultCacheManager().getSingleFile(url);
        }
        final output = File('${directory.path}/$name.wave');
        try {
          final result = await JustWaveform.extract(
                  audioInFile: audio, waveOutFile: output)
              .last;
          final samples = result.waveform?.data;
          if (samples == null || samples.isEmpty) return <double>[];
          final peaks = List.generate(16, (i) {
            final start = i * samples.length ~/ 16;
            final end = math.max(start + 1, (i + 1) * samples.length ~/ 16);
            var peak = 0.0;
            for (var j = start; j < end && j < samples.length; j++) {
              peak = math.max(peak, samples[j].abs().toDouble());
            }
            return peak;
          });
          final maxPeak = peaks.reduce(math.max);
          final normalized =
              peaks.map((v) => maxPeak == 0 ? 0.0 : v / maxPeak).toList();
          await cache.writeAsString(jsonEncode(normalized));
          return normalized;
        } finally {
          if (await output.exists()) await output.delete();
        }
      });
      final values = await job;
      if (mounted) setState(() => _waveform = values);
    } catch (_) {
      // Keep a neutral placeholder if extraction is unavailable; never invent peaks.
    } finally {
      _waveJobs.remove(key);
    }
  }

  @override
  void initState() {
    super.initState();
    _playback = widget.playback ??
        VoicePlaybackController(
          messages: () => [widget.message],
          onPlayed: (_) async {
            await widget.onPlayed?.call();
          },
        );
    _playback.addListener(_changed);
    try {
      _heard = jsonDecode(widget.message.localEx ?? '{}')['voiceHeard'] == true;
    } catch (_) {}
    unawaited(_prepareWaveform());
  }

  @override
  void dispose() {
    _playback.removeListener(_changed);
    if (widget.playback == null) _playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.message.soundElem?.duration ?? 0;
    // Match the reference width; the parent still constrains narrow screens.
    final bubbleContentWidth = 128.w;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _playback.toggle(widget.message),
      child: Semantics(
        button: true,
        label: _playing ? 'attachmentPause'.tr : 'attachmentPlay'.tr,
        child: SizedBox(
            width: bubbleContentWidth,
            child: Row(children: [
              Container(
                width: 24.w,
                height: 24.w,
                decoration: BoxDecoration(
                    color: Styles.c_0089FF, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: _loading
                    ? SizedBox(
                        width: 18.w,
                        height: 18.w,
                        child: const CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(
                        _failed
                            ? Icons.refresh_rounded
                            : _playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 18.w),
              ),
              6.horizontalSpace,
              Expanded(
                  child: StreamBuilder<Duration>(
                stream: _current ? _playback.positionStream : null,
                builder: (_, snapshot) => CustomPaint(
                  size: Size(double.infinity, 18.w),
                  painter: _VoiceWavePainter(
                    levels: _waveform,
                    color: Styles.c_8E9AB0,
                    playedColor: Styles.c_0089FF,
                    progress: _playing && duration > 0
                        ? ((snapshot.data?.inMilliseconds ?? 0) /
                                (duration * 1000))
                            .clamp(0.0, 1.0)
                        : 0,
                  ),
                ),
              )),
              6.horizontalSpace,
              Text('$duration″',
                  style: Styles.ts_0C1C33_17sp.copyWith(fontSize: 12.sp, fontWeight: FontWeight.w500)),
              if (!widget.isOutgoing && !_heard) ...[
                const SizedBox(width: 6),
                Icon(Icons.circle, size: 6, color: Styles.c_0089FF),
              ],
            ])),
      ),
    );
  }
}

class _VoiceWavePainter extends CustomPainter {
  const _VoiceWavePainter(
      {required this.levels,
      required this.color,
      required this.playedColor,
      required this.progress});
  final List<double> levels;
  final Color color;
  final Color playedColor;
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) {
      canvas.drawLine(
          Offset(0, size.height / 2),
          Offset(size.width, size.height / 2),
          Paint()
            ..color = color.withValues(alpha: .35)
            ..strokeWidth = 1);
      return;
    }
    final step = size.width / levels.length;
    final paint = Paint()
      ..strokeWidth = math.min(2.0.w, step * .4)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < levels.length; i++) {
      paint.color = (i + .5) / levels.length <= progress ? playedColor : color;
      final height = math.max(0.0, size.height * levels[i] - paint.strokeWidth);
      final x = step * (i + .5);
      canvas.drawLine(Offset(x, (size.height - height) / 2),
          Offset(x, (size.height + height) / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWavePainter old) =>
      old.levels != levels ||
      old.color != color ||
      old.playedColor != playedColor ||
      old.progress != progress;
}
