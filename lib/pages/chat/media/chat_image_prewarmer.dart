import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/media_preloading.dart';

import 'chat_picture_gallery.dart';

/// Route-owned, bounded speculative work. The viewer's provider reads and writes
/// the same encoded disk cache as chat thumbnails and full-screen previews.
class ChatImagePrewarmer {
  ChatImagePrewarmer({ViewerImageProvider Function(String)? createImage})
      : _createImage = createImage;

  final ViewerImageProvider Function(String)? _createImage;
  Set<String> _thumbnails = {};
  final _done = <String>{};
  List<String> _urls = [];
  Timer? _idle;
  ViewerImageProvider? _image;
  bool _active = true, _scrolling = false, _disposed = false;

  static List<String> candidates(List<Message> messages, List<String> visible) {
    final visibleIDs = visible.toSet();
    final indices = <int>[];
    for (var i = 0; i < messages.length; i++) {
      if (visibleIDs.contains(messages[i].clientMsgID)) indices.add(i);
    }
    if (indices.isEmpty) return [];
    final ordered = <int>[...indices];
    // Neighbors are bounded by rows, not a scan of all historic attachments.
    for (var distance = 1; distance <= 2; distance++) {
      if (indices.first - distance >= 0) ordered.add(indices.first - distance);
      if (indices.last + distance < messages.length) {
        ordered.add(indices.last + distance);
      }
    }
    final urls = <String>{};
    var pictures = 0;
    for (final i in ordered) {
      final message = messages[i];
      if (message.contentType != MessageType.picture ||
          message.attachedInfoElem?.isPrivateChat == true) {
        continue;
      }
      final picture = message.pictureElem;
      if (picture == null) continue;
      if (++pictures > 8) break;
      final originals = [
        picture.sourcePicture?.url,
        picture.bigPicture?.url,
        picture.snapshotPicture?.url
      ].whereType<String>().where((url) => url.trim().isNotEmpty);
      final original = originals.isEmpty ? null : originals.first;
      final thumbnail = picture.snapshotPicture?.url;
      final preview = ChatPictureGallery.previewUrl(picture, original);
      for (final url in [thumbnail, preview]) {
        // Never turn speculative loading into an original-image download.
        if (url == null || url.isEmpty || url == original) continue;
        final resolved = OpenIMMediaUrl.resolve(url, imApiUrl: Config.imApiUrl);
        if (Uri.tryParse(resolved)?.scheme case 'http' || 'https') {
          urls.add(resolved);
        }
      }
    }
    return urls.toList();
  }

  void update(List<Message> messages, List<String> visible) {
    _urls = candidates(messages, visible);
    _thumbnails = {
      for (final message in messages)
        if (message.pictureElem?.snapshotPicture?.url case final String url)
          OpenIMMediaUrl.resolve(url, imApiUrl: Config.imApiUrl),
    };
    if (_image != null && !_urls.contains(_image!.url)) _cancel();
    _schedule();
  }

  void setActive(bool value) {
    if (_active == value) return;
    _active = value;
    if (!value) _cancel();
    _schedule();
  }

  void setScrolling(bool value) {
    _scrolling = value;
    _schedule();
  }

  void _schedule() {
    _idle?.cancel();
    if (_disposed || !_active || _scrolling) return;
    _idle = Timer(const Duration(milliseconds: 250), _next);
  }

  void _next() {
    if (_disposed || !_active || _scrolling || _image != null) return;
    final pending = _urls.where((url) => !_done.contains(url));
    if (pending.isEmpty) return;
    final url = pending.first;
    final image = _image = _createImage?.call(url) ??
        ViewerImageProvider(url, cacheOnly: _thumbnails.contains(url));
    void finish() {
      if (!identical(_image, image)) return;
      _image = null;
      _done.add(url);
      if (_done.length > 128) _done.remove(_done.first);
      _next();
    }

    unawaited(image
        .prefetchEncoded()
        .then((_) => finish(), onError: (Object _, StackTrace __) => finish()));
  }

  void _cancel() {
    _idle?.cancel();
    _image?.cancel();
    _image = null;
  }

  void dispose() {
    _disposed = true;
    _cancel();
    _urls = [];
    _done.clear();
  }
}
