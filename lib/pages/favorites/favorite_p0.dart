import '../../services/favorite_models.dart';

/// Types currently opened by the Chat API. Other schemas stay read-only.
const favoriteP0Kinds = <FavoriteKind>[
  FavoriteKind.text,
  FavoriteKind.note,
  FavoriteKind.image,
  FavoriteKind.video,
  FavoriteKind.audio,
  FavoriteKind.file,
  FavoriteKind.link,
];

bool canSendFavoriteP0(FavoriteItem item) =>
    favoriteP0Kinds.contains(item.kind) &&
    item.canSend &&
    item.blocks.every((block) => const {
          'text',
          'image',
          'video',
          'audio',
          'file',
          'link'
        }.contains(block.type));
