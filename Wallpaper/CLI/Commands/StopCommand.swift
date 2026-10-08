import ArgumentParser
import Foundation

enum InstanceControl {
    static func stop() -> Int32 {
        let pidFile = PIDFile.shared
        guard let pid = pidFile.pid else {
            Console.info("No running instance")
            return 0
        }

        guard pidFile.isLiveSelf(pid) else {
            Console.info("Recorded PID \(pid) is not this program, cleaned up")
            pidFile.remove()
            return 0
        }

        kill(pid, SIGTERM)

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if !pidFile.isLiveSelf(pid) {
                pidFile.remove()
                Console.info("Stopped")
                return 0
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        Console.error("Process \(pid) did not exit within 3s, try `kill -9 \(pid)`")
        return 1
    }
}

struct StopCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the running instance")

    func run() throws {
        let status = InstanceControl.stop()
        if status != 0 {
            throw ExitCode(status)
        }
    }
}
