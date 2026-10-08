import ArgumentParser
import Foundation

enum InstallMethod {
    case installer
    case homebrew
    case manual

    static func detect() -> InstallMethod {
        guard let path = ProcessInfo.processInfo.processIdentifier.executablePath else { return .manual }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if resolved == Paths.binary.resolvingSymlinksInPath().path { return .installer }
        if resolved.contains("/Cellar/") { return .homebrew }
        return .manual
    }

    var name: String {
        switch self {
        case .installer: return "installer"
        case .homebrew: return "brew"
        case .manual: return "manual"
        }
    }
}

extension InstallMethod: ExpressibleByArgument {
    init?(argument: String) {
        switch argument {
        case "installer", "curl":
            self = .installer
        case "brew", "homebrew":
            self = .homebrew
        case "manual":
            self = .manual
        default:
            return nil
        }
    }

    static var allValueStrings: [String] { ["installer", "brew", "manual"] }
}
