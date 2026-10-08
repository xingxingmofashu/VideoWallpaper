import ArgumentParser

struct UnmuteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unmute",
        abstract: "Unmute the running instance")

    func run() throws {
        let status = ControlClient.send("unmute")
        if status != 0 {
            throw ExitCode(status)
        }
    }
}
