# AGENTS.md

## Build / verify

- Building is the only verification step: `xcodebuild -project VideoWallpaper.xcodeproj -scheme VideoWallpaper -configuration Debug build`. Single target/scheme, no tests, no lint config.
- `./Scripts/install.sh` builds Release into `./build/` and installs the binary to `$VW_PREFIX` (when set) or `$HOME/.vw/bin`, then appends that directory to the shell config unless `--no-modify-path` is set or `VW_PREFIX` is used. No sudo anywhere. Flags: `-v/--version`, `-b/--binary`.
- install.sh must `rm` the old binary before `cp`: overwriting a signed binary in place (same inode) makes macOS SIGKILL it on next exec (exit 137).
- Build products: Debug lands in DerivedData (`~/Library/Developer/Xcode/DerivedData/VideoWallpaper-*/Build/Products/Debug/VideoWallpaper`); Release via install.sh (it passes `-derivedDataPath build`) lands in `./build/Build/Products/Release/VideoWallpaper` - not in DerivedData.
- The pbxproj uses `PBXFileSystemSynchronizedRootGroup`: adding/removing/renaming .swift files requires no project-file edits.
- The only third-party dependency is `swift-argument-parser`, wired in through `XCRemoteSwiftPackageReference` / `XCSwiftPackageProductDependency` and pinned in `VideoWallpaper.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (commit it). Builds resolve the package over the network, so CI and the release workflow need network access.
- The CLI is built on swift-argument-parser: the root is `VideoWallpaper` with `defaultSubcommand: RunCommand.self`, so `vw <video>` means `vw run <video>`. Argument errors exit 64 (`EX_USAGE`) and print ArgumentParser's own format; runtime failures print through `Console.error` and exit 1. `vw` with no arguments is shimmed to `--help` in `main.swift` because the default subcommand would otherwise run `run` and fail validation.

## Architecture

- Entry `VideoWallpaper/main.swift`: dispatches `Daemon.flag` and `-v` itself, then hands off to `VideoWallpaper.main()` (`VideoWallpaper/CLI/VideoWallpaper.swift`, the root `ParsableCommand`); one `ParsableCommand` per subcommand in `CLI/Commands/`.
- `VideoWallpaper/Core/`: `Paths.swift` (XDG roots - data/state/config/cache under `$XDG_*` or `~/.local/share`, `~/.local/state`, `~/.config`, `~/.cache`, plus the `~/.vw/bin` binary; `Paths.home` honors `VW_TEST_HOME`), `Wallpaper.swift` (per-screen desktop-level NSWindow + AVQueuePlayer playlist; stall/heartbeat/watchdog timers; spectrum overlay hosts), `Playlist.swift` (ordered or shuffled URL rotation), `ControlServer.swift` (unix socket runtime control), `Daemon.swift` (re-exec self via posix_spawn, POSIX_SPAWN_SETSID, stdio -> `~/.local/share/vw/vw.log`), `PIDFile.swift`, `SignalHandler.swift`, `InstallMethod.swift`, `ShellConfig.swift`.
- `VideoWallpaper/Core/Waveform/`: `AudioSpectrum.swift` (MTAudioProcessingTap + vDSP FFT band meter), `SpectrumStore.swift` (band levels, color and visibility published to SwiftUI), `SpectrumView.swift` (bottom anchored spectrum bars).
- `vw run` daemonizes: parent prints `Started (PID n)` and exits; daemon errors are only visible in `~/.local/share/vw/vw.log` (truncated at each start).
- Single instance via `flock` on `~/.local/state/vw/vw.lock`: parent acquires, daemon inherits the held lock as fd 3 (`posix_spawn_file_actions_adddup2`); the lock releases automatically when the daemon exits or is killed.
- Daemon argv is `[exe, --vw-daemon-child, run, <video>..., --rate <f>, --volume <f>, --stall <f>, --watchdog <f>]` (`--shuffle` and `--waveform` are appended when set); the flag is prepended inside `Daemon.spawn`. Never construct daemon argv without the flag - a missing flag makes the child spawn again (fork bomb). `main.swift` dispatches `Daemon.flag` before ArgumentParser ever sees the arguments.
- Run-option values are Doubles serialized as strings into the daemon argv (`optionArguments`) and capped by `RunCommand.validate()` (rate 0.1-1.0, volume 0-1.0, stall/watchdog <= 86400). Never convert user-provided Doubles with `Int()` - `--stall 1e30` once crashed the parent via the `Int(Double)` trap.
- Runtime control: `ControlServer` (`Core/ControlServer.swift`) listens on `~/.local/state/vw/vw.sock`; `vw mute`, `vw unmute`, `vw waveform on|off` and `vw waveform color default|gradient` (`CLI/ControlClient.swift`) send one command line over it. `SIGINT`/`SIGTERM` still stop the daemon; `SignalHandler` no longer maps `SIGUSR1`/`SIGUSR2`.
- `PIDFile.isLiveSelf` compares `proc_pidpath` output on BOTH sides (self and target). Do not derive the self path from `CommandLine.arguments[0]` - via PATH lookup it is a bare name and the comparison always fails, silently breaking `vw stop` and the single-instance guard.

## Conventions (differ from defaults)

- Code contains no comments at all (user preference). Do not add comments.
- All runtime CLI output must be English only (user terminals may not render Chinese): Console messages, help text, log lines.
- Chinese prose belongs in README.zh_CN.md only.

## macOS 26 SDK quirks

- `posix_spawnattr_t` / `posix_spawn_file_actions_t` are opaque pointers here: declare `var attr: posix_spawnattr_t?` and pass `&attr`; `posix_spawnattr_t()` does not compile.
- `fork()` is unavailable in Swift - use posix_spawn.
- `kCGDesktopWindowLevel` and similar constants are not Swift-visible; use `CGWindowLevelForKey(.desktopWindow)`.

## Install and upgrade

- `Paths` (`Core/Paths.swift`) is the single source of truth for every runtime path - nothing else may join `~/.vw` by hand. `Paths.home` honors `VW_TEST_HOME`, which sandboxes the whole CLI in tests.
- `InstallMethod.detect()` classifies the running binary: `installer` when the resolved exec path equals `Paths.binary` (`~/.vw/bin/vw`), `brew` when it contains `/Cellar/`, otherwise `manual`. Both `vw uninstall` and `vw upgrade` branch on it.
- `vw uninstall` removes the XDG data/state/config directories, cleans the PATH entry out of the shell config (only while `~/.vw/bin` holds nothing but `vw`) and removes the binary for an `installer` install; for `brew` it only prints `brew uninstall vw`.
- `vw upgrade` re-runs the published `Scripts/install.sh` for an `installer` install and `brew upgrade vw` for a Homebrew install; with no argument it reads the latest tag from the GitHub API.
- Homebrew distribution is the tap `xingxingmofashu/homebrew-tap` (`Formula/vw.rb`, a binary formula). `.github/workflows/release.yml` bumps its url+sha256 on every tag when the `TAP_TOKEN` secret is set.

## Release

- Push tag `v*` -> `.github/workflows/release.yml` (runs-on macos-26) builds with `CODE_SIGNING_ALLOWED=NO` (the pbxproj pins a DEVELOPMENT_TEAM that does not exist on CI), ad-hoc signs (`codesign -f -s -`), uploads the fixed-name asset `vw-macos-arm64.tar.gz` and creates the GitHub release.
- The workflow asserts the tag equals `Version.number` in `VersionCommand.swift` - bump both together.
- `Scripts/install.sh` is dual-mode: inside the repo (with no explicit `--version`/`--binary`) it builds from source; otherwise it downloads the release asset. `--version`/`VW_VERSION` pin a version, default latest. The layout mirrors opencode's installer: `$HOME/.vw/bin`, a shell-config PATH edit, and a progress bar.

## Branch protection

- main requires the `build` status check (`.github/workflows/ci.yml`) and forbids force pushes and deletion. Admins bypass checks on direct pushes (`enforce_admins` off) - direct pushes print a "Bypassed rule violations" notice and still land.
- The required check context must stay in sync with the job name in ci.yml - renaming the job silently breaks PR merging.

## Runtime files

`~/.local/state/vw/vw.pid` (daemon PID, written by the daemon), `~/.local/state/vw/vw.lock` (flock), `~/.local/state/vw/vw.sock` (runtime control socket), `~/.local/share/vw/vw.log` (daemon stdout/stderr), `~/.vw/bin/vw` (binary). All of them go through `Paths`.
