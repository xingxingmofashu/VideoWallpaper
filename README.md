<div align="center">

# VideoWallpaper

**Loop a video as your macOS desktop wallpaper from the terminal.**

<p align="center">
  <a href="https://github.com/xingxingmofashu/Wallpaper/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/xingxingmofashu/Wallpaper?style=flat-square" /></a>
  <a href="https://github.com/xingxingmofashu/Wallpaper/actions/workflows/ci.yml"><img alt="Build status" src="https://img.shields.io/github/actions/workflow/status/xingxingmofashu/Wallpaper/ci.yml?style=flat-square&branch=main" /></a>
</p>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README.zh_CN.md">简体中文</a>
</p>

https://github.com/user-attachments/assets/ba9da556-17c4-467a-b038-0a58b88e45d8

<p align="center"><sub>Preview artwork by <a href="https://www.wlop.art">WLOP</a></sub></p>

</div>

---

```bash
vw run ~/Videos/wallpaper.mov      # start (returns immediately)
vw stop                            # stop
```

## Features

- Plays any local video, looping, on **all screens** or only the main display
- Play a playlist: pass several files or a directory to play them one after another, in filename order or `--shuffle`
- Silent by default; set `--volume <0.0-1.0>` to play the video's audio
- Toggle the running instance's audio at any time with `vw mute` / `vw unmute`
- Optional audio spectrum bars across the lower desktop (`--waveform`); they follow the video's own audio and settle while muted
- Detached daemon: keeps playing after the terminal closes; `vw run` exits immediately with `Started (PID n)`
- Single-instance lock (`flock`); concurrent starts fail fast with a clear message
- Self-protection: exits on decoder failure, playback stall (8 s by default) or main-thread freeze (6 s by default), instead of showing a frozen desktop forever
- Stable across display sleep/wake, lock/unlock and resolution changes; windows are only rebuilt when the screen configuration actually changes
- English-only CLI output

## Requirements

- Apple Silicon Mac, macOS 26.2+
- Xcode (for `xcodebuild`) — required to build, not needed at runtime

## Install

One line, no clone needed (downloads the latest release):

```bash
curl -fsSL https://raw.githubusercontent.com/xingxingmofashu/Wallpaper/main/Scripts/install.sh | bash
```

Or build from source:

```bash
git clone https://github.com/xingxingmofashu/Wallpaper.git
cd Wallpaper
./Scripts/install.sh
```

Either way the script installs to the first writable location in this order:
`$VW_PREFIX`, `/usr/local/bin` (sudo only if needed), `/opt/homebrew/bin`, and removes
the previous binary before copying, because overwriting a signed binary in place
(same inode) gets SIGKILLed by macOS on next launch.

Uninstall:

```bash
vw uninstall                                         # using the installed CLI
./Scripts/install.sh --uninstall                    # from a clone
curl -fsSL https://raw.githubusercontent.com/xingxingmofashu/Wallpaper/main/Scripts/install.sh | bash -s -- --uninstall
```

## Usage

```text
vw run <video|dir>... [options]   play video wallpaper in background
vw stop                    stop the running instance
vw mute                    mute the running instance's audio
vw unmute                  unmute the running instance's audio
vw waveform on|off         turn the desktop waveform on or off
vw waveform color          switch the waveform color (default|gradient)
vw uninstall               stop the instance, remove the binary and runtime data
vw version                 show version
vw help                    show full help
```

`vw <video>` (without `run`) also works as a shorthand.

### run options

| Option | Description | Default |
|---|---|---|
| `--single` | cover only the main display | all screens |
| `--shuffle` | play the videos in random order | filename order |
| `--rate <0.1-1.0>` | cap playback rate to lower CPU/GPU load | `1.0` |
| `--volume <0.0-1.0>` | audio volume; `0` keeps playback silent | `0` |
| `--waveform` | show audio spectrum bars across the lower desktop | off |
| `--stall <seconds>` | auto-exit after playback stalls this long; `0` disables (max 86400) | `8` |
| `--watchdog <seconds>` | auto-exit if the main thread is unresponsive this long; `0` disables (max 86400) | `6` |

Examples:

```bash
vw run ~/Videos/wallpaper.mov --single --rate 0.5
vw run ~/Videos/wallpaper.mov --volume 0.4 --waveform        # sound + waveform
vw run ~/Videos/wallpapers --shuffle                    # every video in a folder, shuffled
vw run ~/Videos/wallpaper.mov --stall 0 --watchdog 0   # disable auto-exit guards
```

## How it works

- `vw run` re-executes itself via `posix_spawn` with `POSIX_SPAWN_SETSID`: the daemon
  detaches from the terminal (survives close, SIGHUP ignored), stdin goes to `/dev/null`,
  and stdout/stderr append to `~/.vw/vw.log`.
- The daemon writes `~/.vw/vw.pid`; `vw stop` verifies the PID actually belongs to
  `vw` (`proc_pidpath` on both sides) before sending `SIGTERM`.
- A held `flock` on `~/.vw/vw.lock` is inherited by the daemon, so the single-instance
  guarantee covers the whole daemon lifetime and releases automatically on exit or kill.
- One borderless `NSWindow` per screen at the desktop window level with an
  `AVPlayerLayer`; windows are rebuilt only when the screen configuration really changes.
- The playlist keeps the next video queued on a single `AVQueuePlayer` so items
  advance back to back; a directory expands to its videos (non-recursive), and
  unplayable files are skipped.

### Runtime files

| Path | Purpose |
|---|---|
| `~/.vw/vw.pid` | PID of the running daemon |
| `~/.vw/vw.lock` | single-instance lock |
| `~/.vw/vw.sock` | runtime control socket |
| `~/.vw/vw.log` | daemon output/errors (truncated at each start) |

## Troubleshooting

- `Another instance is running` → run `vw stop` first.
- Wallpaper gone → the daemon probably exited; check `ps -p "$(cat ~/.vw/vw.pid)"`,
  then start again with `vw run`. The reason for any abnormal exit is in `~/.vw/vw.log`.
- The **lock screen** always shows the system's static wallpaper; that is a macOS
  limitation. The video resumes on the desktop after unlock.
- If you downloaded the binary with a **browser** instead of `curl`, macOS Gatekeeper
  may block it (quarantine); remove the flag with `xattr -d com.apple.quarantine <file>`
  or prefer the curl-based install.

## Development

```bash
xcodebuild -project Wallpaper.xcodeproj -scheme Wallpaper -configuration Debug build
```

Source layout: `Wallpaper/CLI` (command dispatch and subcommands), `Wallpaper/Core`
(playback engine, daemonization, PID/lock files, signal handling).
