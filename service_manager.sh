#!/usr/bin/env bash
# ==============================================================================
# service_manager.sh - Production-grade Systemd Service Manager TUI
# Target: Linux Mint & systemd-based Linux distributions
# ==============================================================================

set -u
set -o pipefail

# ==============================================================================
# SOURCE MODULAR COMPONENTS
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/source.d/00_constants.sh"  # Colors, box chars, layout dims, paths
source "${SCRIPT_DIR}/source.d/01_cli.sh"         # CLI flags, show_help(), option parsing
source "${SCRIPT_DIR}/source.d/02_state.sh"        # State variables & associative arrays
source "${SCRIPT_DIR}/source.d/03_terminal.sh"     # Terminal helpers, cleanup trap, audit_log
source "${SCRIPT_DIR}/source.d/04_data.sh"         # load_services, filter_services, refresh_data
source "${SCRIPT_DIR}/source.d/05_ui_helpers.sh"   # print_box_* frame drawing helpers
source "${SCRIPT_DIR}/source.d/06_modals.sh"       # Modals, prompts & service actions
source "${SCRIPT_DIR}/source.d/07_draw.sh"         # get_hint_text, render_cheat_sheet, draw_ui
source "${SCRIPT_DIR}/source.d/08_input.sh"        # read_key, handle_resize, WINCH trap

# ==============================================================================
# MAIN ENTRY POINT
# ==============================================================================

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

        # While cheat sheet is open, only ESC and q/Q are active
        if (( HELP_MODE == 1 )); then
            case "$key" in
                ESC|h|H)
                    HELP_MODE=0
                    printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                    ;;
                q|Q)
                    break
                    ;;
            esac
            continue
        fi

        case "$key" in
            q|Q)
                break
                ;;
            h|H)
                HELP_MODE=1
                printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
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
                if [[ -n "$SEARCH_QUERY" ]]; then
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
            g|G|HOME)
                FOCUS_AREA="system"
                SYS_BTN=0
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
                    if (( SYS_BTN < 3 )); then
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
                            toggle_list
                            ;;
                        2)
                            HELP_MODE=1
                            printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                            ;;
                        3)
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
            t|T)
                toggle_list
                ;;
            a|A)
                if [[ "$LIST_MODE" == "system" ]] && (( ${#VISIBLE_SERVICES[@]} > 0 )); then
                    local target_svc="${VISIBLE_SERVICES[$SELECTED_ROW]}"
                    add_to_user_config "$target_svc"
                elif [[ "$LIST_MODE" == "user" ]]; then
                    CURRENT_STATUS="Status: Switch to systemctl list first to add a service [t]."
                fi
                ;;
            x|X)
                if [[ "$LIST_MODE" == "user" ]] && (( ${#VISIBLE_SERVICES[@]} > 0 )); then
                    local target_svc="${VISIBLE_SERVICES[$SELECTED_ROW]}"
                    remove_from_user_config "$target_svc"
                    # Clamp cursor after removal
                    if (( SELECTED_ROW >= ${#USER_SERVICES[@]} )) && (( ${#USER_SERVICES[@]} > 0 )); then
                        SELECTED_ROW=$(( ${#USER_SERVICES[@]} - 1 ))
                    fi
                    filter_services
                elif [[ "$LIST_MODE" == "system" ]]; then
                    CURRENT_STATUS="Status: Switch to user config list first to remove a service [t]."
                fi
                ;;
        esac
    done
}

main "$@"
