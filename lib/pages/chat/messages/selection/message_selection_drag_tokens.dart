/// Edge scrolling geometry adapted from 99chat's desktop drag selection.
/// Touch activation uses Flutter's normal long-press recognizer.
abstract final class MessageSelectionDragTokens {
  static const edgeZone = 56.0;
  static const minSpeed = 260.0;
  static const maxSpeed = 1400.0;
  static const maxFrameSeconds = .05;
}
