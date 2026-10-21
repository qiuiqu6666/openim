import 'package:openim_common/openim_common.dart';

/// Show only after the requested favorite send has been acknowledged.
void showFavoriteSendSuccess() {
  IMViews.showToast(StrRes.sendSuccessfully,
      duration: const Duration(seconds: 2), centered: true);
}
