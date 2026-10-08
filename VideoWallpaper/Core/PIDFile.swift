import Foundation

final class PIDFile {
    static let shared = PIDFile()

    let url: URL

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".vw", isDirectory: true)) {
        url = directory.appendingPathComponent("vw.pid")
    }

    var pid: pid_t? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    enum AcquireResult {
        case acquired
        case alreadyRunning(pid: pid_t)
        case writeFailed(Error)
    }

    func acquire(pid: pid_t = ProcessInfo.processInfo.processIdentifier) -> AcquireResult {
        if let existing = self.pid, isLiveSelf(existing) {
            return .alreadyRunning(pid: existing)
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try String(pid).write(to: url, atomically: true, encoding: .utf8)
            return .acquired
        } catch {
            return .writeFailed(error)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    func isLiveSelf(_ pid: pid_t) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 else { return false }
        guard let target = pid.executablePath,
              let own = ProcessInfo.processInfo.processIdentifier.executablePath
        else { return false }
        return target == own
    }
}
