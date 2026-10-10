import AVFoundation
import WebRTC

/// CallKit activates the session; WebRTC only starts its audio after Flutter
/// has prepared the matching call. Other app audio keeps its existing owner.
final class CallKitAudioSession {
    private(set) var active = false
    private var ownsSession = false
    private var previousManualAudio = false
    private var previousAudioEnabled = true

    func prepare(hasVideo: Bool) throws {
        let session = RTCAudioSession.sharedInstance()
        if !ownsSession {
            previousManualAudio = session.useManualAudio
            previousAudioEnabled = session.isAudioEnabled
            ownsSession = true
            session.isAudioEnabled = false
        }
        session.useManualAudio = true
        let configuration = RTCAudioSessionConfiguration.webRTC()
        configuration.category = AVAudioSession.Category.playAndRecord.rawValue
        configuration.mode = (hasVideo ? AVAudioSession.Mode.videoChat : .voiceChat).rawValue
        configuration.categoryOptions = hasVideo ? [.allowBluetooth, .defaultToSpeaker] : [.allowBluetooth]
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        // The overload without `active` never calls setActive(true).
        try session.setConfiguration(configuration)
    }

    func didActivate(_ audioSession: AVAudioSession) {
        active = true
        RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
    }

    func didDeactivate(_ audioSession: AVAudioSession) {
        active = false
        let session = RTCAudioSession.sharedInstance()
        if ownsSession { session.isAudioEnabled = false }
        session.audioSessionDidDeactivate(audioSession)
    }

    func setEnabled(_ enabled: Bool) -> Bool {
        guard ownsSession, !enabled || active else { return false }
        RTCAudioSession.sharedInstance().isAudioEnabled = enabled
        return true
    }

    func setSpeakerphone(_ enabled: Bool) -> Bool {
        guard ownsSession, active else { return false }
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(enabled ? .speaker : .none)
            return true
        } catch { return false }
    }

    func quarantine(force: Bool = false) {
        guard ownsSession || force else { active = false; return }
        let session = RTCAudioSession.sharedInstance()
        if !ownsSession {
            previousManualAudio = session.useManualAudio
            previousAudioEnabled = session.isAudioEnabled
            ownsSession = true
        }
        session.useManualAudio = true
        session.isAudioEnabled = false
        active = false
    }

    func releaseAfterMediaStopped() {
        guard ownsSession else { return }
        let session = RTCAudioSession.sharedInstance()
        session.isAudioEnabled = false
        session.useManualAudio = previousManualAudio
        session.isAudioEnabled = previousAudioEnabled
        ownsSession = false
        active = false
        // Caller has disposed the old media. CallKit owns native deactivation.
    }
}
