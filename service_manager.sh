#!/usr/bin/env bash
# ==============================================================================
# service_manager.sh - Production-grade Systemd Service Manager TUI
# Target: Linux Mint & systemd-based Linux distributions
# ==============================================================================

set -u
set -o pipefail

# ==============================================================================
# 2. CODE STYLE & COLOR DEFINITIONS (SEMANTIC CONSTANTS)
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
readonly DEFAULT_SERVICES=("ssh" "nginx" "ufw" "bluetooth" "apache2")
readonly CONFIG_DIR="${HOME}/.config/service_manager"
readonly CONFIG_FILE="${CONFIG_DIR}/services.conf"
readonly LOG_DIR="${HOME}/.local/share/service_manager"
readonly LOG_FILE="${LOG_DIR}/service_manager.log"

# ==============================================================================
# 1. COMMAND LINE INTERFACE (CLI OPTIONS)
# ==============================================================================
FLAG_NO_CONFIG=0
FLAG_NO_LOG=0

show_help() {
    cat << 'EOF'
Usage: service_manager.sh [OPTIONS]

Production-grade interactive Terminal User Interface (TUI) to monitor,
manage, inspect, and log systemd services on Linux Mint and modern Linux.

Options:
  --help          Display this help documentation and exit immediately.
  --no-config     Disable reading or creating ~/.config/service_manager/services.conf.
                  Use hardcoded fallback services: ssh, nginx, ufw, bluetooth, apache2.
  --no-log        Disable audit logging. Suppress all write operations to
  --nn-log        ~/.local/share/service_manager/service_manager.log.

Keybindings & Controls:
  [Up / Down]     Navigate service rows or switch to top System Action Bar
  [Left / Right]  Navigate action buttons across highlighted row ([action1], [restart], [action2])
  [Enter]         Execute highlighted action (prompts [y/N] before stop/disable)
  [/]             Enter Search Mode (filters services by name and description)
  [h / H]         Toggle keybinding cheat sheet view
  [c / C]         Clear config and audit logs (prompts confirmation, resets defaults)
  [d / D]         Toggle Information Area view (Description <-> CPU/Memory/PID)
  [l / L]         Open journalctl log viewer modal (last 30 entries)
  [i / I]         Open systemctl status inspection modal
  [r / R]         Manually refresh systemd status cache and process metrics
  [ESC]           Exit active search mode, cheat sheet, or clear active search query
  [q / Q]         Cleanly exit service manager

Examples:
  ./service_manager.sh
  ./service_manager.sh --no-config
  ./service_manager.sh --no-log
  ./service_manager.sh --no-config --no-log
EOF
}

# Parse CLI options prior to UI initialization and pre-flight checks
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --no-config)
            FLAG_NO_CONFIG=1
            shift
            ;;
        --no-log|--nn-log)
            FLAG_NO_LOG=1
            shift
            ;;
        *)
            printf "Error: Unknown option '%s'\nTry '%s --help' for usage.\n" "$1" "$0" >&2
            exit 1
            ;;
    esac
done

# ==============================================================================
# STATE MANAGEMENT & DATA STRUCTURES
# ==============================================================================
SERVICES=()
VISIBLE_SERVICES=()

declare -A SVC_ACTIVE_STATE
declare -A SVC_UNIT_STATE
declare -A SVC_DESCRIPTION
declare -A SVC_PID
declare -A CPU_USAGE
declare -A MEM_USAGE

FOCUS_AREA="services"      # "services" or "system"
SYS_BTN=0                 # 0: [search], 1: [help], 2: [clear]
SELECTED_ROW=0            # Index within VISIBLE_SERVICES
SELECTED_BTN=0            # 0: [action1], 1: [restart], 2: [action2]
SCROLL_OFFSET=0           # Viewport scrolling offset
INFO_MODE=0               # 0: Description, 1: Live CPU/Memory
HELP_MODE=0               # 0: Normal service list, 1: Keybinding cheat sheet
SEARCH_MODE=0             # 0: Idle, 1: Active query typing
SEARCH_QUERY=""           # Current search string
CURRENT_STATUS="Status: Ready." # Execution result status message
SAVED_TTY_SETTINGS=""     # Cooked terminal mode backup
TERM_LINES=24             # Detected terminal rows
TERM_COLS=80              # Detected terminal columns

# ==============================================================================
# 5. D-BUS PERFORMANCE & TERMINAL STATE RULES
# ==============================================================================

# Subcommand Context Wrapper: Restores cooked terminal and shows cursor
with_cooked_terminal() {
    if [[ -n "${SAVED_TTY_SETTINGS:-}" ]]; then
        stty "$SAVED_TTY_SETTINGS" 2>/dev/null || stty icanon echo 2>/dev/null || true
    else
        stty icanon echo 2>/dev/null || true
    fi
    printf '%s' "$TERM_CURSOR_SHOW"

    local exit_code=0
    "$@" || exit_code=$?

    stty -icanon -echo min 1 time 0 2>/dev/null || true
    printf '%s' "$TERM_CURSOR_HIDE"

    return "$exit_code"
}

cleanup() {
    printf '%s' "$TERM_CURSOR_SHOW"
    if [[ -n "${SAVED_TTY_SETTINGS:-}" ]]; then
        stty "$SAVED_TTY_SETTINGS" 2>/dev/null || true
    else
        stty icanon echo 2>/dev/null || true
    fi
    printf '\n'
}
trap cleanup EXIT INT TERM HUP

audit_log() {
    local action="$1"
    local target="$2"
    local result="$3"
    local details="${4:-}"

    if (( FLAG_NO_LOG == 1 )); then
        return 0
    fi

    mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf '[%s] ACTION="%s" TARGET="%s" RESULT="%s" DETAILS="%s"\n' \
        "$timestamp" "$action" "$target" "$result" "$details" >> "$LOG_FILE" 2>/dev/null || true
}

load_services() {
    SERVICES=()
    if (( FLAG_NO_CONFIG == 1 )); then
        SERVICES=("${DEFAULT_SERVICES[@]}")
        return 0
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        mkdir -p "$CONFIG_DIR" 2>/dev/null || true
        cat << 'EOF' > "$CONFIG_FILE"
# Service Manager Configuration
# List systemd service names to monitor (one per line).
# Blank lines and lines starting with '#' are ignored.
ssh
nginx
ufw
bluetooth
apache2
EOF
    fi

    if [[ -f "$CONFIG_FILE" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            SERVICES+=("$line")
        done < "$CONFIG_FILE"
    fi

    if [[ ${#SERVICES[@]} -eq 0 ]]; then
        SERVICES=("${DEFAULT_SERVICES[@]}")
    fi
}

escape_glob() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\*/\\*}"
    str="${str//\?/\\?}"
    str="${str//\[/\\[}"
    str="${str//\]/\\]}"
    printf '%s' "$str"
}

filter_services() {
    VISIBLE_SERVICES=()
    shopt -s nocasematch
    if [[ -z "$SEARCH_QUERY" ]]; then
        VISIBLE_SERVICES=("${SERVICES[@]}")
    else
        local safe_q
        safe_q=$(escape_glob "$SEARCH_QUERY")
        local pat="*${safe_q}*"
        for s in "${SERVICES[@]}"; do
            local desc="${SVC_DESCRIPTION[$s]:-}"
            if [[ "$s" == $pat || "$desc" == $pat ]]; then
                VISIBLE_SERVICES+=("$s")
            fi
        done
    fi
    shopt -u nocasematch

    if (( ${#VISIBLE_SERVICES[@]} == 0 )); then
        SELECTED_ROW=0
    elif (( SELECTED_ROW >= ${#VISIBLE_SERVICES[@]} )); then
        SELECTED_ROW=$(( ${#VISIBLE_SERVICES[@]} - 1 ))
    fi
}

# 1. Batched Systemd Queries & 2. Batched Process Resource Metrics
refresh_data() {
    for s in "${SERVICES[@]}"; do
        SVC_ACTIVE_STATE["$s"]="unknown"
        SVC_UNIT_STATE["$s"]="unknown"
        SVC_DESCRIPTION["$s"]="Service metadata unavailable"
        SVC_PID["$s"]="0"
        CPU_USAGE["$s"]="0.0"
        MEM_USAGE["$s"]="0.0"
    done

    if [[ ${#SERVICES[@]} -gt 0 ]]; then
        local show_raw
        show_raw=$(systemctl show "${SERVICES[@]}" --property=Id,ActiveState,UnitFileState,Description,MainPID 2>/dev/null || true)

        declare -A block_props=()

        _commit_block() {
            local id="${block_props[Id]:-}"
            [[ -z "$id" ]] && return 0
            local clean_id="${id%.service}"
            local matched_svc=""
            for s in "${SERVICES[@]}"; do
                if [[ "$s" == "$id" || "$s" == "$clean_id" ]]; then
                    matched_svc="$s"
                    break
                fi
            done
            if [[ -n "$matched_svc" ]]; then
                SVC_ACTIVE_STATE["$matched_svc"]="${block_props[ActiveState]:-inactive}"
                SVC_UNIT_STATE["$matched_svc"]="${block_props[UnitFileState]:-disabled}"
                SVC_DESCRIPTION["$matched_svc"]="${block_props[Description]:-No description available}"
                SVC_PID["$matched_svc"]="${block_props[MainPID]:-0}"
            fi
            block_props=()
        }

        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%$'\r'}"
            if [[ -z "$line" ]]; then
                _commit_block
                continue
            fi
            if [[ "$line" == *"="* ]]; then
                local k="${line%%=*}"
                local v="${line#*=}"
                block_props["$k"]="$v"
            fi
        done <<< "$show_raw"
        _commit_block

        local pid_list=""
        for s in "${SERVICES[@]}"; do
            local pid="${SVC_PID[$s]:-0}"
            if [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 0 )); then
                if [[ -z "$pid_list" ]]; then
                    pid_list="$pid"
                else
                    pid_list="${pid_list},${pid}"
                fi
            fi
        done

        if [[ -n "$pid_list" ]]; then
            local ps_raw
            ps_raw=$(ps -o pid=,%cpu=,%mem=,rss= -p "$pid_list" 2>/dev/null || true)
            while IFS= read -r ps_line || [[ -n "$ps_line" ]]; do
                [[ -z "$ps_line" ]] && continue
                read -r r_pid r_cpu r_mem r_rss <<< "$ps_line"
                [[ -z "${r_pid:-}" || ! "$r_pid" =~ ^[0-9]+$ ]] && continue

                local mem_mb="0.0"
                if [[ "$r_rss" =~ ^[0-9]+$ ]] && (( r_rss > 0 )); then
                    local whole=$(( r_rss / 1024 ))
                    local frac=$(( (r_rss * 10 / 1024) % 10 ))
                    mem_mb="${whole}.${frac}"
                fi

                for s in "${SERVICES[@]}"; do
                    if [[ "${SVC_PID[$s]:-0}" == "$r_pid" ]]; then
                        CPU_USAGE["$s"]="$r_cpu"
                        MEM_USAGE["$s"]="$mem_mb"
                    fi
                done
            done <<< "$ps_raw"
        fi
    fi

    filter_services
}

# ==============================================================================
# UI FRAME BOX HELPERS (UTF-8 SAFE)
# ==============================================================================

print_box_top() {
    printf '%s%s%s%s%s\n' "$COLOR_BORDER" "$BOX_TL" "$HBAR" "$BOX_TR" "$COLOR_RESET"
}

print_box_divider() {
    printf '%s%s%s%s%s\n' "$COLOR_BORDER" "$BOX_ML" "$HBAR" "$BOX_MR" "$COLOR_RESET"
}

print_box_bottom() {
    printf '%s%s%s%s%s\n' "$COLOR_BORDER" "$BOX_BL" "$HBAR" "$BOX_BR" "$COLOR_RESET"
}

print_box_line() {
    local text="$1"
    local color="${2:-$COLOR_TEXT}"
    if (( ${#text} > INNER_WIDTH )); then
        text="${text:0:$INNER_WIDTH}"
    fi
    local pad_len=$(( INNER_WIDTH - ${#text} ))
    local spaces=""
    if (( pad_len > 0 )); then
        printf -v spaces "%*s" "$pad_len" ""
    fi
    printf '%s%s%s%s%s%s%s%s%s%s\n' \
        "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET" \
        "$color" "$text" "$COLOR_RESET" \
        "$spaces" \
        "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET"
}

# ==============================================================================
# MODALS & PROMPTS
# ==============================================================================

_do_confirm_modal() {
    local prompt_msg="$1"
    printf '%s%s' "$TERM_CURSOR_HOME" "$TERM_CLEAR_SCREEN"

    print_box_top
    print_box_line "  CONFIRMATION REQUIRED" "$COLOR_WARN$COLOR_BOLD"
    print_box_divider
    print_box_line "  ${prompt_msg}" "$COLOR_TEXT$COLOR_BOLD"
    print_box_line "  Press 'y' or 'Y' to confirm, or any other key to cancel." "$COLOR_MUTED"
    print_box_bottom

    printf '\n%s%s%s ' "$COLOR_WARN" "  Confirmation [y/N]: " "$COLOR_RESET"
    local resp=""
    read -r resp
    if [[ "$resp" =~ ^[yY]([eE][sS])?$ ]]; then
        return 0
    else
        return 1
    fi
}

confirm_prompt() {
    local prompt_msg="$1"
    with_cooked_terminal _do_confirm_modal "$prompt_msg"
}

_view_logs_modal() {
    local svc="$1"
    printf '%s%s' "$TERM_CURSOR_HOME" "$TERM_CLEAR_SCREEN"

    print_box_top
    print_box_line "  Journalctl Audit Logs: ${svc} (Last 30 lines)" "$COLOR_TITLE$COLOR_BOLD"
    print_box_divider

    journalctl -u "$svc" -n 30 --no-pager 2>&1 || printf '%s  Failed to retrieve journal logs for %s%s\n' "$COLOR_ERROR" "$svc" "$COLOR_RESET"

    printf '\n'
    print_box_divider
    print_box_line "  Press [Enter] to return to service manager..." "$COLOR_HIGHLIGHT$COLOR_BOLD"
    print_box_bottom

    read -r _
}

show_log_modal() {
    local svc="$1"
    with_cooked_terminal _view_logs_modal "$svc"
}

_view_status_modal() {
    local svc="$1"
    printf '%s%s' "$TERM_CURSOR_HOME" "$TERM_CLEAR_SCREEN"

    print_box_top
    print_box_line "  Systemctl Status Inspection: ${svc}" "$COLOR_TITLE$COLOR_BOLD"
    print_box_divider

    systemctl status "$svc" 2>&1 || true

    printf '\n'
    print_box_divider
    print_box_line "  Press [Enter] to return to service manager..." "$COLOR_HIGHLIGHT$COLOR_BOLD"
    print_box_bottom

    read -r _
}

show_status_modal() {
    local svc="$1"
    with_cooked_terminal _view_status_modal "$svc"
}

_do_systemctl_action() {
    local action="$1"
    local svc="$2"
    if [[ $EUID -eq 0 ]]; then
        systemctl "$action" "$svc"
    else
        sudo systemctl "$action" "$svc"
    fi
}

execute_service_action() {
    local svc="$1"
    local action="$2"

    if [[ "$action" == "stop" || "$action" == "disable" ]]; then
        if ! confirm_prompt "Are you sure you want to ${action} '${svc}'? [y/N]"; then
            CURRENT_STATUS="Status: Action cancelled: '${action}' on '${svc}'."
            return 0
        fi
    fi

    local err_out=""
    local ret_code=0
    err_out=$(with_cooked_terminal _do_systemctl_action "$action" "$svc" 2>&1) || ret_code=$?

    if (( ret_code == 0 )); then
        local past_part="${action}ed"
        [[ "$action" == "stop" ]] && past_part="stopped"
        CURRENT_STATUS="Status: Success: '${svc}' ${past_part}."
        audit_log "$action" "$svc" "SUCCESS" "Executed ${action} on ${svc}"
    else
        CURRENT_STATUS="Status: Error: Failed to ${action} '${svc}'"
        local first_err="${err_out%%$'\n'*}"
        audit_log "$action" "$svc" "FAILURE" "${first_err:-exit code $ret_code}"
    fi

    refresh_data
}

action_clear_config_logs() {
    if ! confirm_prompt "Delete config and log files? [y/N]"; then
        CURRENT_STATUS="Status: Clear cancelled by user."
        return 0
    fi

    if (( FLAG_NO_CONFIG == 0 )); then
        rm -f "$CONFIG_FILE" 2>/dev/null || true
    fi

    if (( FLAG_NO_LOG == 0 )); then
        rm -f "$LOG_FILE" 2>/dev/null || true
    fi

    load_services
    refresh_data
    CURRENT_STATUS="Status: Config and log files deleted. Defaults re-initialized."
    audit_log "CLEAR" "CONFIG_AND_LOGS" "SUCCESS" "Deleted config and logs, reset to defaults"
}

# ==============================================================================
# 3. TUI SCREEN LAYOUT STRUCTURE RENDERING
# ==============================================================================

get_hint_text() {
    if (( SEARCH_MODE == 1 )); then
        echo "Type query. Press [Enter] to finish search, [ESC] to cancel filter."
        return
    fi
    if (( HELP_MODE == 1 )); then
        echo "Press [h] or [ESC] to exit cheat sheet and return to service list."
        return
    fi
    if [[ "$FOCUS_AREA" == "system" ]]; then
        case "$SYS_BTN" in
            0) echo "Press [Enter] to enter Search Mode (or press '/')." ;;
            1) echo "Press [Enter] to view keybinding cheat sheet (or press 'h')." ;;
            2) echo "Press [Enter] to clear config & logs (or press 'c')." ;;
        esac
        return
    fi

    if (( ${#VISIBLE_SERVICES[@]} == 0 )); then
        echo "No matching services. Press [ESC] to clear search filter."
        return
    fi

    local current_svc="${VISIBLE_SERVICES[$SELECTED_ROW]}"
    case "$SELECTED_BTN" in
        0)
            local a_state="${SVC_ACTIVE_STATE[$current_svc]:-inactive}"
            if [[ "$a_state" == "active" ]]; then
                echo "Press [Enter] to stop '${current_svc}' (requires confirmation)."
            else
                echo "Press [Enter] to start '${current_svc}'."
            fi
            ;;
        1)
            echo "Press [Enter] to restart '${current_svc}'."
            ;;
        2)
            local u_state="${SVC_UNIT_STATE[$current_svc]:-disabled}"
            if [[ "$u_state" == "enabled" ]]; then
                echo "Press [Enter] to disable '${current_svc}' (requires confirmation)."
            else
                echo "Press [Enter] to enable '${current_svc}' on boot."
            fi
            ;;
    esac
}

render_cheat_sheet() {
    local cheat_lines=(
        "  KEYBOARD SHORTCUT CHEAT SHEET"
        "  ────────────────────────────────────────────────────────────────────────"
        "  [↑ / ↓]       Navigate service rows or switch to system action bar"
        "  [← / →]       Navigate action buttons across highlighted service row"
        "  [Enter]       Execute highlighted action (confirms stop/disable)"
        "  [/]           Enter Search Mode (filters services by name & description)"
        "  [h / H]       Toggle this keybinding cheat sheet"
        "  [c / C]       Clear config and audit logs (prompts confirmation)"
        "  [d / D]       Toggle Information Area (Description <-> CPU/Memory/PID)"
        "  [l / L]       Open journalctl log viewer modal (last 30 entries)"
        "  [i / I]       Open systemctl status inspection modal"
        "  [r / R]       Manually refresh systemd cache and process metrics"
        "  [ESC]         Exit active search / close cheat sheet / cancel filter"
        "  [q / Q]       Cleanly exit service manager"
    )
    for cline in "${cheat_lines[@]}"; do
        print_box_line "$cline" "$COLOR_SECONDARY"
    done
}

draw_ui() {
    # Move to Home without clearing to eliminate screen flicker
    printf '%s' "$TERM_CURSOR_HOME"

    # 1. Application Title Banner (Very Top)
    print_box_top
    local title_str="Linux systemctl manager"
    local left_pad=$(( (INNER_WIDTH - ${#title_str}) / 2 ))
    local right_pad=$(( INNER_WIDTH - ${#title_str} - left_pad ))
    local p_title
    printf -v p_title "%*s%s%*s" "$left_pad" "" "$title_str" "$right_pad" ""
    print_box_line "$p_title" "$COLOR_TITLE$COLOR_BOLD"

    # Divider below Title
    print_box_divider

    # 2. System Action Bar (Below Title)
    if (( SEARCH_MODE == 1 )); then
        local search_prefix="  Search: "
        local cursor_sym="_"
        local used_len=$(( ${#search_prefix} + ${#SEARCH_QUERY} + ${#cursor_sym} ))
        local fill_len=$(( INNER_WIDTH - used_len ))
        (( fill_len < 0 )) && fill_len=0
        local pad_fill
        printf -v pad_fill "%*s" "$fill_len" ""
        local search_line="  ${COLOR_ACCENT}Search: ${COLOR_RESET}${COLOR_BOLD}${COLOR_TEXT}${SEARCH_QUERY}${COLOR_PRIMARY}_${COLOR_RESET}${pad_fill}"
        printf '%s%s%s%s%s%s%s\n' \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET" \
            "$search_line" \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET"
    else
        local btn_search_style="$COLOR_ACCENT"
        local btn_help_style="$COLOR_ACCENT"
        local btn_clear_style="$COLOR_ACCENT"

        if [[ "$FOCUS_AREA" == "system" ]]; then
            (( SYS_BTN == 0 )) && btn_search_style="$COLOR_HIGHLIGHT" || btn_search_style="$COLOR_PRIMARY"
            (( SYS_BTN == 1 )) && btn_help_style="$COLOR_HIGHLIGHT" || btn_help_style="$COLOR_PRIMARY"
            (( SYS_BTN == 2 )) && btn_clear_style="$COLOR_HIGHLIGHT" || btn_clear_style="$COLOR_PRIMARY"
        fi

        local plain_len=41 # "  Actions:  [search]    [help]    [clear]"
        local pad_sys_len=$(( INNER_WIDTH - plain_len ))
        local pad_sys
        printf -v pad_sys "%*s" "$pad_sys_len" ""
        local sys_line="  Actions:  ${btn_search_style}[search]${COLOR_RESET}    ${btn_help_style}[help]${COLOR_RESET}    ${btn_clear_style}[clear]${COLOR_RESET}${pad_sys}"

        printf '%s%s%s%s%s%s%s\n' \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET" \
            "$sys_line" \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET"
    fi

    # Divider below System Action Bar
    print_box_divider

    # 3. Service List Area (Middle Main Area)
    if (( HELP_MODE == 1 )); then
        render_cheat_sheet
    else
        # Column Header Row
        local p_hdr_name p_hdr_active p_hdr_btn1 p_hdr_btn2 p_hdr_unit p_hdr_btn3
        printf -v p_hdr_name "%-16.16s" "SERVICE"
        printf -v p_hdr_active "%-12.12s" "STATE"
        printf -v p_hdr_btn1 "%-9.9s" "ACTION 1"
        printf -v p_hdr_btn2 "%-11.11s" "RESTART"
        printf -v p_hdr_unit "%-11.11s" "STARTUP"
        printf -v p_hdr_btn3 "%-9.9s" "ACTION 2"

        local hdr_content="  ${p_hdr_name} ${p_hdr_active} ${p_hdr_btn1} ${p_hdr_btn2} ${p_hdr_unit} ${p_hdr_btn3} "
        print_box_line "$hdr_content" "$COLOR_SECONDARY$COLOR_BOLD"

        # Calculate visible rows and scroll window
        local available_rows=$(( TERM_LINES - 15 ))
        (( available_rows < 5 )) && available_rows=5
        (( available_rows > 15 )) && available_rows=15

        if (( SELECTED_ROW < SCROLL_OFFSET )); then
            SCROLL_OFFSET=$SELECTED_ROW
        elif (( SELECTED_ROW >= SCROLL_OFFSET + available_rows )); then
            SCROLL_OFFSET=$(( SELECTED_ROW - available_rows + 1 ))
        fi

        local total_visible=${#VISIBLE_SERVICES[@]}
        if (( total_visible == 0 )); then
            print_box_line "  (No services match search filter)" "$COLOR_MUTED"
            for (( r=1; r < available_rows; r++ )); do
                print_box_line "" "$COLOR_TEXT"
            done
        else
            for (( idx=0; idx < available_rows; idx++ )); do
                local service_idx=$(( SCROLL_OFFSET + idx ))
                if (( service_idx < total_visible )); then
                    local svc="${VISIBLE_SERVICES[$service_idx]}"
                    local a_state="${SVC_ACTIVE_STATE[$svc]:-unknown}"
                    local u_state="${SVC_UNIT_STATE[$svc]:-unknown}"

                    local btn1_label="[start]"
                    [[ "$a_state" == "active" ]] && btn1_label="[stop]"

                    local btn2_label="[restart]"

                    local btn3_label="[enable]"
                    [[ "$u_state" == "enabled" ]] && btn3_label="[disable]"

                    # ANSI Padding Rule: ALWAYS pad plain text with printf BEFORE applying semantic colors
                    local pad_svc pad_act pad_b1 pad_b2 pad_unt pad_b3
                    printf -v pad_svc "%-16.16s" "$svc"
                    printf -v pad_act "%-12.12s" "$a_state"
                    printf -v pad_b1 "%-9.9s" "$btn1_label"
                    printf -v pad_b2 "%-11.11s" "$btn2_label"
                    printf -v pad_unt "%-11.11s" "$u_state"
                    printf -v pad_b3 "%-9.9s" "$btn3_label"

                    # Apply semantic color styling
                    local col_svc="$COLOR_TEXT"
                    local is_row_active=0
                    if [[ "$FOCUS_AREA" == "services" ]] && (( service_idx == SELECTED_ROW )); then
                        is_row_active=1
                        col_svc="${COLOR_BOLD}${COLOR_TEXT}"
                    fi

                    local col_act="$COLOR_MUTED"
                    if [[ "$a_state" == "active" ]]; then
                        col_act="$COLOR_SUCCESS"
                    elif [[ "$a_state" == "failed" ]]; then
                        col_act="${COLOR_ERROR}${COLOR_BOLD}"
                    elif [[ "$a_state" =~ ^(activating|reloading|deactivating)$ ]]; then
                        col_act="$COLOR_WARN"
                    fi

                    local col_unt="$COLOR_MUTED"
                    if [[ "$u_state" == "enabled" ]]; then
                        col_unt="$COLOR_SUCCESS"
                    elif [[ "$u_state" == "masked" ]]; then
                        col_unt="$COLOR_ERROR"
                    elif [[ "$u_state" =~ ^(static|indirect)$ ]]; then
                        col_unt="$COLOR_WARN"
                    fi

                    local col_b1="$COLOR_PRIMARY"
                    local col_b2="$COLOR_PRIMARY"
                    local col_b3="$COLOR_PRIMARY"

                    if (( is_row_active == 1 )); then
                        (( SELECTED_BTN == 0 )) && col_b1="$COLOR_HIGHLIGHT"
                        (( SELECTED_BTN == 1 )) && col_b2="$COLOR_HIGHLIGHT"
                        (( SELECTED_BTN == 2 )) && col_b3="$COLOR_HIGHLIGHT"
                    fi

                    local row_colored="  ${col_svc}${pad_svc}${COLOR_RESET} ${col_act}${pad_act}${COLOR_RESET} ${col_b1}${pad_b1}${COLOR_RESET} ${col_b2}${pad_b2}${COLOR_RESET} ${col_unt}${pad_unt}${COLOR_RESET} ${col_b3}${pad_b3}${COLOR_RESET} "
                    printf '%s%s%s%s%s%s%s\n' \
                        "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET" \
                        "$row_colored" \
                        "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET"
                else
                    print_box_line "" "$COLOR_TEXT"
                fi
            done
        fi
    fi

    # Divider below Service List Area
    print_box_divider

    # 4. Information Area (Below Service List)
    local info_text=""
    if (( ${#VISIBLE_SERVICES[@]} > 0 )); then
        local cur_svc="${VISIBLE_SERVICES[$SELECTED_ROW]}"
        if (( INFO_MODE == 0 )); then
            info_text="  Description: ${SVC_DESCRIPTION[$cur_svc]:-No description available}"
        else
            local cpu_val="${CPU_USAGE[$cur_svc]:-0.0}"
            local mem_val="${MEM_USAGE[$cur_svc]:-0.0}"
            local pid_val="${SVC_PID[$cur_svc]:-0}"
            [[ "$pid_val" == "0" ]] && pid_val="None"
            info_text="  Resource Usage: CPU: ${cpu_val}% | Memory: ${mem_val} MB | PID: ${pid_val}"
        fi
    else
        info_text="  Information: No service selected"
    fi
    print_box_line "$info_text" "$COLOR_ACCENT"

    # Divider below Information Area
    print_box_divider

    # 5. Hint Area (Below Information Area)
    local hint_text="  Hint: $(get_hint_text)"
    print_box_line "$hint_text" "$COLOR_MUTED"

    # Divider below Hint Area
    print_box_divider

    # 6. Status Bar (Bottom Row)
    local col_status="$COLOR_PRIMARY"
    if [[ "$CURRENT_STATUS" =~ "Success" ]]; then
        col_status="$COLOR_SUCCESS"
    elif [[ "$CURRENT_STATUS" =~ "Error" ]]; then
        col_status="${COLOR_ERROR}${COLOR_BOLD}"
    fi
    print_box_line "  ${CURRENT_STATUS}" "$col_status"

    # Bottom Frame Border
    print_box_bottom
}

# ==============================================================================
# 4. KEYBINDINGS & CONTROL LOGIC
# ==============================================================================

read_key() {
    local k=""
    IFS= read -rsn1 k || return 1
    if [[ "$k" == $'\x1b' ]]; then
        local seq=""
        IFS= read -rsn1 -t 0.05 seq || true
        if [[ -z "$seq" ]]; then
            echo "ESC"
            return 0
        fi
        if [[ "$seq" == "[" ]]; then
            local code=""
            IFS= read -rsn1 -t 0.05 code || true
            case "$code" in
                A) echo "UP"; return 0 ;;
                B) echo "DOWN"; return 0 ;;
                C) echo "RIGHT"; return 0 ;;
                D) echo "LEFT"; return 0 ;;
                Z) echo "BTAB"; return 0 ;;
                *) echo "ESC"; return 0 ;;
            esac
        fi
        echo "ESC"
        return 0
    elif [[ -z "$k" || "$k" == $'\n' || "$k" == $'\r' ]]; then
        echo "ENTER"
        return 0
    elif [[ "$k" == $'\t' ]]; then
        echo "TAB"
        return 0
    elif [[ "$k" == $'\x7f' || "$k" == $'\x08' ]]; then
        echo "BACKSPACE"
        return 0
    else
        echo "$k"
        return 0
    fi
}

handle_resize() {
    TERM_COLS=$(tput cols 2>/dev/null || echo 80)
    TERM_LINES=$(tput lines 2>/dev/null || echo 24)
    printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
    draw_ui
}
trap handle_resize WINCH

main() {
    # Pre-flight Terminal Check
    if [[ ! -t 0 || ! -t 1 ]]; then
        printf "Error: Standard input/output is not a terminal.\n" >&2
        exit 1
    fi

    # Save initial terminal state
    SAVED_TTY_SETTINGS=$(stty -g 2>/dev/null || true)

    # 3. Non-Canonical Terminal Input: Preserve newline translation
    stty -icanon -echo min 1 time 0 2>/dev/null || true
    printf '%s' "$TERM_CURSOR_HIDE"

    TERM_COLS=$(tput cols 2>/dev/null || echo 80)
    TERM_LINES=$(tput lines 2>/dev/null || echo 24)

    load_services
    refresh_data

    # Initial Screen Clear
    printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"

    while true; do
        draw_ui

        local key
        key=$(read_key) || break

        if (( SEARCH_MODE == 1 )); then
            case "$key" in
                ENTER)
                    SEARCH_MODE=0
                    FOCUS_AREA="services"
                    ;;
                ESC)
                    SEARCH_MODE=0
                    SEARCH_QUERY=""
                    filter_services
                    ;;
                BACKSPACE)
                    SEARCH_QUERY="${SEARCH_QUERY%?}"
                    filter_services
                    ;;
                UP)
                    if (( SELECTED_ROW > 0 )); then
                        (( SELECTED_ROW-- ))
                    fi
                    ;;
                DOWN)
                    if (( SELECTED_ROW < ${#VISIBLE_SERVICES[@]} - 1 )); then
                        (( SELECTED_ROW++ ))
                    fi
                    ;;
                TAB)
                    SEARCH_MODE=0
                    FOCUS_AREA="services"
                    ;;
                *)
                    if [[ ${#key} -eq 1 ]]; then
                        SEARCH_QUERY+="$key"
                        filter_services
                    fi
                    ;;
            esac
            continue
        fi

        # Normal Navigation Mode
        case "$key" in
            q|Q)
                break
                ;;
            h|H)
                HELP_MODE=$(( 1 - HELP_MODE ))
                ;;
            c|C)
                action_clear_config_logs
                printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                ;;
            d|D)
                INFO_MODE=$(( 1 - INFO_MODE ))
                ;;
            r|R)
                refresh_data
                CURRENT_STATUS="Status: Systemd cache and process metrics refreshed."
                ;;
            l|L)
                if (( ${#VISIBLE_SERVICES[@]} > 0 )); then
                    local target_svc="${VISIBLE_SERVICES[$SELECTED_ROW]}"
                    show_log_modal "$target_svc"
                    printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                fi
                ;;
            i|I)
                if (( ${#VISIBLE_SERVICES[@]} > 0 )); then
                    local target_svc="${VISIBLE_SERVICES[$SELECTED_ROW]}"
                    show_status_modal "$target_svc"
                    printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                fi
                ;;
            "/")
                SEARCH_MODE=1
                FOCUS_AREA="system"
                ;;
            ESC)
                if (( HELP_MODE == 1 )); then
                    HELP_MODE=0
                elif [[ -n "$SEARCH_QUERY" ]]; then
                    SEARCH_QUERY=""
                    filter_services
                    CURRENT_STATUS="Status: Search filter cleared."
                elif [[ "$FOCUS_AREA" == "system" ]]; then
                    FOCUS_AREA="services"
                fi
                ;;
            TAB)
                if [[ "$FOCUS_AREA" == "services" ]]; then
                    FOCUS_AREA="system"
                else
                    FOCUS_AREA="services"
                fi
                ;;
            BTAB)
                if [[ "$FOCUS_AREA" == "services" ]]; then
                    FOCUS_AREA="system"
                else
                    FOCUS_AREA="services"
                fi
                ;;
            UP)
                if [[ "$FOCUS_AREA" == "services" ]]; then
                    if (( SELECTED_ROW > 0 )); then
                        (( SELECTED_ROW-- ))
                    else
                        FOCUS_AREA="system"
                        SYS_BTN=0
                    fi
                fi
                ;;
            DOWN)
                if [[ "$FOCUS_AREA" == "system" ]]; then
                    FOCUS_AREA="services"
                elif [[ "$FOCUS_AREA" == "services" ]]; then
                    if (( SELECTED_ROW < ${#VISIBLE_SERVICES[@]} - 1 )); then
                        (( SELECTED_ROW++ ))
                    fi
                fi
                ;;
            LEFT)
                if [[ "$FOCUS_AREA" == "system" ]]; then
                    if (( SYS_BTN > 0 )); then
                        (( SYS_BTN-- ))
                    fi
                elif [[ "$FOCUS_AREA" == "services" ]]; then
                    if (( SELECTED_BTN > 0 )); then
                        (( SELECTED_BTN-- ))
                    fi
                fi
                ;;
            RIGHT)
                if [[ "$FOCUS_AREA" == "system" ]]; then
                    if (( SYS_BTN < 2 )); then
                        (( SYS_BTN++ ))
                    fi
                elif [[ "$FOCUS_AREA" == "services" ]]; then
                    if (( SELECTED_BTN < 2 )); then
                        (( SELECTED_BTN++ ))
                    fi
                fi
                ;;
            ENTER)
                if [[ "$FOCUS_AREA" == "system" ]]; then
                    case "$SYS_BTN" in
                        0)
                            SEARCH_MODE=1
                            ;;
                        1)
                            HELP_MODE=$(( 1 - HELP_MODE ))
                            ;;
                        2)
                            action_clear_config_logs
                            printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                            ;;
                    esac
                elif [[ "$FOCUS_AREA" == "services" ]]; then
                    if (( ${#VISIBLE_SERVICES[@]} > 0 )); then
                        local svc="${VISIBLE_SERVICES[$SELECTED_ROW]}"
                        local a_state="${SVC_ACTIVE_STATE[$svc]:-unknown}"
                        local u_state="${SVC_UNIT_STATE[$svc]:-unknown}"

                        case "$SELECTED_BTN" in
                            0)
                                if [[ "$a_state" == "active" ]]; then
                                    execute_service_action "$svc" "stop"
                                else
                                    execute_service_action "$svc" "start"
                                fi
                                printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                                ;;
                            1)
                                execute_service_action "$svc" "restart"
                                printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                                ;;
                            2)
                                if [[ "$u_state" == "enabled" ]]; then
                                    execute_service_action "$svc" "disable"
                                else
                                    execute_service_action "$svc" "enable"
                                fi
                                printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                                ;;
                        esac
                    fi
                fi
                ;;
        esac
    done
}

main "$@"
