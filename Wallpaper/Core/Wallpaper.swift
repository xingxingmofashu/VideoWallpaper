import Cocoa
import AVFoundation
import SwiftUI

final class Wallpaper: NSObject {
    private let player: AVQueuePlayer
    private let playlist: Playlist
    private let options: RunOptions

    private var windows: [NSWindow] = []
    private var itemObserverTokens: [NSObjectProtocol] = []
    private var currentItemObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?

    private var heartbeatTimer: Timer?
    private var stallTimer: Timer?
    private var waveformTimer: Timer?

    private var waveformHosts: [NSView] = []
    private var spectrum: AudioSpectrum?
    private let spectrumStore = SpectrumStore()
    private var observedItem: AVPlayerItem?
    private var waveformEnabled = false

    private var isRunning = false
    private var isAsleep = false
    private var consecutiveFailures = 0

    private(set) var lastHeartbeat = Date()

    init(playlist: Playlist, options: RunOptions) {
        self.playlist = playlist
        self.options = options
        player = AVQueuePlayer(items: [AVPlayerItem(url: playlist.next())])
        player.volume = options.volume
        player.isMuted = options.volume <= 0
        player.defaultRate = options.rate
        super.init()
        if options.waveform {
            spectrum = AudioSpectrum()
            waveformEnabled = true
        }
        observeCurrentItem()
    }

    deinit {
        if isRunning { stop() }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        observeSystemEvents()
        createWindows()
        player.play()
        startHeartbeat()
        startStallMonitor()
        startWatchdog()
        if waveformEnabled {
            startWaveformTimer()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        statusObservation?.invalidate()
        statusObservation = nil
        itemObserverTokens.forEach { NotificationCenter.default.removeObserver($0) }
        itemObserverTokens.removeAll()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        stallTimer?.invalidate()
        stallTimer = nil
        waveformTimer?.invalidate()
        waveformTimer = nil
        observedItem = nil
        player.pause()
        teardownWindows()
    }

    private func observeSystemEvents() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(screensDidSleep),
                           name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(screensDidWake),
                           name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc private func screenParametersDidChange(_ note: Notification) {
        guard isRunning else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.rebuildWindows()
        }
    }

    @objc private func screensDidSleep(_ note: Notification) {
        guard isRunning else { return }
        isAsleep = true
        player.pause()
    }

    @objc private func screensDidWake(_ note: Notification) {
        guard isRunning else { return }
        isAsleep = false
        player.play()
    }

    func mute() {
        player.isMuted = true
    }

    func unmute() {
        if player.volume <= 0 {
            player.volume = 1
        }
        player.isMuted = false
    }

    private func observeCurrentItem() {
        currentItemObservation = player.observe(\.currentItem, options: [.initial, .new]) {
            [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.currentItemObservation != nil else { return }
                self.lastProgress = .zero
                self.frozenSeconds = 0
                self.replenishQueue()
                self.attachItemObservers()
            }
        }
    }

    private func replenishQueue() {
        while player.items().count < 2 {
            player.insert(AVPlayerItem(url: playlist.next()), after: player.items().last)
        }
    }

    private func attachItemObservers() {
        itemObserverTokens.forEach { NotificationCenter.default.removeObserver($0) }
        itemObserverTokens.removeAll()
        guard let item = player.currentItem else { return }

        if waveformEnabled, let spectrum {
            if let observedItem, observedItem !== item {
                spectrum.detach(from: observedItem)
            }
            observedItem = item
            spectrum.attach(to: item) { [weak self] hasAudio in
                self?.spectrumStore.visible = hasAudio
            }
        }

        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.statusObservation != nil else { return }
                switch item.status {
                case .readyToPlay:
                    self.consecutiveFailures = 0
                case .failed:
                    let detail = item.error?.localizedDescription ?? "unknown"
                    self.handleItemFailure(item, detail: detail)
                default:
                    break
                }
            }
        }

        let failure = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] note in
            let detail = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription ?? "unknown"
            self?.handleItemFailure(item, detail: detail)
        }
        itemObserverTokens.append(failure)

        let stalled = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
        ) { [weak self] _ in
            guard let self, self.options.stallLimit > 0 else { return }
            self.handleItemFailure(item, detail: "Playback stalled")
        }
        itemObserverTokens.append(stalled)

        let didEnd = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            self?.frozenSeconds = 0
        }
        itemObserverTokens.append(didEnd)
    }

    private func createWindows() {
        if options.singleScreen {
            if let main = NSScreen.main {
                windows.append(makeWindow(for: main))
            }
        } else {
            windows = NSScreen.screens.map(makeWindow(for:))
        }
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.backgroundColor = .black
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false

        let contentView = window.contentView ?? NSView()
        contentView.wantsLayer = true
        let container = CALayer()
        container.frame = contentView.bounds
        container.backgroundColor = NSColor.black.cgColor
        let videoLayer = AVPlayerLayer(player: player)
        videoLayer.videoGravity = .resizeAspectFill
        videoLayer.frame = container.bounds
        container.addSublayer(videoLayer)
        contentView.layer = container
        window.contentView = contentView

        if waveformEnabled {
            addWaveformHost(contentView: contentView)
        }

        window.orderFrontRegardless()
        return window
    }

    private func rebuildWindows() {
        let target = options.singleScreen
            ? NSScreen.main.map { [$0] } ?? []
            : NSScreen.screens

        if windows.count == target.count,
           zip(windows, target).allSatisfy({ window, screen in
               window.screen === screen && NSEqualRects(window.frame, screen.frame)
           }) {
            return
        }

        teardownWindows()
        createWindows()
    }

    private func teardownWindows() {
        waveformHosts.removeAll()
        windows.forEach { $0.contentView?.layer = nil }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func startHeartbeat() {
        heartbeatTimer = repeatingTimer(interval: 0.5) { [weak self] in
            self?.lastHeartbeat = Date()
        }
    }

    private func startWaveformTimer() {
        guard waveformTimer == nil else { return }
        waveformTimer = repeatingTimer(interval: 1.0 / 30.0) { [weak self] in
            self?.tickWaveform()
        }
    }

    private func stopWaveformTimer() {
        waveformTimer?.invalidate()
        waveformTimer = nil
    }

    private func tickWaveform() {
        guard isRunning, waveformEnabled, let spectrum else { return }
        let (bands, peaks) = spectrum.advance(active: !player.isMuted)
        spectrumStore.bands = bands
        spectrumStore.peaks = peaks
    }

    func setWaveform(_ enabled: Bool) {
        guard waveformEnabled != enabled else { return }
        waveformEnabled = enabled
        if enabled {
            if spectrum == nil {
                spectrum = AudioSpectrum()
            }
            if let item = player.currentItem, let spectrum {
                observedItem = item
                spectrum.attach(to: item) { [weak self] hasAudio in
                    self?.spectrumStore.visible = hasAudio
                }
            }
            addWaveformHosts()
            startWaveformTimer()
        } else {
            stopWaveformTimer()
            removeWaveformHosts()
            if let observedItem, let spectrum {
                spectrum.detach(from: observedItem)
            }
            observedItem = nil
            spectrumStore.visible = false
            spectrumStore.bands = []
            spectrumStore.peaks = []
        }
    }

    private func addWaveformHosts() {
        guard waveformHosts.isEmpty else { return }
        for window in windows {
            guard let contentView = window.contentView else { continue }
            addWaveformHost(contentView: contentView)
        }
    }

    private func removeWaveformHosts() {
        waveformHosts.forEach { $0.removeFromSuperview() }
        waveformHosts.removeAll()
    }

    private func addWaveformHost(contentView: NSView) {
        let bounds = contentView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        let panel = GlassSpectrumView.panelSize(in: bounds.size)
        let padding: CGFloat = 96
        let hostSize = CGSize(width: panel.width + padding * 2, height: panel.height + padding * 2)
        let centreY = bounds.height * (1 - GlassSpectrumView.verticalPosition)
        let host = NSHostingView(rootView: GlassSpectrumView(store: spectrumStore, panelSize: panel))
        host.frame = CGRect(
            x: (bounds.width - hostSize.width) / 2,
            y: centreY - hostSize.height / 2,
            width: hostSize.width,
            height: hostSize.height)
        contentView.addSubview(host)
        waveformHosts.append(host)
    }

    private var lastProgress = CMTime.zero
    private var frozenSeconds: TimeInterval = 0
    private var pendingSeconds: TimeInterval = 0
    private var hasPlayed = false

    private func startStallMonitor() {
        guard options.stallLimit > 0 else { return }
        stallTimer = repeatingTimer(interval: 1.0) { [weak self] in
            self?.checkStall()
        }
    }

    private func checkStall() {
        guard isRunning, !isAsleep else { return }
        let now = player.currentTime()
        let delta = CMTimeGetSeconds(CMTimeSubtract(now, lastProgress))
        lastProgress = now

        let playing = player.timeControlStatus == .playing
        if playing {
            hasPlayed = true
            if delta < 0.01 {
                frozenSeconds += 1
                if frozenSeconds >= options.stallLimit {
                    exitWithError("Playback frozen for over \(Int(options.stallLimit)) seconds")
                }
            } else {
                frozenSeconds = 0
            }
        } else {
            frozenSeconds = 0
            guard !hasPlayed else { return }
            pendingSeconds += 1
            if pendingSeconds >= options.stallLimit {
                exitWithError("Playback did not start within \(Int(options.stallLimit)) seconds")
            }
        }
    }

    private func startWatchdog() {
        guard options.watchdogLimit > 0 else { return }
        let limit = options.watchdogLimit
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while let self = self {
                Thread.sleep(forTimeInterval: 0.5)
                if Date().timeIntervalSince(self.lastHeartbeat) > limit {
                    self.exitFromBackground("Main thread unresponsive for over \(Int(limit)) seconds")
                }
            }
        }
    }

    private func repeatingTimer(interval: TimeInterval, handler: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in handler() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func handleItemFailure(_ item: AVPlayerItem, detail: String) {
        guard item === player.currentItem else { return }
        consecutiveFailures += 1
        if consecutiveFailures >= playlist.count {
            exitWithError("All videos failed to play: \(detail)")
            return
        }
        Console.info("Skipping unplayable video: \(detail)")
        player.advanceToNextItem()
        replenishQueue()
        if !isAsleep {
            player.play()
        }
    }

    private func exitWithError(_ message: String) {
        stop()
        PIDFile.shared.remove()
        Console.error(message)
        exit(2)
    }

    private func exitFromBackground(_ message: String) {
        PIDFile.shared.remove()
        Console.error(message)
        exit(3)
    }
}
