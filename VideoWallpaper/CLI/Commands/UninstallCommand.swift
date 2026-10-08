import ArgumentParser
import Darwin
import Foundation

struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Stop the instance and remove vw, its runtime data and shell PATH entry")

    @Flag(name: .long, help: "Show what would be removed without removing anything")
    var dryRun = false

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt")
    var force = false

    func run() throws {
        let method = InstallMethod.detect()
        let directories = [Paths.data, Paths.state, Paths.config]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        let shell = ShellConfig.modified()
        let binaryPath = ProcessInfo.processInfo.processIdentifier.executablePath

        Console.info("Installation method: \(method.name)")
        Console.info("The following will be removed:")
        for directory in directories {
            Console.info("  \(directory.path)")
        }
        for file in shell {
            Console.info("  Shell PATH entry in \(file.path)")
        }
        switch method {
        case .installer:
            Console.info("  Binary: \(Paths.binary.path)")
        case .homebrew:
            Console.info("  Binary: managed by Homebrew, run `brew uninstall vw`")
        case .manual:
            Console.info("  Binary (manual removal): \(binaryPath ?? Paths.binary.path)")
        }

        if dryRun {
            Console.info("Dry run - nothing removed")
            return
        }

        if !force {
            guard isatty(STDIN_FILENO) == 1 else {
                throw ValidationError("Refusing to uninstall without confirmation; pass --force")
            }
            Console.info("Continue? [y/N] ")
            let answer = (readLine() ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            guard answer == "y" || answer == "yes" else {
                Console.info("Cancelled")
                throw ExitCode.success
            }
        }

        guard InstanceControl.stop() == 0 else {
            throw ExitCode.failure
        }

        var failed = false

        for directory in directories {
            do {
                try FileManager.default.removeItem(at: directory)
                Console.info("Removed \(directory.path)")
            } catch {
                Console.error("Failed to remove \(directory.path): \(error.localizedDescription)")
                failed = true
            }
        }

        for file in shell {
            do {
                let content = try String(contentsOf: file, encoding: .utf8)
                try ShellConfig.clean(content).write(to: file, atomically: true, encoding: .utf8)
                Console.info("Removed the PATH entry from \(file.path)")
            } catch {
                Console.error("Failed to update \(file.path): \(error.localizedDescription)")
                failed = true
            }
        }

        switch method {
        case .installer:
            removeBinary(Paths.binary, pruning: Paths.binaryDirectory, failed: &failed)
        case .homebrew:
            Console.info("The binary is managed by Homebrew; run: brew uninstall vw")
        case .manual:
            if let binaryPath {
                removeBinary(URL(fileURLWithPath: binaryPath), pruning: nil, failed: &failed)
            } else {
                Console.error("Could not locate the running binary")
                failed = true
            }
        }

        if failed {
            Console.error("Uninstall incomplete")
            throw ExitCode.failure
        }
        Console.info("Uninstalled")
    }

    private func removeBinary(_ url: URL, pruning parent: URL?, failed: inout Bool) {
        do {
            try FileManager.default.removeItem(at: url)
            Console.info("Removed \(url.path)")
        } catch {
            Console.error("Failed to remove \(url.path): \(error.localizedDescription)")
            Console.error("Run manually: sudo rm -f \(url.path)")
            failed = true
            return
        }

        guard let parent else { return }
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        guard remaining.isEmpty else { return }
        try? FileManager.default.removeItem(at: parent)
        try? FileManager.default.removeItem(at: parent.deletingLastPathComponent())
    }
}
