import 'package:get/get.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

/// Presentation only: selected assets are not SDK messages until prepared.
/// Accepted work survives closing its route, just like the media outbox.
class PendingChatMedia {
  PendingChatMedia(
      {required this.asset,
      required this.conversationID,
      required this.visible});

  static final entries = <PendingChatMedia>[].obs;
  static int _sequence = 0;
  final String id = 'pending-media-${_sequence++}';
  final AssetEntity asset;
  final String conversationID;
  final bool Function() visible;
}
