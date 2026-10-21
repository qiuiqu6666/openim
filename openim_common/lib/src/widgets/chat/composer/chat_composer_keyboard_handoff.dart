import 'dart:async';

/// Keeps the accessory footprint until the asynchronous native IME catches up.
/// The caller subtracts the inset already consumed by Scaffold from [height].
class ChatComposerKeyboardHandoff {
  ChatComposerKeyboardHandoff(this.onReleased);
  final void Function() onReleased;
  static const presentationTimeout = Duration(milliseconds: 800);
  static const metricsSettleDelay = Duration(milliseconds: 120);
  double height = 0;
  Timer? _timer;

  void begin(double panelHeight) {
    if (panelHeight <= 0 || height > 0) return;
    height = panelHeight;
    _schedule(presentationTimeout);
  }

  void updateKeyboard(double inset) {
    if (height <= 0) return;
    if (inset >= height) {
      cancel();
    } else {
      // A shorter keyboard releases the remaining reservation once its native
      // metrics settle. A hardware keyboard must not leave an empty panel.
      _schedule(inset > 0 ? metricsSettleDelay : presentationTimeout);
    }
  }

  void _schedule(Duration duration) {
    _timer?.cancel();
    _timer = Timer(duration, () {
      cancel();
      onReleased();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    height = 0;
  }

  void dispose() => cancel();
}
