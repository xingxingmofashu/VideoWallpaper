import ArgumentParser
import Foundation

struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Stop the instance, remove the binary and runtime data")

    func run() throws {
        guard InstanceControl.stop() == 0 else {
            throw ExitCode.failure
        }

        var failed = false

        if let binaryPath = ProcessInfo.processInfo.processIdentifier.executablePath {
            do {
                try FileManager.default.removeItem(atPath: binaryPath)
                Console.info("Removed \(binaryPath)")
            } catch {
                Console.error("Failed to remove \(binaryPath): \(error.localizedDescription)")
                Console.error("Run manually: sudo rm -f \(binaryPath)")
                failed = true
            }
        } else {
            Console.error("Could not locate the running binary")
            failed = true
        }

        let dataDir = PIDFile.shared.url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: dataDir.path) {
            do {
                try FileManager.default.removeItem(at: dataDir)
                Console.info("Removed \(dataDir.path)")
            } catch {
                Console.error("Failed to remove \(dataDir.path): \(error.localizedDescription)")
                failed = true
            }
        }

        if failed {
            Console.error("Uninstall incomplete")
            throw ExitCode.failure
        }
        Console.info("Uninstalled")
    }
}
