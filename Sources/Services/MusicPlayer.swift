import AVFoundation
import AppKit

/// Double-click a song and it plays right in Attic's top bar. ⌥⌘P plays or pauses, ⌥⌘← and ⌥⌘→ skip.
@MainActor @Observable
final class MusicPlayer {
    var current: FileItem?
    var isPlaying = false
    var progress: Double = 0
    private(set) var queue: [FileItem] = []
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var timeObserver: Any?

    func play(_ item: FileItem, queue: [FileItem]) {
        self.queue = queue.contains(item) ? queue : [item]
        start(item)
    }

    /// The play button on a song card: plays it, or pauses if it's already playing.
    func toggle(_ item: FileItem, queue: [FileItem]) {
        if current?.url == item.url { togglePlay() } else { play(item, queue: queue) }
    }

    func togglePlay() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    func next() { step(1) }

    func previous() {
        // Like every music app: back to the start first, then to the previous song.
        if let player, player.currentTime().seconds > 3 {
            player.seek(to: .zero)
            return
        }
        step(-1)
    }

    func stop() {
        teardown()
        current = nil
        isPlaying = false
        progress = 0
    }

    private func step(_ delta: Int) {
        guard let cur = current, let i = queue.firstIndex(of: cur) else { return }
        let j = i + delta
        guard queue.indices.contains(j) else {
            if delta > 0 { stop() }
            return
        }
        start(queue[j])
    }

    private func start(_ item: FileItem) {
        teardown()
        let p = AVPlayer(url: item.url)
        player = p
        current = item
        isPlaying = true
        progress = 0
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { _ in
            Task { @MainActor in AppState.shared.player.next() }
        }
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { t in
            Task { @MainActor in
                let me = AppState.shared.player
                guard let d = me.player?.currentItem?.duration.seconds, d.isFinite, d > 0 else { return }
                me.progress = min(1, max(0, t.seconds / d))
            }
        }
        p.play()
    }

    private func teardown() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player?.pause()
        player = nil
    }
}
