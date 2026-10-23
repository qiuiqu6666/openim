import AVFoundation
import Foundation

extension Comparable {
  func clamp(to limits: ClosedRange<Self>) -> Self {
    return min(max(self, limits.lowerBound), limits.upperBound)
  }
}

// Volume controls observe the media owner's session; they must never activate,
// deactivate or change its category (CallKit/WebRTC/players own that lifecycle).
extension AVAudioSession {
  func getVolume() -> Float {
    return outputVolume
  }
}
