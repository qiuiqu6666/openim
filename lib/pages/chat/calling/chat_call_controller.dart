import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';

import '../../../core/controller/im_controller.dart';

/// Chat entry points for the existing single-recipient calling flow.
class ChatCallController {
  ChatCallController({
    required IMController im,
    required String? Function() userID,
    required String Function() nickname,
    required bool Function() isClosed,
    required bool Function() isSingleChat,
    required bool Function() busy,
  })  : _im = im,
        _userID = userID,
        _nickname = nickname,
        _isClosed = isClosed,
        _isSingleChat = isSingleChat,
        _busy = busy;

  final IMController _im;
  final String? Function() _userID;
  final String Function() _nickname;
  final bool Function() _isClosed, _isSingleChat, _busy;

  bool get rtcIsBusy => _busy();

  void call() {
    if (_isClosed()) return;
    if (rtcIsBusy) {
      IMViews.showToast(StrRes.callingBusy);
      return;
    }
    IMViews.openIMCallSheet(_nickname(), (index) {
      if (_isClosed()) return;
      _im.call(
        callObj: CallObj.single,
        callType: index == 0 ? CallType.audio : CallType.video,
        inviteeUserIDList: [if (_isSingleChat()) _userID()!],
      );
    });
  }

  void callDirectly(CallType type) {
    if (_isClosed()) return;
    if (rtcIsBusy) {
      IMViews.showToast(StrRes.callingBusy);
      return;
    }
    if (!_isSingleChat()) return;
    _im.call(
      callObj: CallObj.single,
      callType: type,
      inviteeUserIDList: [_userID()!],
    );
  }

  void callAudio() => callDirectly(CallType.audio);
  void callVideo() => callDirectly(CallType.video);
}
