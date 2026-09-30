import Foundation

enum SoundControl {
    static func signal(_ sig: Int32, confirmation: String) -> Int32 {
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

        guard kill(pid, sig) == 0 else {
            Console.error("Failed to signal process \(pid): \(String(cString: strerror(errno)))")
            return 1
        }

        Console.info(confirmation)
        return 0
    }
}
