import Foundation
import Cocoa
import UniformTypeIdentifiers

struct OptionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct RunOptions {
    var singleScreen = false
    var shuffle = false
    var rate: Float = 1.0
    var volume: Float = 0
    var waveform = false
    var stallLimit: TimeInterval = 8
    var watchdogLimit: TimeInterval = 6

    struct Parsed {
        var paths: [String]
        var options: RunOptions
    }

    static func parse(_ args: [String]) throws -> Parsed {
        var options = RunOptions()
        var paths: [String] = []
        var index = 0

        func nextValue<T>(_ name: String, validate: (T) -> Bool) throws -> T
            where T: LosslessStringConvertible {
            guard index + 1 < args.count,
                  let value = T(args[index + 1]),
                  validate(value) else {
                throw OptionError(message: "Invalid value for \(name)")
            }
            index += 1
            return value
        }

        while index < args.count {
            switch args[index] {
            case "--single":
                options.singleScreen = true
            case "--shuffle":
                options.shuffle = true
            case "--rate":
                options.rate = try nextValue("--rate") { (0.1...1.0).contains($0) }
            case "--volume":
                options.volume = try nextValue("--volume") { (0.0...1.0).contains($0) }
            case "--waveform":
                options.waveform = true
            case "--stall":
                options.stallLimit = try nextValue("--stall") { $0 >= 0 && $0 <= 86400 }
            case "--watchdog":
                options.watchdogLimit = try nextValue("--watchdog") { $0 >= 0 && $0 <= 86400 }
            default:
                guard !args[index].hasPrefix("-") else {
                    throw OptionError(message: "Unknown option: \(args[index])")
                }
                paths.append(args[index])
            }
            index += 1
        }
        return Parsed(paths: paths, options: options)
    }
}

struct RunCommand: Command {
    let name = "run"
    let summary = "<video|dir>... [options]  Play video wallpaper in background"
    let optionsHelp = """
        Options:
          --single              Cover only the main display (default: all screens)
          --shuffle             Play the videos in random order (default: filename order)
          --rate <0.1-1.0>      Max playback rate to lower CPU/GPU load (default: 1.0)
          --volume <0.0-1.0>    Audio volume; 0 keeps it silent (default: 0)
          --waveform            Show audio spectrum bars across the lower desktop
          --stall <seconds>     Auto-exit when playback stalls or never starts within this long, 0 disables (default: 8, max 86400)
          --watchdog <seconds>  Auto-exit if UI is unresponsive this long, 0 disables (default: 6, max 86400)

        Pass one or more videos; a directory plays all videos inside it (not
        recursive) in filename order, one after another. Unplayable videos are
        skipped. The command returns immediately; the wallpaper keeps playing
        after the terminal is closed. Stop it with `vw stop`. Errors go to
        ~/.vw/vw.log.
        """

    func execute(arguments: [String]) -> Int32 {
        guard let input = validatedInput(arguments) else { return 1 }
        return startDetached(urls: input.urls, options: input.options)
    }

    func executeDaemon(arguments: [String]) -> Int32 {
        let args = arguments.first == "run" ? Array(arguments.dropFirst()) : arguments
        guard let input = validatedInput(args) else { return 1 }
        return runDaemon(urls: input.urls, options: input.options)
    }

    private func validatedInput(_ arguments: [String]) -> (urls: [URL], options: RunOptions)? {
        let parsed: RunOptions.Parsed
        do {
            parsed = try RunOptions.parse(arguments)
        } catch {
            Console.error("\(error.localizedDescription)")
            return nil
        }

        guard !parsed.paths.isEmpty else {
            Console.error("Missing video path")
            Console.info(HelpCommand().usage())
            return nil
        }

        var urls: [URL] = []
        for path in parsed.paths {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                Console.error("File not found: \(url.path)")
                return nil
            }
            if isDirectory.boolValue {
                let videos = videoFiles(in: url)
                guard !videos.isEmpty else {
                    Console.error("No videos found in: \(url.path)")
                    return nil
                }
                urls.append(contentsOf: videos)
            } else {
                guard isReadable(url) else {
                    Console.error("No permission to read file: \(url.path)")
                    Console.error("If the file is in Downloads/Desktop/Documents, grant your terminal app access in System Settings > Privacy & Security > Files and Folders, or move the file to an unrestricted folder such as ~/Movies")
                    return nil
                }
                guard isVideo(url) else {
                    Console.error("Not a video file: \(url.path)")
                    return nil
                }
                urls.append(url)
            }
        }
        return (urls, parsed.options)
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
            exit(1)
        case .writeFailed(let error):
            Console.error("Failed to write PID file (\(pidFile.url.path)): \(error.localizedDescription)")
            exit(1)
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
                return "Unknown command"
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
            exit(0)
        }
        withExtendedLifetime((signalHandler, control)) {
            app.run()
        }

        wallpaper.stop()
        pidFile.remove()
        return 0
    }
}
