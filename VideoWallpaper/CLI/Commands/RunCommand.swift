import ArgumentParser
import Cocoa
import UniformTypeIdentifiers

struct RunOptions {
    var singleScreen = false
    var shuffle = false
    var rate: Float = 1.0
    var volume: Float = 0
    var waveform = false
    var stallLimit: TimeInterval = 8
    var watchdogLimit: TimeInterval = 6
}

struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Play video wallpaper in background",
        discussion: """
            Pass one or more videos; a directory plays all videos inside it (not
            recursive) in filename order, one after another. Unplayable videos are
            skipped. The command returns immediately; the wallpaper keeps playing
            after the terminal is closed. Stop it with `vw stop`. Errors go to
            ~/.vw/vw.log.
            """)

    @Argument(help: ArgumentHelp("A video file, or a directory of videos.", valueName: "video|dir"))
    var paths: [String] = []

    @Flag(name: .long, help: "Cover only the main display (default: all screens)")
    var single = false

    @Flag(name: .long, help: "Play the videos in random order (default: filename order)")
    var shuffle = false

    @Option(help: "Max playback rate to lower CPU/GPU load")
    var rate: Double = 1.0

    @Option(help: "Audio volume; 0 keeps it silent")
    var volume: Double = 0

    @Flag(name: .long, help: "Show audio spectrum bars across the lower desktop")
    var waveform = false

    @Option(help: "Auto-exit when playback stalls or never starts within this long, 0 disables, max 86400")
    var stall: Double = 8

    @Option(help: "Auto-exit if UI is unresponsive this long, 0 disables, max 86400")
    var watchdog: Double = 6

    func validate() throws {
        guard !paths.isEmpty else {
            throw ValidationError("Missing video path")
        }
        guard (0.1...1.0).contains(rate) else {
            throw ValidationError("Invalid value for --rate")
        }
        guard (0.0...1.0).contains(volume) else {
            throw ValidationError("Invalid value for --volume")
        }
        guard stall >= 0, stall <= 86400 else {
            throw ValidationError("Invalid value for --stall")
        }
        guard watchdog >= 0, watchdog <= 86400 else {
            throw ValidationError("Invalid value for --watchdog")
        }
    }

    func run() throws {
        let urls = try resolvedURLs()
        let status = startDetached(urls: urls, options: options)
        if status != 0 {
            throw ExitCode(status)
        }
    }

    func serveDaemon() -> Int32 {
        guard let urls = try? resolvedURLs() else { return 1 }
        return runDaemon(urls: urls, options: options)
    }

    private var options: RunOptions {
        RunOptions(
            singleScreen: single,
            shuffle: shuffle,
            rate: Float(rate),
            volume: Float(volume),
            waveform: waveform,
            stallLimit: stall,
            watchdogLimit: watchdog)
    }

    private func resolvedURLs() throws -> [URL] {
        var urls: [URL] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                Console.error("File not found: \(url.path)")
                throw ExitCode.failure
            }
            if isDirectory.boolValue {
                let videos = videoFiles(in: url)
                guard !videos.isEmpty else {
                    Console.error("No videos found in: \(url.path)")
                    throw ExitCode.failure
                }
                urls.append(contentsOf: videos)
            } else {
                guard isReadable(url) else {
                    Console.error("No permission to read file: \(url.path)")
                    Console.error("If the file is in Downloads/Desktop/Documents, grant your terminal app access in System Settings > Privacy & Security > Files and Folders, or move the file to an unrestricted folder such as ~/Movies")
                    throw ExitCode.failure
                }
                guard isVideo(url) else {
                    Console.error("Not a video file: \(url.path)")
                    throw ExitCode.failure
                }
                urls.append(url)
            }
        }
        return urls
    }

    private func videoFiles(in directory: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { isVideo($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func isVideo(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]),
              values.isRegularFile == true,
              let type = values.contentType else { return false }
        return type.conforms(to: .movie)
    }

    private func isReadable(_ url: URL) -> Bool {
        let fd = open(url.path, O_RDONLY | O_NONBLOCK)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }

    private func startDetached(urls: [URL], options: RunOptions) -> Int32 {
        let pidFile = PIDFile.shared
        let dataDir = pidFile.url.deletingLastPathComponent()
        let logURL = dataDir.appendingPathComponent("vw.log")
        let lockURL = dataDir.appendingPathComponent("vw.lock")

        do {
            try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        } catch {
            Console.error("Failed to create \(dataDir.path): \(error.localizedDescription)")
            return 1
        }

        let lockFD = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard lockFD >= 0 else {
            Console.error("Failed to open \(lockURL.path): \(String(cString: strerror(errno)))")
            return 1
        }
        defer { close(lockFD) }

        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK {
                reportAlreadyRunning(pidFile)
            } else {
                Console.error("Failed to lock \(lockURL.path): \(String(cString: strerror(errno)))")
            }
            return 1
        }

        if let existing = pidFile.pid, pidFile.isLiveSelf(existing) {
            reportAlreadyRunning(pidFile)
            return 1
        }

        FileManager.default.createFile(atPath: logURL.path, contents: nil)

        do {
            let command = ["run"] + urls.map { $0.path } + optionArguments(options)
            let pid = try Daemon.spawn(detachedCommand: command, logURL: logURL, lockFD: lockFD)
            Console.info("Started (PID \(pid))")
            return 0
        } catch {
            Console.error("Failed to start: \(error.localizedDescription)")
            return 1
        }
    }

    private func reportAlreadyRunning(_ pidFile: PIDFile) {
        if let existing = pidFile.pid, pidFile.isLiveSelf(existing) {
            Console.error("Another instance is running (PID \(existing)), run `\(Version.name) stop` first")
        } else {
            Console.error("Another instance is running, run `\(Version.name) stop` first")
        }
    }

    private func optionArguments(_ options: RunOptions) -> [String] {
        var args: [String] = []
        if options.singleScreen { args.append("--single") }
        if options.shuffle { args.append("--shuffle") }
        if options.waveform { args.append("--waveform") }
        args.append("--rate")
        args.append(String(options.rate))
        args.append("--volume")
        args.append(String(options.volume))
        args.append("--stall")
        args.append(String(options.stallLimit))
        args.append("--watchdog")
        args.append(String(options.watchdogLimit))
        return args
    }

    private func runDaemon(urls: [URL], options: RunOptions) -> Int32 {
        let pidFile = PIDFile.shared

        signal(SIGHUP, SIG_IGN)

        switch pidFile.acquire() {
        case .acquired:
            break
        case .alreadyRunning(let existing):
            Console.error("Another instance is running (PID \(existing)), exiting")
            Darwin.exit(1)
        case .writeFailed(let error):
            Console.error("Failed to write PID file (\(pidFile.url.path)): \(error.localizedDescription)")
            Darwin.exit(1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let playlist = Playlist(urls: urls, shuffle: options.shuffle)
        let wallpaper = Wallpaper(playlist: playlist, options: options)
        let control = ControlServer { command in
            switch command {
            case "mute":
                wallpaper.mute()
                return "Muted"
            case "unmute":
                wallpaper.unmute()
                return "Unmuted"
            case "waveform on":
                wallpaper.setWaveform(true)
                return "Waveform on"
            case "waveform off":
                wallpaper.setWaveform(false)
                return "Waveform off"
            default:
                let prefix = "waveform color "
                guard command.hasPrefix(prefix) else {
                    return "Unknown command"
                }
                guard let color = SpectrumColor.named(String(command.dropFirst(prefix.count))) else {
                    return "Unknown color"
                }
                wallpaper.setSpectrumColor(color)
                return "Waveform color: \(color.name)"
            }
        }
        if control == nil {
            Console.error("Failed to start the control socket")
        }
        wallpaper.start()

        let signalHandler = SignalHandler(signals: [SIGINT, SIGTERM]) {
            control?.shutdown()
            wallpaper.stop()
            PIDFile.shared.remove()
            Darwin.exit(0)
        }
        withExtendedLifetime((signalHandler, control)) {
            app.run()
        }

        wallpaper.stop()
        pidFile.remove()
        return 0
    }
}

enum DaemonEntry {
    static func run(_ arguments: [String]) -> Int32 {
        do {
            let root = try VideoWallpaper.parseAsRoot(arguments)
            guard let command = root as? RunCommand else {
                Console.error("The daemon child expects the run command")
                return 1
            }
            return command.serveDaemon()
        } catch {
            VideoWallpaper.exit(withError: error)
        }
    }
}
