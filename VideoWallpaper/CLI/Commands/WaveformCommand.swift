import ArgumentParser

struct WaveformCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "waveform",
        abstract: "Turn the desktop waveform on or off, or switch its color",
        subcommands: [On.self, Off.self, Color.self])

    func run() throws {
        throw CleanExit.helpRequest(self)
    }

    struct On: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "on",
            abstract: "Turn the desktop waveform on")

        func run() throws {
            let status = ControlClient.send("waveform on")
            if status != 0 {
                throw ExitCode(status)
            }
        }
    }

    struct Off: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "off",
            abstract: "Turn the desktop waveform off")

        func run() throws {
            let status = ControlClient.send("waveform off")
            if status != 0 {
                throw ExitCode(status)
            }
        }
    }

    struct Color: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "color",
            abstract: "Switch the waveform color")

        @Argument(help: "The waveform color.")
        var color: SpectrumColor

        func run() throws {
            let status = ControlClient.send("waveform color \(color.name)")
            if status != 0 {
                throw ExitCode(status)
            }
        }
    }
}

extension SpectrumColor: ExpressibleByArgument {
    init?(argument: String) {
        guard let value = SpectrumColor.named(argument) else { return nil }
        self = value
    }

    static var allValueStrings: [String] {
        ["default", "gradient"]
    }
}
