#!/usr/bin/env bash
set -euo pipefail

APP=vw
REPO="xingxingmofashu/VideoWallpaper"
ASSET="vw-macos-arm64.tar.gz"

MUTED='\033[0;2m'
RED='\033[0;31m'
ORANGE='\033[38;5;214m'
NC='\033[0m'

usage() {
    cat <<EOF
VideoWallpaper Installer

Usage: install.sh [options]

Options:
    -h, --help              Display this help message
    -v, --version <version> Install a specific version (e.g. 1.5.0)
    -b, --binary <path>     Install from a local binary instead of downloading
        --no-modify-path    Don't modify shell config files (.zshrc, .bashrc, etc.)

Examples:
    curl -fsSL https://raw.githubusercontent.com/$REPO/main/Scripts/install.sh | bash
    curl -fsSL https://raw.githubusercontent.com/$REPO/main/Scripts/install.sh | bash -s -- --version 1.5.0
    ./Scripts/install.sh --binary /path/to/vw
EOF
}

requested_version="${VW_VERSION:-}"
explicit_version=false
no_modify_path=false
binary_path=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--version)
            if [[ -n "${2:-}" ]]; then
                requested_version="$2"
                explicit_version=true
                shift 2
            else
                echo -e "${RED}Error: --version requires a version argument${NC}" >&2
                exit 1
            fi
            ;;
        -b|--binary)
            if [[ -n "${2:-}" ]]; then
                binary_path="$2"
                shift 2
            else
                echo -e "${RED}Error: --binary requires a path argument${NC}" >&2
                exit 1
            fi
            ;;
        --no-modify-path)
            no_modify_path=true
            shift
            ;;
        *)
            echo -e "${ORANGE}Warning: Unknown option '$1'${NC}" >&2
            shift
            ;;
    esac
done

if [ "$(uname -s)" != "Darwin" ]; then
    echo -e "${RED}Error: vw only runs on macOS${NC}" >&2
    exit 1
fi

if [ "$(uname -m)" != "arm64" ]; then
    echo -e "${RED}Error: vw requires Apple Silicon (arm64), but this machine is $(uname -m)${NC}" >&2
    exit 1
fi

INSTALL_DIR="${VW_PREFIX:-$HOME/.vw/bin}"
mkdir -p "$INSTALL_DIR"

print_message() {
    local level=$1
    local message=$2
    local color=""

    case $level in
        info) color="${NC}" ;;
        warning) color="${NC}" ;;
        error) color="${RED}" ;;
    esac

    echo -e "${color}${message}${NC}"
}

check_version() {
    if command -v "$APP" >/dev/null 2>&1; then
        local installed
        installed=$("$APP" version 2>/dev/null | awk '{print $NF}' || echo "")
        if [ -n "$installed" ]; then
            print_message info "${MUTED}Installed version: ${NC}$installed."
        fi
    fi
}

unbuffered_sed() {
    if echo | sed -u -e "" >/dev/null 2>&1; then
        sed -nu "$@"
    elif echo | sed -l -e "" >/dev/null 2>&1; then
        sed -nl "$@"
    else
        local pad="$(printf "\n%512s" "")"
        sed -ne "s/$/\\${pad}/" "$@"
    fi
}

print_progress() {
    local bytes="$1"
    local length="$2"
    [ "$length" -gt 0 ] || return 0

    local width=50
    local percent=$(( bytes * 100 / length ))
    [ "$percent" -gt 100 ] && percent=100
    local on=$(( percent * width / 100 ))
    local off=$(( width - on ))

    local filled=$(printf "%*s" "$on" "")
    filled=${filled// /■}
    local empty=$(printf "%*s" "$off" "")
    empty=${empty// /･}

    printf "\r${ORANGE}%s%s %3d%%${NC}" "$filled" "$empty" "$percent" >&4
}

download_with_progress() {
    local url="$1"
    local output="$2"

    if [ -t 2 ]; then
        exec 4>&2
    else
        exec 4>/dev/null
    fi

    local tmp_dir=${TMPDIR:-/tmp}
    local basename="${tmp_dir}/vw_install_$$"
    local tracefile="${basename}.trace"

    rm -f "$tracefile"
    mkfifo "$tracefile"

    printf "\033[?25l" >&4

    trap "trap - RETURN; rm -f \"$tracefile\"; printf '\033[?25h' >&4; exec 4>&-" RETURN

    (
        curl --trace-ascii "$tracefile" -fsL -o "$output" "$url"
    ) &
    local curl_pid=$!

    unbuffered_sed \
        -e 'y/ACDEGHLNORTV/acdeghlnortv/' \
        -e '/^0000: content-length:/p' \
        -e '/^<= recv data/p' \
        "$tracefile" | \
    {
        local length=0
        local bytes=0

        while IFS=" " read -r -a line; do
            [ "${#line[@]}" -lt 2 ] && continue
            local tag="${line[0]} ${line[1]}"

            if [ "$tag" = "0000: content-length:" ]; then
                length="${line[2]}"
                length=$(echo "$length" | tr -d '\r')
                bytes=0
            elif [ "$tag" = "<= recv" ]; then
                local size="${line[3]}"
                bytes=$(( bytes + size ))
                if [ "$length" -gt 0 ]; then
                    print_progress "$bytes" "$length"
                fi
            fi
        done
    }

    wait $curl_pid
    local ret=$?
    echo "" >&4
    return $ret
}

install_from_path() {
    print_message info "\n${MUTED}Installing ${NC}$APP ${MUTED}to: ${NC}$INSTALL_DIR/$APP"
    rm -f "$INSTALL_DIR/$APP"
    cp "$1" "$INSTALL_DIR/$APP"
    chmod 755 "$INSTALL_DIR/$APP"
    print_message info "${MUTED}Installed: ${NC}$("$INSTALL_DIR/$APP" version)"
}

install_from_binary() {
    if [ ! -f "$binary_path" ]; then
        echo -e "${RED}Error: binary not found at $binary_path${NC}" >&2
        exit 1
    fi
    install_from_path "$binary_path"
}

download_and_install() {
    local version="${requested_version:-latest}"
    if [ "$version" = "latest" ]; then
        url="https://github.com/$REPO/releases/latest/download/$ASSET"
    else
        version="${version#v}"
        url="https://github.com/$REPO/releases/download/v$version/$ASSET"
    fi

    print_message info "\n${MUTED}Installing ${NC}$APP ${MUTED}version: ${NC}$version"
    local tmp_dir="${TMPDIR:-/tmp}/vw_install_$$"
    mkdir -p "$tmp_dir"
    trap "rm -rf '$tmp_dir'" EXIT

    if ! [ -t 2 ] || ! download_with_progress "$url" "$tmp_dir/$ASSET"; then
        curl -f -# -L -o "$tmp_dir/$ASSET" "$url" \
            || { echo -e "${RED}Error: download failed, is $version published?${NC}" >&2; exit 1; }
    fi

    tar -xzf "$tmp_dir/$ASSET" -C "$tmp_dir"
    if [ ! -f "$tmp_dir/$APP" ]; then
        echo -e "${RED}Error: archive does not contain the $APP binary${NC}" >&2
        exit 1
    fi
    install_from_path "$tmp_dir/$APP"
}

build_from_source() {
    command -v xcodebuild >/dev/null 2>&1 \
        || { echo -e "${RED}Error: xcodebuild not found, install Xcode first${NC}" >&2; exit 1; }

    local root project built
    root="$(cd "$(dirname "$0")/.." && pwd)"
    project="$root/VideoWallpaper.xcodeproj"
    built="$root/build/Build/Products/Release/VideoWallpaper"

    print_message info "${MUTED}Building (Release)...${NC}"
    xcodebuild -project "$project" -scheme VideoWallpaper -configuration Release \
        build -derivedDataPath "$root/build" -quiet

    if [ ! -f "$built" ]; then
        echo -e "${RED}Error: build product not found at $built${NC}" >&2
        exit 1
    fi
    install_from_path "$built"
}

add_to_path() {
    local config_file=$1
    local command=$2

    if grep -Fxq "$command" "$config_file"; then
        print_message info "Command already exists in $config_file, skipping write."
    elif [[ -w $config_file ]]; then
        echo -e "\n# vw" >> "$config_file"
        echo "$command" >> "$config_file"
        print_message info "${MUTED}Successfully added ${NC}vw ${MUTED}to \$PATH in ${NC}$config_file"
    else
        print_message warning "Manually add the directory to $config_file (or similar):"
        print_message info "  $command"
    fi
}

if [ -n "$binary_path" ]; then
    install_from_binary
elif [ "$explicit_version" = "true" ]; then
    check_version
    download_and_install
elif [ -d "$(dirname "$0")/../VideoWallpaper.xcodeproj" ]; then
    build_from_source
else
    check_version
    download_and_install
fi

XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}

current_shell=$(basename "${SHELL:-bash}")
case $current_shell in
    fish)
        config_files="$HOME/.config/fish/config.fish"
        ;;
    zsh)
        config_files="${ZDOTDIR:-$HOME}/.zshrc ${ZDOTDIR:-$HOME}/.zshenv $XDG_CONFIG_HOME/zsh/.zshrc $XDG_CONFIG_HOME/zsh/.zshenv"
        ;;
    bash)
        config_files="$HOME/.bashrc $HOME/.bash_profile $HOME/.profile $XDG_CONFIG_HOME/bash/.bashrc $XDG_CONFIG_HOME/bash/.bash_profile"
        ;;
    ash|sh)
        config_files="$HOME/.ashrc $HOME/.profile"
        ;;
    *)
        config_files="$HOME/.bashrc $HOME/.bash_profile $XDG_CONFIG_HOME/bash/.bashrc $XDG_CONFIG_HOME/bash/.bash_profile"
        ;;
esac

if [ -n "${VW_PREFIX:-}" ]; then
    print_message info "${MUTED}Installed to a custom prefix; add it to \$PATH if needed:${NC}"
    print_message info "  export PATH=$INSTALL_DIR:\$PATH"
elif [[ "$no_modify_path" != "true" ]]; then
    config_file=""
    for file in $config_files; do
        if [[ -f $file ]]; then
            config_file=$file
            break
        fi
    done

    if [[ -z $config_file ]]; then
        print_message warning "No config file found for $current_shell. You may need to manually add to PATH:"
        print_message info "  export PATH=$INSTALL_DIR:\$PATH"
    elif [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        case $current_shell in
            fish)
                add_to_path "$config_file" "fish_add_path $INSTALL_DIR"
                ;;
            *)
                add_to_path "$config_file" "export PATH=$INSTALL_DIR:\$PATH"
                ;;
        esac
    fi
fi

echo -e ""
echo -e "${MUTED}█ █ ▀█▀ █▀▄ █▀▀ █▀█${NC}  █ █ █ █▀█ █   █   █▀█ █▀█ █▀█ █▀▀ █▀▄"
echo -e "${MUTED}█ █  █  █ █ █▀▀ █ █${NC}  █ █ █ █▀█ █   █   █▀▀ █▀█ █▀▀ █▀▀ █▀▄"
echo -e "${MUTED} ▀  ▀▀▀ ▀▀▀ ▀▀▀ ▀▀▀${NC}   ▀ ▀  ▀ ▀ ▀▀▀ ▀▀▀ ▀   ▀ ▀ ▀   ▀▀▀ ▀ ▀"
echo -e ""
echo -e "${MUTED}To start a video wallpaper:${NC}"
echo -e ""
echo -e "vw run ~/Videos/wallpaper.mov   ${MUTED}# Start${NC}"
echo -e "vw stop                         ${MUTED}# Stop${NC}"
echo -e "vw upgrade                      ${MUTED}# Update${NC}"
echo -e "vw help                         ${MUTED}# Full help${NC}"
echo -e ""
echo -e "${MUTED}For more information visit ${NC}https://github.com/$REPO"
echo -e ""
