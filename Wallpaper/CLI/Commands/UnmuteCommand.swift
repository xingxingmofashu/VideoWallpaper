import Foundation

struct UnmuteCommand: Command {
    let name = "unmute"
    let summary = "Unmute the running instance"

    func execute(arguments: [String]) -> Int32 {
        SoundControl.signal(SIGUSR2, confirmation: "Unmuted")
    }
}
