# shellcheck shell=bash
# ==============================================================================
# CODE STYLE, COLOR DEFINITIONS & PATH CONSTANTS
# ==============================================================================

# shellcheck disable=SC2034
readonly COLOR_RESET=$'\e[0m'
# shellcheck disable=SC2034
readonly COLOR_BOLD=$'\e[1m'
# shellcheck disable=SC2034
readonly COLOR_PRIMARY=$'\e[38;5;39m'        # Vibrant Blue / Cyan
# shellcheck disable=SC2034
readonly COLOR_SECONDARY=$'\e[38;5;246m'     # Slate Grey
# shellcheck disable=SC2034
readonly COLOR_SUCCESS=$'\e[38;5;42m'        # Spring Green
# shellcheck disable=SC2034
readonly COLOR_ERROR=$'\e[38;5;196m'         # Bright Red
# shellcheck disable=SC2034
readonly COLOR_WARN=$'\e[38;5;214m'          # Amber / Orange
# shellcheck disable=SC2034
readonly COLOR_MUTED=$'\e[38;5;241m'         # Dark Grey / Inactive
# shellcheck disable=SC2034
readonly COLOR_HIGHLIGHT=$'\e[30;48;5;45m'   # Inverted High-Contrast Selection
# shellcheck disable=SC2034
readonly COLOR_ACCENT=$'\e[38;5;141m'        # Lavender / Purple
# shellcheck disable=SC2034
readonly COLOR_BORDER=$'\e[38;5;242m'        # Box Border Grey
# shellcheck disable=SC2034
readonly COLOR_TITLE=$'\e[1;38;5;229m'       # Bold Warm Ivory
# shellcheck disable=SC2034
readonly COLOR_TEXT=$'\e[38;5;253m'          # High-contrast Off-White

# Terminal Screen & Cursor Control Escape Sequences
# shellcheck disable=SC2034
readonly TERM_CURSOR_HIDE=$'\e[?25l'
# shellcheck disable=SC2034
readonly TERM_CURSOR_SHOW=$'\e[?25h'
# shellcheck disable=SC2034
readonly TERM_CLEAR_SCREEN=$'\e[2J'
# shellcheck disable=SC2034
readonly TERM_CURSOR_HOME=$'\e[H'

# UTF-8 Box Drawing Characters
# shellcheck disable=SC2034
readonly BOX_TL="╭"
# shellcheck disable=SC2034
readonly BOX_TR="╮"
# shellcheck disable=SC2034
readonly BOX_BL="╰"
# shellcheck disable=SC2034
readonly BOX_BR="╯"
readonly BOX_H="─"
# shellcheck disable=SC2034
readonly BOX_V="│"
# shellcheck disable=SC2034
readonly BOX_ML="├"
# shellcheck disable=SC2034
readonly BOX_MR="┤"

# Fixed Layout Dimensions
readonly INNER_WIDTH=76
_CONST_HBAR_PAD=""
printf -v _CONST_HBAR_PAD '%*s' "$INNER_WIDTH" ""
# shellcheck disable=SC2034
readonly HBAR="${_CONST_HBAR_PAD// /$BOX_H}"
unset _CONST_HBAR_PAD

# Resolve invoking user's home directory and initialize readonly path constants.
# Inputs: $1=config override, $2=log override, $3=scripts config override
# Outputs: sets readonly REAL_HOME, CONFIG_DIR, CONFIG_FILE, SCRIPTS_CONFIG_FILE, LOG_DIR, LOG_FILE
# Returns: 0
constants__init_paths() {
    local cfg_override="${1:-}"
    local log_override="${2:-}"
    local scripts_override="${3:-}"

    local real_user="${SUDO_USER:-${USER:-}}"
    if [[ -z "$real_user" ]]; then
        real_user=$(id -un)
    fi

    local real_home=""
    local passwd_entry=""
    if passwd_entry=$(getent passwd "$real_user" 2>/dev/null); then
        IFS=: read -r _ _ _ _ _ real_home _ <<< "$passwd_entry"
    fi
    if [[ -z "$real_home" ]]; then
        real_home="$HOME"
    fi

    # shellcheck disable=SC2034
    readonly REAL_HOME="$real_home"
    readonly CONFIG_DIR="${real_home}/.config/service_manager"
    readonly CONFIG_FILE="${cfg_override:-${CONFIG_DIR}/services.conf}"

    local cfg_dir="."
    if [[ "$CONFIG_FILE" == */* ]]; then
        cfg_dir="${CONFIG_FILE%/*}"
        if [[ -z "$cfg_dir" ]]; then
            cfg_dir="/"
        fi
    fi

    # shellcheck disable=SC2034
    readonly SCRIPTS_CONFIG_FILE="${scripts_override:-${cfg_dir}/scripts.conf}"
    readonly LOG_DIR="${real_home}/.local/share/service_manager"
    # shellcheck disable=SC2034
    readonly LOG_FILE="${log_override:-${LOG_DIR}/service_manager.log}"
}
