# ==============================================================================
# CODE STYLE & COLOR DEFINITIONS (SEMANTIC CONSTANTS)
# ==============================================================================
readonly COLOR_RESET=$'\e[0m'
readonly COLOR_BOLD=$'\e[1m'
readonly COLOR_DIM=$'\e[2m'
readonly COLOR_PRIMARY=$'\e[38;5;39m'        # Vibrant Blue / Cyan
readonly COLOR_SECONDARY=$'\e[38;5;246m'     # Slate Grey
readonly COLOR_SUCCESS=$'\e[38;5;42m'        # Spring Green
readonly COLOR_ERROR=$'\e[38;5;196m'         # Bright Red
readonly COLOR_WARN=$'\e[38;5;214m'          # Amber / Orange
readonly COLOR_MUTED=$'\e[38;5;241m'         # Dark Grey / Inactive
readonly COLOR_HIGHLIGHT=$'\e[30;48;5;45m'   # Inverted High-Contrast Selection
readonly COLOR_HIGHLIGHT_INACTIVE=$'\e[38;5;255;48;5;238m' # Subtle Highlight
readonly COLOR_ACCENT=$'\e[38;5;141m'        # Lavender / Purple
readonly COLOR_BORDER=$'\e[38;5;242m'        # Box Border Grey
readonly COLOR_TITLE=$'\e[1;38;5;229m'       # Bold Warm Ivory
readonly COLOR_TEXT=$'\e[38;5;253m'          # High-contrast Off-White

# Terminal Screen & Cursor Control Escape Sequences
readonly TERM_CURSOR_HIDE=$'\e[?25l'
readonly TERM_CURSOR_SHOW=$'\e[?25h'
readonly TERM_CLEAR_SCREEN=$'\e[2J'
readonly TERM_CURSOR_HOME=$'\e[H'
readonly TERM_CLEAR_LINE=$'\e[2K'

# UTF-8 Box Drawing Characters
readonly BOX_TL="╭"
readonly BOX_TR="╮"
readonly BOX_BL="╰"
readonly BOX_BR="╯"
readonly BOX_H="─"
readonly BOX_V="│"
readonly BOX_ML="├"
readonly BOX_MR="┤"

# Fixed Layout Dimensions
readonly INNER_WIDTH=76
readonly BOX_WIDTH=78
readonly HBAR=$(printf "%0.s${BOX_H}" $(seq 1 $INNER_WIDTH))

# Paths & Defaults
readonly CONFIG_DIR="${HOME}/.config/service_manager"
readonly CONFIG_FILE="${CONFIG_DIR}/services.conf"
readonly LOG_DIR="${HOME}/.local/share/service_manager"
readonly LOG_FILE="${LOG_DIR}/service_manager.log"
readonly SCRIPTS_DIR="${HOME}/.local/share/service_manager/scripts"
