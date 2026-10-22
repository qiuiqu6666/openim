import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'chat_picture_gallery.dart';

/// Appends pages without changing indexes held by preview actions.
class ChatGalleryPager {
  ChatGalleryPager(
      {required this.gallery,
      required this.conversationID,
      required this.isCurrent,
      this.query});
  final ChatPictureGallery gallery;
  final String conversationID;
  final bool Function() isCurrent;
  final Future<List<Message>> Function(int page, int count)? query;
  int _page = 1;
  final _seen = <String>{};
  bool _more = true;
  Future<bool>? _pending;
  Future<bool> load() =>
      _pending ??= _load().whenComplete(() => _pending = null);
  Future<bool> _load() async {
    if (!_more || !isCurrent()) return false;
    const count = 30;
    final List<Message> batch;
    if (query != null) {
      batch = await query!(_page, count);
    } else {
      final result = await OpenIM.iMManager.messageManager.searchLocalMessages(
          conversationID: conversationID,
          messageTypeList: [MessageType.picture, MessageType.video],
          pageIndex: _page,
          count: count);
      batch = [
        for (final item in result.searchResultItems ?? <SearchResultItems>[])
          ...?item.messageList
      ];
    }
    if (!isCurrent()) return false;
    final ids = batch
        .map((m) => m.clientMsgID)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final fresh = ids.difference(_seen);
    await gallery.append(batch, isCurrent: isCurrent);
    if (!isCurrent()) return false;
    _seen.addAll(ids);
    _page++;
    _more = batch.length >= count && fresh.isNotEmpty;
    return _more;
  }
}
