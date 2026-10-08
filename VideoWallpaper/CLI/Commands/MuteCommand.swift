import ArgumentParser

struct MuteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mute",
        abstract: "Mute the running instance")

    func run() throws {
        let status = ControlClient.send("mute")
        if status != 0 {
            throw ExitCode(status)
        }
    }
}
