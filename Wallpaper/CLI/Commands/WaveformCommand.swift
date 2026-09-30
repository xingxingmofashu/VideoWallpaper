import Foundation

struct WaveformCommand: Command {
    let name = "waveform"
    let summary = "Turn the desktop waveform on or off"

    func execute(arguments: [String]) -> Int32 {
        guard let mode = arguments.first, mode == "on" || mode == "off" else {
            Console.error("Usage: \(Version.name) waveform on|off")
            return 1
        }
        return ControlClient.send("waveform \(mode)")
    }
}
