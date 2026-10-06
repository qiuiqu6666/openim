/// Shared identifiers for settings previews and native notification resources.
/// These are the existing 99chat sounds in openim_common, not remote filenames.
abstract final class MessageNotificationSoundIds {
  static const defaultId = 'preview000';
  static const optionIds = <String>[
    defaultId,
    'crisp',
    'soft',
    'chime',
    'preview',
    'preview1',
    'preview04',
  ];

  static String normalizedId(String? value) {
    final id = value?.trim();
    return optionIds.contains(id) ? id! : defaultId;
  }

  static String assetPath(String value) =>
      'assets/audio/99chat/${normalizedId(value)}.wav';

  static String androidResource(String value) =>
      'chat_message_${normalizedId(value)}';

  static String darwinFilename(String value) => '${androidResource(value)}.wav';
}
