/// One app-bundled 99CHAT sticker. Sending remains owned by the OpenIM flow.
class ChatBuiltinSticker {
  const ChatBuiltinSticker({
    required this.id,
    required this.fileName,
    required this.label,
    this.width = ChatBuiltinStickerCatalog.imageWidth,
    this.height = ChatBuiltinStickerCatalog.imageHeight,
  });

  final String id;
  final String fileName;
  final String label;
  final int width;
  final int height;

  String get assetPath =>
      '${ChatBuiltinStickerCatalog.assetDirectory}/$fileName';
}

/// Original 4351 order from 99chat's `Const.emojiList`, with no network lookup.
abstract final class ChatBuiltinStickerCatalog {
  static const packID = '4351';
  static const label = '99CHAT';
  static const assetDirectory = 'lib/pages/chat/stickers/builtin/assets/4351';
  static const menuAssetPath = '$assetDirectory/menu@2x.png';

  // Read from the original PNG IHDR metadata; all 16 images and menu are 240².
  static const imageWidth = 240;
  static const imageHeight = 240;

  // The reference names files, not actions. Labels describe the actual artwork
  // for tooltips/accessibility; IDs remain independent of translated labels.
  static const stickers = <ChatBuiltinSticker>[
    ChatBuiltinSticker(
        id: '99chat_4351_ys00', fileName: 'ys00@2x.png', label: '睡觉'),
    ChatBuiltinSticker(
        id: '99chat_4351_ys01', fileName: 'ys01@2x.png', label: '点赞'),
    ChatBuiltinSticker(
        id: '99chat_4351_ys02', fileName: 'ys02@2x.png', label: '疑问'),
    ChatBuiltinSticker(
        id: '99chat_4351_ys03', fileName: 'ys03@2x.png', label: '庆祝'),
    ChatBuiltinSticker(
        id: '99chat_4351_ys04', fileName: 'ys04@2x.png', label: '酷'),
    ChatBuiltinSticker(
        id: '99chat_4351_ys05', fileName: 'ys05@2x.png', label: '喜欢'),
    ChatBuiltinSticker(
        id: '99chat_4351_ys06', fileName: 'ys06@2x.png', label: '惊讶'),
    ChatBuiltinSticker(
        id: '99chat_4351_ys07', fileName: 'ys07@2x.png', label: '大笑'),
    ChatBuiltinSticker(
        id: '99chat_4351_ys08', fileName: 'ys08@2x.png', label: '哭泣'),
    ChatBuiltinSticker(
        id: '99chat_4351_ys09', fileName: 'ys09@2x.png', label: '尴尬'),
    ChatBuiltinSticker(
        id: '99chat_4351_ys10', fileName: 'ys10@2x.png', label: '拥抱'),
    ChatBuiltinSticker(
        id: '99chat_4351_ys11', fileName: 'ys11@2x.png', label: '生气'),
    ChatBuiltinSticker(
        id: '99chat_4351_ys12', fileName: 'ys12@2x.png', label: '挥手'),
    ChatBuiltinSticker(
        id: '99chat_4351_ys13', fileName: 'ys13@2x.png', label: '好的'),
    ChatBuiltinSticker(
        id: '99chat_4351_ys14', fileName: 'ys14@2x.png', label: '害羞'),
    ChatBuiltinSticker(
        id: '99chat_4351_ys15', fileName: 'ys15@2x.png', label: '你好'),
  ];

  static ChatBuiltinSticker? byID(String id) {
    for (final sticker in stickers) {
      if (sticker.id == id) return sticker;
    }
    return null;
  }
}
