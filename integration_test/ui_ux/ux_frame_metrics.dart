import 'package:flutter/scheduler.dart';

/// Samples engine timings without requiring a VM timeline connection on-device.
/// This measures build/raster work, not input latency, energy or real-phone FPS.
Future<Map<String, Object>> measureUxFrames(
    Future<void> Function() action, Future<void> Function() flushFrames) async {
  final frames = <FrameTiming>[];
  void collect(List<FrameTiming> batch) => frames.addAll(batch);
  SchedulerBinding.instance.addTimingsCallback(collect);
  try {
    await action();
    await flushFrames();
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(collect);
  }
  final build =
      frames.map((f) => f.buildDuration.inMicroseconds / 1000).toList();
  final raster =
      frames.map((f) => f.rasterDuration.inMicroseconds / 1000).toList();
  return {
    'frame_count': frames.length,
    'build_ms': build,
    'raster_ms': raster,
    'over_60hz_budget_count': frames
        .where((f) =>
            f.buildDuration.inMicroseconds > 16667 ||
            f.rasterDuration.inMicroseconds > 16667)
        .length,
  };
}
