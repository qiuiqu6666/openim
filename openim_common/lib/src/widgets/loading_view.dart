import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

enum LoadingIndicatorStyle { dots, ring }

class LoadingView {
  static final LoadingView singleton = LoadingView._();

  factory LoadingView() => singleton;

  LoadingView._();

  /// Shared animation for overlays and locally owned loading states.
  static Widget indicator(
          {double size = 50,
          Color? color,
          LoadingIndicatorStyle style = LoadingIndicatorStyle.dots}) =>
      style == LoadingIndicatorStyle.ring
          ? SizedBox.square(
              dimension: size,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: color ?? AppTokens.accent))
          : SpinKitCircle(color: color ?? Styles.c_0089FF, size: size);

  OverlayState? _overlayState;
  OverlayEntry? _overlayEntry;
  bool _isVisible = false;

  OverlayState? _progressOverlayState;
  OverlayEntry? _progressOverlayEntry;
  bool isProgressVisible = false;

  Future<T> wrap<T>({
    required Future<T> Function() asyncFunction,
    bool showing = true,
  }) async {
    await Future.delayed(1.milliseconds);
    if (showing) show();
    T data;
    try {
      data = await asyncFunction();
    } on Exception catch (_) {
      rethrow;
    } finally {
      dismiss();
    }
    return data;
  }

  void show() async {
    if (_isVisible) return;
    _overlayState = Get.key.currentState?.overlay;
    if (_overlayState == null) return;
    _overlayEntry = OverlayEntry(
      builder: (BuildContext context) => Container(
        width: MediaQuery.of(context).size.width,
        color: Colors.transparent,
        child: Center(
          child: indicator(),
        ),
      ),
    );
    _isVisible = true;
    _overlayState?.insert(_overlayEntry!);
  }

  Future<void> dismiss() async {
    if (!_isVisible && !isProgressVisible) return;
    _overlayEntry?.remove();
    _progressOverlayEntry?.remove();
    _isVisible = false;
    isProgressVisible = false;
  }

  void progress(Stream<double> stream) async {
    _progressOverlayState = Get.key.currentState?.overlay;
    if (_progressOverlayState == null) return;
    _progressOverlayEntry = OverlayEntry(
      builder: (BuildContext context) => GestureDetector(
        onTap: dismiss,
        child: Container(
          width: MediaQuery.of(context).size.width,
          color: const Color.fromARGB(0, 37, 33, 33),
          child: Center(
            child: Container(
              alignment: Alignment.center,
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: FeedbackColors.background,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CupertinoActivityIndicator(
                    color: FeedbackColors.foreground,
                    radius: 20,
                  ),
                  StreamBuilder(
                      stream: stream,
                      builder: (BuildContext context,
                          AsyncSnapshot<double> snapshot) {
                        if (!snapshot.hasData) return Container();
                        final progress = snapshot.data ?? 0.0;
                        return Text('${(progress * 100).toStringAsFixed(1)}%',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: FeedbackColors.foreground));
                      }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    isProgressVisible = true;
    _progressOverlayState?.insert(_progressOverlayEntry!);
  }
}
