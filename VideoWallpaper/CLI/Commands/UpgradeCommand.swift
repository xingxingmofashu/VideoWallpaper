import ArgumentParser
import Foundation

struct UpgradeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "upgrade",
        abstract: "Upgrade vw to the latest or a specific version",
        aliases: ["update"])

    @Argument(help: "Version to upgrade to (with or without a leading v)")
    var target: String?

    @Option(name: .shortAndLong, help: "Installation method to use")
    var method: InstallMethod?

    func run() throws {
        let method = self.method ?? InstallMethod.detect()
        Console.info("Using method: \(method.name)")

        let version = try resolvedVersion()
        guard version != Version.number else {
            Console.info("\(Version.name) upgrade skipped: \(version) is already installed")
            return
        }

        Console.info("From \(Version.number) to \(version)")
        switch method {
        case .installer:
            try runInstaller(version: version)
        case .homebrew:
            try run("/usr/bin/env", ["brew", "upgrade", Version.name])
        case .manual:
            throw ValidationError("Could not detect the installation method; reinstall with the installer or Homebrew")
        }
        Console.info("Upgraded to \(version)")
        warnAboutRunningInstance()
    }

    private func resolvedVersion() throws -> String {
        if let target, !target.isEmpty {
            return target.hasPrefix("v") ? String(target.dropFirst()) : target
        }
        guard let url = URL(string: Project.latestReleaseURL) else {
            throw ValidationError("Invalid release URL")
        }
        let data = try fetch(url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String else {
            throw ValidationError("Could not read the latest release version")
        }
        return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    private func runInstaller(version: String) throws {
        guard let url = URL(string: Project.installerURL) else {
            throw ValidationError("Invalid installer URL")
        }
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("vw-install-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: script) }
        try fetch(url).write(to: script)
        try run("/bin/bash", [script.path, "--version", version, "--no-modify-path"])
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ExitCode(process.terminationStatus)
        }
    }

    private func fetch(_ url: URL) throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("\(Version.name)/\(Version.number)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Result<Data, Error>?
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                outcome = .failure(error)
            } else if let data {
                outcome = .success(data)
            } else {
                outcome = .failure(URLError(.badServerResponse))
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()

        guard let outcome else { throw URLError(.unknown) }
        return try outcome.get()
    }

    private func warnAboutRunningInstance() {
        let pidFile = PIDFile.shared
        guard let pid = pidFile.pid, pidFile.isLiveSelf(pid) else { return }
        Console.info("The running instance (PID \(pid)) still uses the previous version; run `\(Version.name) stop` and start it again")
    }
}
