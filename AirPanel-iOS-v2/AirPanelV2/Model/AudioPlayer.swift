import AVFoundation
import Observation

// MARK: - 录音播放器
//
// 录音文件在 WebDAV 上，`/api/recordings/play` 需要 Bearer token，
// 所以不能把 URL 丢给 AVPlayer——必须先取回 Data 再本地播。
// 好处是进度条是真实播放进度，而不是按文件大小瞎猜的。

@MainActor
@Observable
final class AudioPlayer {

    private(set) var currentID: String?
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isLoading = false
    var error: String?

    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    func isActive(_ id: String) -> Bool { currentID == id }

    func toggle(id: String, load: @escaping () async throws -> Data) async {
        if currentID == id {
            stop()
            return
        }
        stop()
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try await load()
            try activateSession()
            let p = try AVAudioPlayer(data: data)
            p.prepareToPlay()
            p.play()
            player = p
            currentID = id
            isPlaying = true
            duration = p.duration
            progress = 0
            startTicker()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            stop()
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        currentID = nil
        isPlaying = false
        progress = 0
        duration = 0
    }

    private func startTicker() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                guard let p = self.player else { return }
                if p.duration > 0 {
                    self.progress = min(1, p.currentTime / p.duration)
                }
                if !p.isPlaying {
                    self.stop()
                    return
                }
            }
        }
    }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
    }
}
