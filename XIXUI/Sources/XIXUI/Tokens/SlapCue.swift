// One sound in the app: the slap when a sticker lands (PRD 8.21 Settings › Sound). It respects the
// Settings toggle and the ring/silent switch, because the category is `.ambient` and the app never
// overrides it. Nothing else in XIX makes a noise.
import AVFoundation
import Foundation

public enum SlapCue {
    /// The Settings toggle. Off mutes the cue everywhere; unset means on.
    public static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "xix.sound") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "xix.sound") }
    }

    #if canImport(AVFAudio)
    private static let player: AVAudioPlayer? = {
        guard let url = Bundle.module.url(forResource: "slap", withExtension: "wav", subdirectory: "Audio")
            ?? Bundle.module.url(forResource: "slap", withExtension: "wav") else { return nil }
        let p = try? AVAudioPlayer(contentsOf: url)
        p?.prepareToPlay()
        return p
    }()

    /// Fires the cue on the slap's contact frame. Silent when the toggle is off, when the phone is on
    /// silent, or when the round is in quiet mode (the caller decides that part).
    public static func play() {
        guard isEnabled, let player else { return }
        #if os(iOS)
        // `.ambient` is the category that obeys the silent switch and never interrupts anyone's music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        #endif
        player.currentTime = 0
        player.play()
    }
    #else
    public static func play() {}
    #endif
}
