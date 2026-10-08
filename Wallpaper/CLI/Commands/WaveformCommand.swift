import Foundation

struct WaveformCommand: Command {
    let name = "waveform"
    let summary = "Turn the desktop waveform on or off, or switch its color"

    func execute(arguments: [String]) -> Int32 {
        guard let mode = arguments.first else {
            return usage()
        }
        switch mode {
        case "on", "off":
            guard arguments.count == 1 else {
                return usage()
            }
            return ControlClient.send("waveform \(mode)")
        case "color":
            guard arguments.count == 2, SpectrumColor.named(arguments[1]) != nil else {
                return usage()
            }
            return ControlClient.send("waveform color \(arguments[1])")
        default:
            return usage()
        }
    }

    private func usage() -> Int32 {
        Console.error("Usage: \(Version.name) waveform on|off")
        Console.error("       \(Version.name) waveform color default|gradient")
        return 1
    }
}
