import 'package:openim_common/openim_common.dart';

/// Uses the shared text toast after all forwarding destinations acknowledge.
class ForwardSuccessFeedback {
  ForwardSuccessFeedback._();

  static void show() {
    IMViews.showToast(StrRes.sendSuccessfully,
        duration: const Duration(seconds: 2), centered: true);
  }
}
