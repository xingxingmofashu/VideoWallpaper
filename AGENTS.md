# AGENTS.md

## Build / verify

- Building is the only verification step: `xcodebuild -project Wallpaper.xcodeproj -scheme Wallpaper -configuration Debug build`. Single target/scheme, no tests, no lint config.
- `./Scripts/install.sh` builds Release into `./build/` and installs. Install dir resolution: `$VW_PREFIX` > writable `/usr/local/bin` > writable `/opt/homebrew/bin` > `/usr/local/bin` via sudo.
- install.sh must `rm` the old binary before `cp`: overwriting a signed binary in place (same inode) makes macOS SIGKILL it on next exec (exit 137).
- Build products: Debug lands in DerivedData (`~/Library/Developer/Xcode/DerivedData/Wallpaper-*/Build/Products/Debug/Wallpaper`); Release via install.sh (it passes `-derivedDataPath build`) lands in `./build/Build/Products/Release/Wallpaper` - not in DerivedData.
- The pbxproj uses `PBXFileSystemSynchronizedRootGroup`: adding/removing/renaming .swift files requires no project-file edits.

## Architecture

- Entry `Wallpaper/main.swift` -> `CLI.run` (`Wallpaper/CLI/CLI.swift`); `Command` protocol in `CLI/Command.swift`, one struct per subcommand in `CLI/Commands/`.
- `Wallpaper/Core/`: `Wallpaper.swift` (per-screen desktop-level NSWindow + AVQueuePlayer playlist; stall/heartbeat/watchdog timers), `Playlist.swift` (ordered or shuffled URL rotation), `Daemon.swift` (re-exec self via posix_spawn, POSIX_SPAWN_SETSID, stdio -> `~/.vw/vw.log`), `PIDFile.swift`, `SignalHandler.swift`.
- `vw run` daemonizes: parent prints `Started (PID n)` and exits; daemon errors are only visible in `~/.vw/vw.log` (truncated at each start).
- Single instance via `flock` on `~/.vw/vw.lock`: parent acquires, daemon inherits the held lock as fd 3 (`posix_spawn_file_actions_adddup2`); the lock releases automatically when the daemon exits or is killed.
- Daemon argv is `[exe, --vw-daemon-child, run, <video>..., --rate <f>, --volume <f>, --stall <f>, --watchdog <f>]` (`--shuffle` is appended when set); the flag is prepended inside `Daemon.spawn`. Never construct daemon argv without the flag - a missing flag makes the child spawn again (fork bomb). `CLI.run` dispatches `Daemon.flag` before command lookup.
- Run-option values are Doubles serialized as strings into the daemon argv (`optionArguments`) and capped by `RunOptions.parse` (rate 0.1-1.0, volume 0-1.0, stall/watchdog <= 86400). Never convert user-provided Doubles with `Int()` - `--stall 1e30` once crashed the parent via the `Int(Double)` trap.
- Runtime audio control: `vw mute` / `vw unmute` send `SIGUSR1` / `SIGUSR2` to the daemon (guarded by `PIDFile.isLiveSelf`); `SignalHandler` maps them to `Wallpaper.mute()/unmute()`, while `SIGINT`/`SIGTERM` stop the daemon.
- `PIDFile.isLiveSelf` compares `proc_pidpath` output on BOTH sides (self and target). Do not derive the self path from `CommandLine.arguments[0]` - via PATH lookup it is a bare name and the comparison always fails, silently breaking `vw stop` and the single-instance guard.

## Conventions (differ from defaults)

- Code contains no comments at all (user preference). Do not add comments.
- All runtime CLI output must be English only (user terminals may not render Chinese): Console messages, help text, log lines.
- Chinese prose belongs in README.zh_CN.md only.

## macOS 26 SDK quirks

- `posix_spawnattr_t` / `posix_spawn_file_actions_t` are opaque pointers here: declare `var attr: posix_spawnattr_t?` and pass `&attr`; `posix_spawnattr_t()` does not compile.
- `fork()` is unavailable in Swift - use posix_spawn.
- `kCGDesktopWindowLevel` and similar constants are not Swift-visible; use `CGWindowLevelForKey(.desktopWindow)`.

## Release

- Push tag `v*` -> `.github/workflows/release.yml` (runs-on macos-26) builds with `CODE_SIGNING_ALLOWED=NO` (the pbxproj pins a DEVELOPMENT_TEAM that does not exist on CI), ad-hoc signs (`codesign -f -s -`), uploads the fixed-name asset `vw-macos-arm64.tar.gz` and creates the GitHub release.
- The workflow asserts the tag equals `Version.number` in `VersionCommand.swift` - bump both together.
- `Scripts/install.sh` is dual-mode: inside the repo it builds from source; without a repo (curl | bash) it downloads the release asset (`VW_VERSION` pins a version, default latest).

## Branch protection

- main requires the `build` status check (`.github/workflows/ci.yml`) and forbids force pushes and deletion. Admins bypass checks on direct pushes (`enforce_admins` off) - direct pushes print a "Bypassed rule violations" notice and still land.
- The required check context must stay in sync with the job name in ci.yml - renaming the job silently breaks PR merging.

## Runtime files

`~/.vw/vw.pid` (daemon PID, written by the daemon), `~/.vw/vw.lock` (flock), `~/.vw/vw.log` (daemon stdout/stderr).
