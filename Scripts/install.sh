#!/bin/bash
# One-click install for the vw CLI.
#
# Usage:
#   Scripts/install.sh                       Build (Release) and install from this repo
#   VW_PREFIX=/some/dir Scripts/install.sh   Install to a custom prefix
#   curl -fsSL https://raw.githubusercontent.com/xingxingmofashu/VideoWallpaper/main/Scripts/install.sh | bash
#                                            Download the latest release and install (no clone needed)
#   VW_VERSION=v1.0.0 <command above>        Install a specific release instead of latest
#
# Install location (first match wins):
#   1. $VW_PREFIX          if set
#   2. /usr/local/bin      if writable
#   3. /opt/homebrew/bin   if writable (no sudo needed)
#   4. /usr/local/bin      via sudo (will prompt for password)
set -euo pipefail

REPO="xingxingmofashu/VideoWallpaper"

resolve_dest() {
    if [ -n "${VW_PREFIX:-}" ]; then
        echo "$VW_PREFIX"
    elif [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
        echo "/usr/local/bin"
    elif [ -d /opt/homebrew/bin ] && [ -w /opt/homebrew/bin ]; then
        echo "/opt/homebrew/bin"
    else
        echo "/usr/local/bin"
    fi
}

DEST_DIR="$(resolve_dest)"
DEST="$DEST_DIR/vw"

SUDO=""
if [ ! -d "$DEST_DIR" ] || [ ! -w "$DEST_DIR" ]; then
    SUDO="sudo"
fi

install_binary() {
    echo "Installing to $DEST..."
    $SUDO mkdir -p "$DEST_DIR"
    $SUDO rm -f "$DEST"
    $SUDO cp -f "$1" "$DEST"

    echo "Installed: $("$DEST" version)"

    case ":$PATH:" in
        *":$DEST_DIR:"*) ;;
        *) echo "note: add $DEST_DIR to your PATH to use vw from anywhere" ;;
    esac

    echo
    echo "Usage:"
    echo "  vw run ~/Videos/wallpaper.mov   Play a video wallpaper"
    echo "  vw stop                         Stop the running instance"
    echo "  vw help                         Show full help"
}

if [ -d "$(dirname "$0")/../VideoWallpaper.xcodeproj" ]; then
    command -v xcodebuild >/dev/null 2>&1 \
        || { echo "error: xcodebuild not found, please install Xcode first" >&2; exit 1; }

    ROOT="$(cd "$(dirname "$0")/.." && pwd)"
    PROJECT="$ROOT/VideoWallpaper.xcodeproj"
    BUILT="$ROOT/build/Build/Products/Release/VideoWallpaper"

    echo "Building (Release)..."
    xcodebuild -project "$PROJECT" -scheme VideoWallpaper -configuration Release \
        build -derivedDataPath "$ROOT/build" -quiet
    [ -f "$BUILT" ] || { echo "error: build product not found at $BUILT" >&2; exit 1; }

    install_binary "$BUILT"
else
    command -v curl >/dev/null 2>&1 || { echo "error: curl not found" >&2; exit 1; }
    command -v tar >/dev/null 2>&1 || { echo "error: tar not found" >&2; exit 1; }

    version="${VW_VERSION:-latest}"
    if [ "$version" = "latest" ]; then
        url="https://github.com/$REPO/releases/latest/download/vw-macos-arm64.tar.gz"
    else
        url="https://github.com/$REPO/releases/download/$version/vw-macos-arm64.tar.gz"
    fi

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    echo "Downloading vw $version..."
    curl -fSL "$url" -o "$tmp/vw.tar.gz" \
        || { echo "error: download failed, is the release published?" >&2; exit 1; }
    tar -xzf "$tmp/vw.tar.gz" -C "$tmp"
    [ -f "$tmp/vw" ] || { echo "error: archive does not contain the vw binary" >&2; exit 1; }

    install_binary "$tmp/vw"
fi
