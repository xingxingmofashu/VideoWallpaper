import Foundation

enum ShellConfig {
    static let marker = "# vw"

    static func modified() -> [URL] {
        guard ownsBinaryDirectory() else { return [] }
        return candidates().filter { isModified($0) }
    }

    static func isModified(_ url: URL) -> Bool {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return clean(content) != content
    }

    static func clean(_ content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var kept: [String] = []
        for (index, line) in lines.enumerated() {
            if isPathEntry(line) { continue }
            if line.trimmingCharacters(in: .whitespaces) == marker,
               index + 1 < lines.count,
               isPathEntry(lines[index + 1]) {
                continue
            }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }

    static func candidates() -> [URL] {
        let home = Paths.home
        let xdg = environment("XDG_CONFIG_HOME")
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".config", isDirectory: true)
        let zdot = environment("ZDOTDIR").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? home

        switch (environment("SHELL") as NSString?)?.lastPathComponent ?? "bash" {
        case "fish":
            return [
                home.appendingPathComponent(".config/fish/config.fish"),
                xdg.appendingPathComponent("fish/config.fish"),
            ]
        case "zsh":
            return [
                zdot.appendingPathComponent(".zshrc"),
                zdot.appendingPathComponent(".zshenv"),
                xdg.appendingPathComponent("zsh/.zshrc"),
                xdg.appendingPathComponent("zsh/.zshenv"),
            ]
        case "ash", "sh":
            return [
                home.appendingPathComponent(".ashrc"),
                home.appendingPathComponent(".profile"),
            ]
        default:
            return [
                home.appendingPathComponent(".bashrc"),
                home.appendingPathComponent(".bash_profile"),
                home.appendingPathComponent(".profile"),
                xdg.appendingPathComponent("bash/.bashrc"),
                xdg.appendingPathComponent("bash/.bash_profile"),
            ]
        }
    }

    private static func ownsBinaryDirectory() -> Bool {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: Paths.binaryDirectory.path)) ?? []
        return entries.allSatisfy { $0 == Paths.binary.lastPathComponent }
    }

    private static func isPathEntry(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("export PATH=") || trimmed.hasPrefix("fish_add_path ") else { return false }
        return trimmed.contains("/.vw/bin")
    }

    private static func environment(_ name: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else { return nil }
        return value
    }
}
