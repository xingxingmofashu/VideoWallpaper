import Foundation
import Darwin

enum SpawnError: LocalizedError {
    case executableNotFound
    case spawnFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .executableNotFound: return "cannot locate current executable"
        case .spawnFailed(let code): return String(cString: strerror(code))
        }
    }
}

extension pid_t {
    var executablePath: String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let size = proc_pidpath(self, &buffer, UInt32(buffer.count))
        guard size > 0 else { return nil }
        return String(cString: buffer)
    }
}

enum Daemon {
    static let flag = "--vw-daemon-child"
    /// Re-exec self with POSIX_SPAWN_SETSID so the child survives terminal close;
    /// stdin goes to /dev/null, stdout/stderr append to the log file.
    /// The daemon flag is always prepended so the child enters daemon mode.
    /// The held flock on `lockFD` is inherited as fd 3, keeping the single-instance
    /// lock alive for exactly the daemon's lifetime.
    static func spawn(detachedCommand arguments: [String], logURL: URL, lockFD: Int32) throws -> pid_t {
        guard let exePath = ProcessInfo.processInfo.processIdentifier.executablePath else {
            throw SpawnError.executableNotFound
        }

        let exe = strdup(exePath)!
        let flag = strdup(Daemon.flag)!
        let args = arguments.map { strdup($0)! }
        let argv: [UnsafeMutablePointer<CChar>?] = [exe, flag] + args + [nil]

        let logPath = strdup(logURL.path)!

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, logPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, logPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_adddup2(&actions, lockFD, 3)
        if lockFD != 3 {
            posix_spawn_file_actions_addclose(&actions, lockFD)
        }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, exe, &actions, &attr, argv, environ)

        free(exe)
        free(flag)
        free(logPath)
        args.forEach { free($0) }
        posix_spawnattr_destroy(&attr)
        posix_spawn_file_actions_destroy(&actions)

        guard rc == 0 else { throw SpawnError.spawnFailed(rc) }
        return pid
    }
}
