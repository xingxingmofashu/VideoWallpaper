import Foundation

struct MuteCommand: Command {
    let name = "mute"
    let summary = "Mute the running instance"

    func execute(arguments: [String]) -> Int32 {
        ControlClient.send("mute")
    }
}
