/// These newer gestures render as missing glyphs on supported older devices.
/// This only filters picker entries; message content remains unchanged.
bool isChatPickerEmojiCompatible(String emoji) {
  const unsupported = {
    0x1FAF6,
    0x1F90C,
    0x1FAF3,
    0x1FAF4,
    0x1FAF0,
    0x1FAF2,
    0x1FAF1,
    0x1FAF5
  };
  return !emoji.runes.any(unsupported.contains);
}
