import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'package:voice_note_kit/recorder/styles/voice_classic_style.dart';
import 'package:voice_note_kit/recorder/styles/voice_compact_style.dart';
import 'package:voice_note_kit/recorder/utils/utils_for_mobile.dart';
import 'package:voice_note_kit/recorder/utils/utils_for_web.dart';
import 'audio_recorder.dart';
import 'sound_player.dart';
import 'voice_enums/voice_enums.dart';
import 'voice_recorder_controller.dart';

// Main widget for voice recording functionality
class VoiceRecorderWidget extends StatefulWidget {
  /// Optional controller for a custom recorder surface using this widget's
  /// existing permissions, native recorder and temporary-file lifecycle.
  final VoiceRecorderController? controller;

  /// Replaces the default UI and gesture detector. Custom surfaces decide
  /// when to call start, stop or cancel on the supplied controller.
  final Widget Function(BuildContext, VoiceRecorderController)? builder;

  // Callbacks and customizable widgets for the voice recorder widget
  final Function(File file)? onRecorded;
  final Function(String url)? onRecordedWeb;
  final Function(String error)? onError;
  final Function()? onStartRecording;
  final Function()? actionWhenCancel;
  final Function()? onMaxDurationReached;

  // Widgets to customize start and stop recording icons
  final Widget? startRecordingWidget;
  final Widget? stopRecordingWidget;

  // Texts and style options for UI elements
  final String permissionNotGrantedMessage;
  final String recordCancelledMessage;
  final String cancelDoneText;
  final String dragToLeftText;

  final String? idleText;
  final double iconSize;
  final TextStyle? timerTextStyle;
  final TextStyle? dragToLeftTextStyle;

  final double timerFontSize;
  final Color backgroundColor;
  final Color cancelHintColor;
  final Color iconColor;

  final bool showSwipeLeftToCancel;
  final bool showTimerText;

  final bool enableHapticFeedback;

  final Duration? maxRecordDuration;

  // Optionally provided sound assets for starting and stopping recording
  final String? startSoundAsset;
  final String? stopSoundAsset;

  // optional to style show voice record
  final VoiceUIStyle? style;
  final Color? containerColor; // New: optional background color
  final Color? borderColor; // New: optional border color
  final Color? idleWavesColor;
  final Color? recordingWavesColor;
  final double? borderRadius;
  final Duration? wavesSpeed; // New: optional border color

  const VoiceRecorderWidget({
    super.key,
    this.controller,
    this.builder,
    this.onRecorded,
    this.idleText,
    this.onRecordedWeb,
    this.onError,
    this.onStartRecording,
    this.actionWhenCancel,
    this.onMaxDurationReached,
    this.startRecordingWidget,
    this.stopRecordingWidget,
    this.maxRecordDuration,
    this.timerFontSize = 16,
    this.showSwipeLeftToCancel = true,
    this.showTimerText = true,
    this.enableHapticFeedback = true,
    this.backgroundColor = Colors.blueAccent,
    this.cancelHintColor = Colors.redAccent,
    this.iconColor = Colors.white,
    this.timerTextStyle,
    this.dragToLeftTextStyle,
    this.cancelDoneText = 'Cancel Done',
    this.permissionNotGrantedMessage = 'Permission not granted',
    this.recordCancelledMessage = 'Record cancelled',
    this.dragToLeftText = '← Drag to left to cancel',
    this.iconSize = 56,
    this.startSoundAsset,
    this.stopSoundAsset,
    this.style = VoiceUIStyle.classic,
    this.containerColor,
    this.borderColor,
    this.borderRadius,
    this.idleWavesColor = Colors.grey,
    this.recordingWavesColor = Colors.blueAccent,
    this.wavesSpeed,
  });

  @override
  State<VoiceRecorderWidget> createState() => _VoiceRecorderWidgetState();
}

class _VoiceRecorderWidgetState extends State<VoiceRecorderWidget> {
  final _recorder = AudioRecorderClass();
  late VoiceRecorderController _controller;
  bool _ownsController = false;
  bool _isRecording = false;
  bool _isCancelled = false;
  String? _filePath;
  double dragDistance = 0.0;
  Offset? _startOffset;
  Timer? _timer;
  Timer? _preparingTimer;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  int _seconds = 0;
  double _amplitude = 0;
  Color _backgroundColor = Colors.blueAccent;
  bool _showCancelHint = false;
  bool _pressed = false;
  bool _starting = false;
  bool _stopping = false;
  bool _disposing = false;
  int _sessionSequence = 0;
  Future<void>? _startOperation;
  Future<void>? _stopOperation;
  Future<void>? _lateStartCleanup;

  @override
  void initState() {
    super.initState();
    _attachController();
  }

  void _attachController() {
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? VoiceRecorderController();
    _controller.attach(
      owner: this,
      start: _startControlled,
      stop: _stopControlled,
      cancel: _cancelRecording,
    );
    _publishSnapshot();
  }

  @override
  void didUpdateWidget(covariant VoiceRecorderWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _controller.detach(this);
      if (_ownsController) _controller.dispose();
      _attachController();
    }
  }

  void _publishSnapshot() {
    if (_disposing || !mounted) return;
    _controller.updateSnapshot(
      this,
      VoiceRecorderSnapshot(
        isStarting: _starting,
        isRecording: _isRecording,
        isStopping: _stopping,
        seconds: _seconds,
        amplitude: _amplitude,
      ),
    );
  }

  void _refresh() {
    if (_disposing || !mounted) return;
    setState(() {});
    _publishSnapshot();
  }

  void _reportError(Object error) {
    if (!_disposing && mounted) widget.onError?.call(error.toString());
  }

  bool _canStart(int sequence) =>
      !_disposing && mounted && _pressed && sequence == _sessionSequence;

  Future<void> _startControlled() async {
    if (_disposing ||
        _starting ||
        _stopping ||
        _isRecording ||
        _lateStartCleanup != null) {
      return;
    }
    _pressed = true;
    await _startRecording();
  }

  Future<void> _stopControlled() async {
    _pressed = false;
    await _stopRecording();
  }

  @override
  void dispose() {
    _controller.detach(this);
    if (_ownsController) _controller.dispose();
    _disposing = true;
    _pressed = false;
    _isCancelled = true;
    _sessionSequence++;
    _timer?.cancel();
    _preparingTimer?.cancel();
    unawaited(_disposeRecorder());
    super.dispose();
  }

  Future<void> _disposeRecorder() async {
    await _cancelAmplitude();
    // A native start can complete after the widget has left the tree. Wait
    // for its cancellation cleanup before disposing that same recorder.
    await _startOperation;
    await _lateStartCleanup;
    // Once a recording was delivered, the callback owns its file and can be
    // waiting for a review dialog. The native recorder is already stopped.
    if (_filePath != null) await _stopOperation;
    if (_filePath != null) await _discardTemporaryRecording();
    try {
      await _recorder.dispose();
    } catch (_) {
      // Disposal cannot deliver errors or recording callbacks to a dead UI.
    }
  }

  Future<void> _cancelAmplitude() async {
    final subscription = _amplitudeSubscription;
    _amplitudeSubscription = null;
    if (subscription != null) {
      try {
        await subscription.cancel();
      } catch (_) {}
    }
    _amplitude = 0;
  }

  Future<void> _discardTemporaryRecording({
    bool stopNative = true,
    bool reportError = true,
  }) async {
    Object? cleanupError;
    // After delivery the application owns the file. Native cancel can delete
    // it, so discard must be restricted to our still-unclaimed temporary path.
    if (stopNative && _filePath != null) {
      cleanupError = await _recorder.discard();
    }
    final path = _filePath;
    _filePath = null;
    if (!kIsWeb && path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (error) {
        cleanupError ??= error;
      }
    }
    if (reportError && cleanupError != null) _reportError(cleanupError);
  }

  Future<void> _startRecording() async {
    if (_disposing ||
        _starting ||
        _stopping ||
        _isRecording ||
        _lateStartCleanup != null) {
      return;
    }
    final completion = Completer<void>();
    _startOperation = completion.future;
    _starting = true;
    _isCancelled = false;
    _seconds = 0;
    _amplitude = 0;
    final sequence = ++_sessionSequence;
    final preparingWatch = Stopwatch()..start();
    _refresh();
    _preparingTimer = Timer(const Duration(seconds: 15), () {
      if (!_starting || !_canStart(sequence)) return;
      _pressed = false;
      _isCancelled = true;
      _sessionSequence++;
      _reportError(TimeoutException('Recording preparation timed out'));
      _refresh();
    });
    try {
      final hasPermission =
          await _checkPermissions().timeout(const Duration(seconds: 15));
      if (!hasPermission) {
        if (_canStart(sequence)) {
          _reportError(widget.permissionNotGrantedMessage);
        }
        return;
      }
      if (!_canStart(sequence)) return;
      widget.onStartRecording?.call();
      if (widget.enableHapticFeedback) {
        unawaited(HapticFeedback.mediumImpact());
      }
      if (kIsWeb) {
        _filePath = getTempFileForWeb();
      } else {
        _filePath = await getTempFilePath().timeout(const Duration(seconds: 5));
      }
      if (!_canStart(sequence)) {
        await _discardTemporaryRecording(stopNative: false);
        return;
      }
      final nativeStart =
          _recorder.start(const RecordConfig(), path: _filePath!);
      final remaining = const Duration(seconds: 15) - preparingWatch.elapsed;
      try {
        await nativeStart
            .timeout(remaining.isNegative ? Duration.zero : remaining);
      } on TimeoutException catch (error) {
        if (_canStart(sequence)) _reportError(error);
        _pressed = false;
        _isCancelled = true;
        _sessionSequence++;
        // Native calls cannot be interrupted safely. Return the UI to idle,
        // while preventing a new start until the late result has been stopped.
        final cleanup = _cleanUpLateStart(nativeStart);
        _lateStartCleanup = cleanup;
        unawaited(cleanup.whenComplete(() {
          _lateStartCleanup = null;
          _refresh();
        }));
        return;
      }
      if (!_canStart(sequence)) {
        await _discardTemporaryRecording();
        return;
      }
      _isRecording = true;
      _starting = false;
      _preparingTimer?.cancel();
      dragDistance = 0;
      _backgroundColor = widget.cancelHintColor;
      _showCancelHint = true;
      _amplitudeSubscription = _recorder.amplitude.listen((level) {
        if (_disposing || !mounted || !_isRecording) return;
        _amplitude = ((level.current + 60) / 60).clamp(0.0, 1.0).toDouble();
        _refresh();
      }, onError: (Object _) {
        // Metering failure must not discard an otherwise valid recording.
        _amplitude = 0;
        _refresh();
      });
      _startTimer();
      if (widget.startSoundAsset != null) {
        unawaited(_playAssetSound(widget.startSoundAsset!));
      }
      _refresh();
    } catch (e) {
      await _cancelAmplitude();
      await _discardTemporaryRecording(reportError: false);
      if (sequence == _sessionSequence && _pressed) _reportError(e);
      _isRecording = false;
    } finally {
      _preparingTimer?.cancel();
      _starting = false;
      if (!_isRecording) {
        _pressed = false;
        _showCancelHint = false;
        _backgroundColor = widget.backgroundColor;
        _seconds = 0;
        _amplitude = 0;
      }
      _startOperation = null;
      completion.complete();
      _refresh();
    }
  }

  Future<void> _cleanUpLateStart(Future<void> nativeStart) async {
    try {
      await nativeStart;
    } catch (_) {}
    await _discardTemporaryRecording();
  }

  Future<void> _stopRecording() async {
    _pressed = false;
    if (_starting) {
      _isCancelled = true;
      _sessionSequence++;
      await _startOperation;
      return;
    }
    if (_stopping) {
      await _stopOperation;
      return;
    }
    if (_disposing || !_isRecording) return;
    final completion = Completer<void>();
    _stopOperation = completion.future;
    _stopping = true;
    _timer?.cancel();
    _refresh();
    try {
      await _cancelAmplitude();
      if (widget.stopSoundAsset != null) {
        unawaited(_playAssetSound(widget.stopSoundAsset!));
      }
      final filePath = await _recorder.stop();
      if (filePath.isEmpty) throw StateError('No recording file');
      _isRecording = false;
      _refresh();
      if (_disposing || !mounted || _isCancelled) {
        await _discardTemporaryRecording(stopNative: false);
        return;
      }
      final callback = kIsWeb ? widget.onRecordedWeb : widget.onRecorded;
      if (callback == null) {
        await _discardTemporaryRecording(stopNative: false);
        return;
      }
      // The application callback now owns the file. Disposal must not delete
      // it while its asynchronous duration check/copy/send is still running.
      _filePath = null;
      final dynamic result = kIsWeb
          ? widget.onRecordedWeb!(filePath)
          : widget.onRecorded!(File(filePath));
      if (result is Future) await result;
    } catch (e) {
      await _discardTemporaryRecording(reportError: false);
      _reportError(e);
    } finally {
      _isRecording = false;
      _stopping = false;
      _showCancelHint = false;
      _backgroundColor = widget.backgroundColor;
      _seconds = 0;
      _amplitude = 0;
      _stopOperation = null;
      completion.complete();
      _refresh();
    }
  }

  Future<void> _cancelRecording() async {
    _pressed = false;
    _isCancelled = true;
    _sessionSequence++;
    if (_starting) {
      await _startOperation;
      return;
    }
    if (_stopping) {
      await _stopOperation;
      return;
    }
    if (_disposing || !_isRecording) return;
    final completion = Completer<void>();
    _stopOperation = completion.future;
    _stopping = true;
    _timer?.cancel();
    _refresh();
    try {
      await _cancelAmplitude();
      await _discardTemporaryRecording();
      if (_disposing || !mounted) return;
      if (widget.enableHapticFeedback) {
        unawaited(HapticFeedback.mediumImpact());
      }
      if (widget.actionWhenCancel != null) {
        widget.actionWhenCancel!();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.recordCancelledMessage)),
        );
      }
    } catch (e) {
      _reportError(e);
    } finally {
      _isRecording = false;
      _stopping = false;
      _showCancelHint = false;
      _backgroundColor = widget.backgroundColor;
      _seconds = 0;
      _amplitude = 0;
      _stopOperation = null;
      completion.complete();
      _refresh();
    }
  }

  void _startTimer() {
    _seconds = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposing || !mounted || !_isRecording) {
        timer.cancel();
        return;
      }
      _seconds++;
      _refresh();
      if (widget.maxRecordDuration != null &&
          _seconds >= widget.maxRecordDuration!.inSeconds) {
        unawaited(_stopRecording());
        widget.onMaxDurationReached?.call();
      }
    });
  }

  Future<bool> _checkPermissions() async {
    if (Platform.isMacOS) return true;
    final mic = await Permission.microphone.request();
    return mic == PermissionStatus.granted;
  }

  Future<void> _playAssetSound(String assetPath) async {
    try {
      await playSound(assetPath);
    } catch (e) {
      _reportError(e);
    }
  }

  // Build the UI for the voice recorder widget
  @override
  Widget build(BuildContext context) {
    if (widget.builder != null) {
      return widget.builder!(context, _controller);
    }
    return GestureDetector(
      // Start recording when long press starts
      onLongPressStart: (details) {
        _startOffset = details.globalPosition;
        unawaited(_startControlled());
        setState(() {
          _showCancelHint = true; // Show the cancel hint
        });
      },
      // Update drag distance and cancel recording if dragged far enough
      onLongPressMoveUpdate: (details) {
        if (widget.showSwipeLeftToCancel &&
            _isRecording &&
            _startOffset != null) {
          double distance = details.globalPosition.dx - _startOffset!.dx;

          setState(() {
            dragDistance = distance; // Update drag distance
            double percent = (distance.abs() / 100)
                .clamp(0, 1); // Calculate cancellation percentage
            _backgroundColor = Color.lerp(
                widget.cancelHintColor,
                widget.backgroundColor,
                1 - percent)!; // Update background color
          });

          // Cancel recording if dragged far enough
          // make cancel by remove right (>100) or left (< -70)
          if ((distance < -70 || distance > 100) && !_isCancelled) {
            _cancelRecording();
          }
        }
      },
      // Stop recording if long press ends
      onLongPressCancel: _cancelRecording,
      onLongPressEnd: (_) {
        _pressed = false;
        if (!_isCancelled) {
          unawaited(_stopControlled());
        }
        setState(() {
          _showCancelHint = false; // Hide the cancel hint
          _backgroundColor = widget.backgroundColor; // Reset background color
        });
      },
      child: widget.style == VoiceUIStyle.classic
          ? VoiceClassicStyle(
              isRecording: _isRecording,
              showCancelHint: _showCancelHint,
              showSwipeLeftToCancel: widget.showSwipeLeftToCancel,
              dragToLeftText: widget.dragToLeftText,
              dragToLeftTextStyle: widget.dragToLeftTextStyle,
              showTimerText: widget.showTimerText,
              isCancelled: _isCancelled,
              cancelDoneText: widget.cancelDoneText,
              timerTextStyle: widget.timerTextStyle,
              iconSize: widget.iconSize,
              seconds: _seconds,
              cancelHintColor: widget.cancelHintColor,
              timerFontSize: widget.timerFontSize,
              backgroundColorSecond: widget.backgroundColor,
              backgroundColorFirst: _backgroundColor,
              stopRecordingWidget: widget.stopRecordingWidget,
              startRecordingWidget: widget.startRecordingWidget,
              iconColor: widget.iconColor,
            )
          : VoiceCompactStyle(
              idleText: widget.idleText,
              isRecording: _isRecording,
              showCancelHint: _showCancelHint,
              showSwipeLeftToCancel: widget.showSwipeLeftToCancel,
              dragToLeftText: widget.dragToLeftText,
              dragToLeftTextStyle: widget.dragToLeftTextStyle,
              showTimerText: widget.showTimerText,
              isCancelled: _isCancelled,
              cancelDoneText: widget.cancelDoneText,
              timerTextStyle: widget.timerTextStyle,
              iconSize: widget.iconSize,
              seconds: _seconds,
              cancelHintColor: widget.cancelHintColor,
              timerFontSize: widget.timerFontSize,
              backgroundColorSecond: widget.backgroundColor,
              backgroundColorFirst: _backgroundColor,
              stopRecordingWidget: widget.stopRecordingWidget,
              startRecordingWidget: widget.startRecordingWidget,
              iconColor: widget.iconColor,
              containerColor: widget.containerColor,
              borderColor: widget.borderColor,
              borderRadius: widget.borderRadius,
              idleWavesColor: widget.idleWavesColor,
              recordingWavesColor: widget.recordingWavesColor,
              speed: widget.wavesSpeed ?? const Duration(milliseconds: 300),
            ),
    );
  }
}
