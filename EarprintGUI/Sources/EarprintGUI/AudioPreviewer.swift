#if canImport(AVFoundation)
import Foundation
import AVFoundation

@MainActor
final class AudioPreviewer: ObservableObject {
    private var player: AVAudioPlayer?

    func start(url: URL, balance: String) {
        stop()
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.pan = pan(for: balance)
            player?.prepareToPlay()
            player?.play()
        } catch {
            print("Preview error: \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }

    private func pan(for balance: String) -> Float {
        switch balance.lowercased() {
        case "left":
            return -1
        case "right":
            return 1
        default:
            return 0
        }
    }
}
#endif