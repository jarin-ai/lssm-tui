#!/usr/bin/env bash
# ==============================================================================
# service_manager.sh - Systemd Service and Scripts Manager TUI
# Target: systemd-based Linux distributions
# ==============================================================================

set -u
set -o pipefail

# ==============================================================================
# SOURCE MODULAR COMPONENTS
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/source.d/00_cli.sh"         # CLI flags, show_help(), option parsing
source "${SCRIPT_DIR}/source.d/01_constants.sh"  # Colors, box chars, layout dims, paths
source "${SCRIPT_DIR}/source.d/02_state.sh"        # State variables & associative arrays
source "${SCRIPT_DIR}/source.d/03_terminal.sh"     # Terminal helpers, cleanup trap, audit_log
source "${SCRIPT_DIR}/source.d/04_data.sh"         # load_services, filter_services, refresh_data
source "${SCRIPT_DIR}/source.d/05_ui_helpers.sh"   # print_box_* frame drawing helpers
source "${SCRIPT_DIR}/source.d/06_modals.sh"       # Modals, prompts & service actions
source "${SCRIPT_DIR}/source.d/09_scripts.sh"     # load_scripts, add_script_prompt, _run_script
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

    load_services
    load_scripts
    refresh_data
    CURRENT_STATUS="Status: Ready."

    # Enter alternate screen buffer and configure raw terminal only after
    # CLI parsing and pre-flight checks pass, right before the TUI loop.
    enter_tui_mode

    # Initial Screen Clear
    printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"

    local need_redraw=1

    while true; do
        # Do not allow losing focus from action bar when a list is empty
        if [[ "$FOCUS_AREA" == "services" ]]; then
            if [[ "$CURRENT_VIEW" == "scripts" ]] && (( ${#VISIBLE_SCRIPTS[@]} == 0 )); then
                FOCUS_AREA="system"
                SYS_BTN=1
            elif [[ "$CURRENT_VIEW" == "services" ]] && (( ${#VISIBLE_SERVICES[@]} == 0 )); then
                FOCUS_AREA="system"
                SYS_BTN=0
            fi
        fi

        if (( need_redraw == 1 )); then
            draw_ui
            need_redraw=0
        fi

        local key
        key=$(read_key) || break

        if (( SEARCH_MODE == 1 )); then
            need_redraw=1
            case "$key" in
                ENTER)
                    SEARCH_MODE=0
                    local is_empty=0
                    if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                        (( ${#VISIBLE_SCRIPTS[@]} == 0 )) && is_empty=1
                    else
                        (( ${#VISIBLE_SERVICES[@]} == 0 )) && is_empty=1
                    fi
                    if (( is_empty == 1 )); then
                        FOCUS_AREA="system"
                    else
                        FOCUS_AREA="services"
                    fi
                    ;;
                ESC)
                    SEARCH_MODE=0
                    SEARCH_QUERY=""
                    filter_services
                    filter_scripts
                    ;;
                BACKSPACE)
                    SEARCH_QUERY="${SEARCH_QUERY%?}"
                    filter_services
                    filter_scripts
                    ;;
                UP)
                    if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                        if (( SCRIPTS_ROW > 0 )); then
                            (( SCRIPTS_ROW-- ))
                        fi
                    else
                        if (( SELECTED_ROW > 0 )); then
                            (( SELECTED_ROW-- ))
                        fi
                    fi
                    ;;
                DOWN)
                    if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                        if (( SCRIPTS_ROW < ${#VISIBLE_SCRIPTS[@]} - 1 )); then
                            (( SCRIPTS_ROW++ ))
                        fi
                    else
                        if (( SELECTED_ROW < ${#VISIBLE_SERVICES[@]} - 1 )); then
                            (( SELECTED_ROW++ ))
                        fi
                    fi
                    ;;
                HOME)
                    if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                        SCRIPTS_ROW=0
                    else
                        SELECTED_ROW=0
                    fi
                    ;;
                END)
                    if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                        if (( ${#VISIBLE_SCRIPTS[@]} > 0 )); then
                            SCRIPTS_ROW=$(( ${#VISIBLE_SCRIPTS[@]} - 1 ))
                        fi
                    else
                        if (( ${#VISIBLE_SERVICES[@]} > 0 )); then
                            SELECTED_ROW=$(( ${#VISIBLE_SERVICES[@]} - 1 ))
                        fi
                    fi
                    ;;
                TAB)
                    SEARCH_MODE=0
                    local is_empty=0
                    if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                        (( ${#VISIBLE_SCRIPTS[@]} == 0 )) && is_empty=1
                    else
                        (( ${#VISIBLE_SERVICES[@]} == 0 )) && is_empty=1
                    fi
                    if (( is_empty == 1 )); then
                        FOCUS_AREA="system"
                    else
                        FOCUS_AREA="services"
                    fi
                    ;;
                *)
                    if [[ ${#key} -eq 1 ]]; then
                        SEARCH_QUERY+="$key"
                        filter_services
                        filter_scripts
                    fi
                    ;;
            esac
            continue
        fi

        # While cheat sheet is open: LEFT/RIGHT selects action, ENTER displays selected action, q/Q exits, UP/DOWN scrolls
        if (( HELP_MODE == 1 )); then
            case "$key" in
                q|Q)
                    break
                    ;;
                UP)
                    if (( HELP_SCROLL_OFFSET > 0 )); then
                        (( HELP_SCROLL_OFFSET-- ))
                        need_redraw=1
                    else
                        need_redraw=0
                    fi
                    ;;
                DOWN)
                    local available_rows=$(( TERM_LINES - 15 ))
                    (( available_rows < 5 ))  && available_rows=5
                    (( available_rows > 15 )) && available_rows=15
                    local max_scroll=$(( ${#CHEAT_LINES[@]} - available_rows ))
                    (( max_scroll < 0 )) && max_scroll=0
                    if (( HELP_SCROLL_OFFSET < max_scroll )); then
                        (( HELP_SCROLL_OFFSET++ ))
                        need_redraw=1
                    else
                        need_redraw=0
                    fi
                    ;;
                LEFT)
                    case "$SYS_BTN" in
                        4) SYS_BTN=3; need_redraw=1 ;;
                        3) SYS_BTN=1; need_redraw=1 ;;
                        2) SYS_BTN=1; need_redraw=1 ;;
                        1) SYS_BTN=0; need_redraw=1 ;;
                        0) need_redraw=0 ;;
                        *) SYS_BTN=0; need_redraw=1 ;;
                    esac
                    ;;
                RIGHT)
                    case "$SYS_BTN" in
                        0) SYS_BTN=1; need_redraw=1 ;;
                        1) SYS_BTN=3; need_redraw=1 ;;
                        2) SYS_BTN=3; need_redraw=1 ;;
                        3) SYS_BTN=4; need_redraw=1 ;;
                        4) need_redraw=0 ;;
                        *) SYS_BTN=4; need_redraw=1 ;;
                    esac
                    ;;
                ENTER)
                    case "$SYS_BTN" in
                        0)
                            HELP_MODE=0
                            CURRENT_VIEW="services"
                            FOCUS_AREA="system"
                            refresh_data
                            CURRENT_STATUS="Status: Services view active. Systemd cache refreshed."
                            printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                            need_redraw=1
                            ;;
                        1)
                            HELP_MODE=0
                            CURRENT_VIEW="scripts"
                            FOCUS_AREA="system"
                            load_scripts
                            CURRENT_STATUS="Status: Scripts view active."
                            printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                            need_redraw=1
                            ;;
                        3)
                            HELP_MODE=0
                            FOCUS_AREA="system"
                            action_clear_config_logs
                            printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                            need_redraw=1
                            ;;
                        4)
                            HELP_SCROLL_OFFSET=0
                            FOCUS_AREA="system"
                            printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                            need_redraw=1
                            ;;
                        *)
                            need_redraw=0
                            ;;
                    esac
                    ;;
                *)
                    need_redraw=0
                    ;;
            esac
            continue
        fi

        # Normal Navigation Mode
        need_redraw=1

        case "$key" in
            q|Q)
                break
                ;;
            h|H)
                HELP_MODE=1
                HELP_SCROLL_OFFSET=0
                SYS_BTN=4
                FOCUS_AREA="system"
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
                if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                    load_scripts
                    CURRENT_STATUS="Status: Scripts configuration refreshed."
                else
                    refresh_data
                    CURRENT_STATUS="Status: Systemd cache and process metrics refreshed."
                fi
                ;;
            j|J)
                if [[ "$CURRENT_VIEW" == "services" ]] && (( ${#VISIBLE_SERVICES[@]} > 0 )); then
                    local target_svc="${VISIBLE_SERVICES[$SELECTED_ROW]}"
                    show_log_modal "$target_svc"
                    printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                fi
                ;;
            i|I)
                if [[ "$CURRENT_VIEW" == "services" ]] && (( ${#VISIBLE_SERVICES[@]} > 0 )); then
                    local target_svc="${VISIBLE_SERVICES[$SELECTED_ROW]}"
                    show_status_modal "$target_svc"
                    printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                fi
                ;;
            f|F)
                SEARCH_MODE=1
                FOCUS_AREA="system"
                ;;
            ESC)
                if [[ -n "$SEARCH_QUERY" ]]; then
                    SEARCH_QUERY=""
                    filter_services
                    filter_scripts
                    CURRENT_STATUS="Status: Search filter cleared."
                elif [[ "$FOCUS_AREA" == "system" ]]; then
                    local is_empty=0
                    if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                        (( ${#VISIBLE_SCRIPTS[@]} == 0 )) && is_empty=1
                    else
                        (( ${#VISIBLE_SERVICES[@]} == 0 )) && is_empty=1
                    fi
                    if (( is_empty == 0 )); then
                        FOCUS_AREA="services"
                    else
                        need_redraw=0
                    fi
                fi
                ;;
            TAB)
                local is_empty=0
                if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                    (( ${#VISIBLE_SCRIPTS[@]} == 0 )) && is_empty=1
                else
                    (( ${#VISIBLE_SERVICES[@]} == 0 )) && is_empty=1
                fi

                if [[ "$FOCUS_AREA" == "services" ]]; then
                    FOCUS_AREA="system"
                elif (( is_empty == 0 )); then
                    FOCUS_AREA="services"
                else
                    need_redraw=0
                fi
                ;;
            HOME)
                if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                    if (( ${#VISIBLE_SCRIPTS[@]} == 0 )); then
                        need_redraw=0
                    else
                        FOCUS_AREA="services"
                        SCRIPTS_ROW=0
                    fi
                else
                    if (( ${#VISIBLE_SERVICES[@]} == 0 )); then
                        need_redraw=0
                    else
                        FOCUS_AREA="services"
                        SELECTED_ROW=0
                    fi
                fi
                ;;
            END)
                if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                    if (( ${#VISIBLE_SCRIPTS[@]} == 0 )); then
                        need_redraw=0
                    else
                        FOCUS_AREA="services"
                        SCRIPTS_ROW=$(( ${#VISIBLE_SCRIPTS[@]} - 1 ))
                    fi
                else
                    if (( ${#VISIBLE_SERVICES[@]} == 0 )); then
                        need_redraw=0
                    else
                        FOCUS_AREA="services"
                        SELECTED_ROW=$(( ${#VISIBLE_SERVICES[@]} - 1 ))
                    fi
                fi
                ;;
            UP)
                local is_empty=0
                if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                    (( ${#VISIBLE_SCRIPTS[@]} == 0 )) && is_empty=1
                else
                    (( ${#VISIBLE_SERVICES[@]} == 0 )) && is_empty=1
                fi

                if (( is_empty == 1 )); then
                    need_redraw=0
                elif [[ "$FOCUS_AREA" == "services" ]]; then
                    if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                        if (( SCRIPTS_ROW > 0 )); then
                            (( SCRIPTS_ROW-- ))
                        else
                            FOCUS_AREA="system"
                            SYS_BTN=1
                        fi
                    else
                        if (( SELECTED_ROW > 0 )); then
                            (( SELECTED_ROW-- ))
                        else
                            FOCUS_AREA="system"
                            SYS_BTN=0
                        fi
                    fi
                fi
                ;;
            DOWN)
                local is_empty=0
                if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                    (( ${#VISIBLE_SCRIPTS[@]} == 0 )) && is_empty=1
                else
                    (( ${#VISIBLE_SERVICES[@]} == 0 )) && is_empty=1
                fi

                if (( is_empty == 1 )); then
                    need_redraw=0
                elif [[ "$FOCUS_AREA" == "system" ]]; then
                    FOCUS_AREA="services"
                elif [[ "$FOCUS_AREA" == "services" ]]; then
                    if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                        if (( SCRIPTS_ROW < ${#VISIBLE_SCRIPTS[@]} - 1 )); then
                            (( SCRIPTS_ROW++ ))
                        fi
                    else
                        if (( SELECTED_ROW < ${#VISIBLE_SERVICES[@]} - 1 )); then
                            (( SELECTED_ROW++ ))
                        fi
                    fi
                fi
                ;;
            p|P)
                FOCUS_AREA="system"
                if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                    SYS_BTN=1
                else
                    SYS_BTN=0
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
                    if (( SYS_BTN < 4 )); then
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
                            CURRENT_VIEW="services"
                            refresh_data
                            CURRENT_STATUS="Status: Services view active. Systemd cache refreshed."
                            ;;
                        1)
                            CURRENT_VIEW="scripts"
                            load_scripts
                            CURRENT_STATUS="Status: Scripts view active."
                            ;;
                        2)
                            SEARCH_MODE=1
                            ;;
                        3)
                            action_clear_config_logs
                            printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                            ;;
                        4)
                            HELP_MODE=1
                            HELP_SCROLL_OFFSET=0
                            SYS_BTN=4
                            FOCUS_AREA="system"
                            printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                            ;;
                    esac
                elif [[ "$FOCUS_AREA" == "services" ]]; then
                    if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                        if (( ${#VISIBLE_SCRIPTS[@]} > 0 )); then
                            local s_idx="${VISIBLE_SCRIPTS[$SCRIPTS_ROW]}"
                            _run_script "${SCRIPTS_NAMES[$s_idx]}" "${SCRIPTS_PATHS[$s_idx]}"
                            printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                        fi
                    else
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
                fi
                ;;
            s|S)
                if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                    CURRENT_VIEW="services"
                    refresh_data
                    CURRENT_STATUS="Status: Services view active. Systemd cache refreshed."
                else
                    CURRENT_VIEW="scripts"
                    load_scripts
                    CURRENT_STATUS="Status: Scripts view active."
                fi
                ;;
            a|A)
                if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                    add_script_prompt
                    printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
                else
                    if (( ${#VISIBLE_SERVICES[@]} > 0 )); then
                        local target_svc="${VISIBLE_SERVICES[$SELECTED_ROW]}"
                        add_to_user_config "$target_svc"
                        filter_services
                    fi
                fi
                ;;
            x|X)
                if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                    if (( ${#VISIBLE_SCRIPTS[@]} > 0 )); then
                        local s_idx="${VISIBLE_SCRIPTS[$SCRIPTS_ROW]}"
                        local target_name="${SCRIPTS_NAMES[$s_idx]}"
                        remove_script_from_config "$target_name"
                        if (( SCRIPTS_ROW >= ${#VISIBLE_SCRIPTS[@]} )) && (( ${#VISIBLE_SCRIPTS[@]} > 0 )); then
                            SCRIPTS_ROW=$(( ${#VISIBLE_SCRIPTS[@]} - 1 ))
                        fi
                    fi
                else
                    if (( ${#VISIBLE_SERVICES[@]} > 0 )); then
                        local target_svc="${VISIBLE_SERVICES[$SELECTED_ROW]}"
                        remove_from_user_config "$target_svc"
                        # Clamp cursor after removal
                        if (( SELECTED_ROW >= ${#VISIBLE_SERVICES[@]} )) && (( ${#VISIBLE_SERVICES[@]} > 0 )); then
                            SELECTED_ROW=$(( ${#VISIBLE_SERVICES[@]} - 1 ))
                        fi
                        filter_services
                    fi
                fi
                ;;
        esac
    done
}

main "$@"
