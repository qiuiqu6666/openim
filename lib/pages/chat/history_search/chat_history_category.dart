import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'chat_history_search_strings.dart';

enum ChatHistoryCategory {
  date,
  sender,
  media,
  picture,
  video,
  file,
  voice;

  // Member/day history shows the full selected scope, as in 99chat. Media
  // content also has no keyword index in OpenIM.
  bool get supportsKeyword =>
      this != date &&
      this != sender &&
      this != media &&
      this != picture &&
      this != video &&
      this != voice;

  String title(BuildContext context) => switch (this) {
        date => chatHistorySearchText(context, 'date'),
        sender => chatHistorySearchText(context, 'sender'),
        media => chatHistorySearchText(context, 'media'),
        picture => StrRes.picture,
        video => StrRes.video,
        file => StrRes.file,
        voice => StrRes.voice,
      };

  List<int> get messageTypes => switch (this) {
        media => const [MessageType.picture, MessageType.video],
        picture => const [MessageType.picture],
        video => const [MessageType.video],
        file => const [MessageType.file],
        voice => const [MessageType.voice],
        _ => const [],
      };
}
