import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Boundaries use the persisted OpenIM sequence inside the current group.
/// User-controlled message.ex never selects a backend message or another tenant.
class SangongBetSubmitCutoff {
  const SangongBetSubmitCutoff(
      {this.untilMsgSeq, this.excludeMsgSeqs = const []});
  final int? untilMsgSeq;
  final List<int> excludeMsgSeqs;
  bool get hasExplicitBoundary => untilMsgSeq != null;
  bool get hasExclusions => excludeMsgSeqs.isNotEmpty;
  List<int> get sortedExclusions => excludeMsgSeqs.toSet().toList()..sort();

  Map<String, dynamic> toJson() {
    if (untilMsgSeq != null && untilMsgSeq! <= 0 ||
        excludeMsgSeqs.any((seq) => seq <= 0) ||
        sortedExclusions.length > 100) {
      throw ArgumentError('消息截止点或排除范围无效');
    }
    return {
      if (untilMsgSeq != null) 'untilMsgSeq': untilMsgSeq,
      if (hasExclusions) 'excludeMsgSeqs': sortedExclusions
    };
  }

  Map<String, dynamic> toQuery() => {
        ...toJson(),
        if (hasExclusions) 'excludeMsgSeqs': sortedExclusions.join(',')
      };

  SangongBetSubmitCutoff withAdditionalExclude(int seq) =>
      SangongBetSubmitCutoff(
          untilMsgSeq: untilMsgSeq, excludeMsgSeqs: [...sortedExclusions, seq]);

  static SangongBetSubmitCutoff? fromLongPressedMessage(Message message) {
    final seq = readMessageSeq(message);
    return seq == null ? null : SangongBetSubmitCutoff(untilMsgSeq: seq);
  }

  static SangongBetSubmitCutoff? excludingMessage(Message message) {
    final seq = readMessageSeq(message);
    return seq == null ? null : SangongBetSubmitCutoff(excludeMsgSeqs: [seq]);
  }

  static bool canExcludeMessage(Message message) =>
      readMessageSeq(message) != null;
  static int? readMessageSeq(Message message) =>
      message.seq != null && message.seq! > 0 ? message.seq : null;
  static String? readMessagePreviewText(Message message) =>
      message.textElem?.content;
  static String readSenderLabel(Message message) =>
      message.senderNickname?.trim().isNotEmpty == true
          ? message.senderNickname!.trim()
          : message.sendID ?? '';
}
