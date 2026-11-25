#!/usr/bin/env bash
# ==============================================================================
# service_manager.sh - Systemd Service and Scripts Manager TUI
# Target: systemd-based Linux distributions
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SOURCE MODULAR LIBRARIES
# ==============================================================================
_SM_ENTRY="${BASH_SOURCE[0]}"
if [[ "$_SM_ENTRY" == */* ]]; then
    _SM_DIR="${_SM_ENTRY%/*}"
    [[ -z "$_SM_DIR" ]] && _SM_DIR="/"
    SCRIPT_DIR="$(cd "$_SM_DIR" && pwd)"
    unset _SM_DIR
else
    SCRIPT_DIR="$PWD"
fi
unset _SM_ENTRY

source "${SCRIPT_DIR}/source.d/00_cli.sh"
source "${SCRIPT_DIR}/source.d/01_constants.sh"
source "${SCRIPT_DIR}/source.d/02_state.sh"
source "${SCRIPT_DIR}/source.d/03_terminal.sh"
source "${SCRIPT_DIR}/source.d/04_data.sh"
source "${SCRIPT_DIR}/source.d/05_ui_helpers.sh"
source "${SCRIPT_DIR}/source.d/06_modals.sh"
source "${SCRIPT_DIR}/source.d/07_draw.sh"
source "${SCRIPT_DIR}/source.d/08_input.sh"
source "${SCRIPT_DIR}/source.d/09_scripts.sh"

# ==============================================================================
# CONTROLLER HELPERS & EVENT HANDLERS
# ==============================================================================

_sm__install_traps() {
    term__register_cleanup term__cleanup
    trap 'term__run_cleanups' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    trap 'input__handle_resize' WINCH
}

_sm__clear_screen() {
    printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
}

_sm__apply_search_filters() {
    data__filter_services
    scripts__filter
}

_sm__switch_view() {
    local target_view="$1"
    if [[ "$target_view" == "scripts" ]]; then
        STATE_CURRENT_VIEW="scripts"
        scripts__load
        state__set_status "Status: Scripts view active."
    else
        STATE_CURRENT_VIEW="services"
        data__refresh
        state__set_status "Status: Services view active. Systemd cache refreshed."
    fi
}

_sm__open_help_view() {
    STATE_HELP_MODE=1
    STATE_HELP_SCROLL_OFFSET=0
    STATE_SYS_BTN=4
    STATE_FOCUS_AREA="system"
    _sm__clear_screen
}

_sm__handle_search_key() {
    local _hsk_key="$1"
    local -n _hsk_redraw="$2"

    case "$_hsk_key" in
        ENTER|TAB)
            STATE_SEARCH_MODE=0
            if state__is_current_list_empty; then
                STATE_FOCUS_AREA="system"
            else
                STATE_FOCUS_AREA="services"
            fi
            _hsk_redraw=1
            ;;
        ESC)
            STATE_SEARCH_MODE=0
            STATE_SEARCH_QUERY=""
            _sm__apply_search_filters
            _hsk_redraw=1
            ;;
        BACKSPACE)
            if [[ -n "$STATE_SEARCH_QUERY" ]]; then
                STATE_SEARCH_QUERY="${STATE_SEARCH_QUERY%?}"
                _sm__apply_search_filters
                _hsk_redraw=1
            else
                _hsk_redraw=0
            fi
            ;;
        *)
            if (( ${#_hsk_key} == 1 )); then
                STATE_SEARCH_QUERY+="$_hsk_key"
                _sm__apply_search_filters
                _hsk_redraw=1
            else
                _hsk_redraw=0
            fi
            ;;
    esac
}

_sm__handle_help_key() {
    local _hhk_key="$1"
    local -n _hhk_redraw="$2"
    local -n _hhk_quit="$3"

    case "$_hhk_key" in
        q|Q)
            _hhk_quit=1
            ;;
        UP)
            if (( STATE_HELP_SCROLL_OFFSET > 0 )); then
                STATE_HELP_SCROLL_OFFSET=$(( STATE_HELP_SCROLL_OFFSET - 1 ))
                _hhk_redraw=1
            else
                _hhk_redraw=0
            fi
            ;;
        DOWN)
            local _hhk_avail=0 _hhk_total=0
            util__clamp_list_rows "$STATE_TERM_LINES" _hhk_avail
            draw__get_cheat_count _hhk_total
            local _hhk_max=$(( _hhk_total - _hhk_avail ))
            if (( _hhk_max < 0 )); then
                _hhk_max=0
            fi
            if (( STATE_HELP_SCROLL_OFFSET < _hhk_max )); then
                STATE_HELP_SCROLL_OFFSET=$(( STATE_HELP_SCROLL_OFFSET + 1 ))
                _hhk_redraw=1
            else
                _hhk_redraw=0
            fi
            ;;
        LEFT)
            case "$STATE_SYS_BTN" in
                4) STATE_SYS_BTN=3; _hhk_redraw=1 ;;
                3) STATE_SYS_BTN=1; _hhk_redraw=1 ;;
                2) STATE_SYS_BTN=1; _hhk_redraw=1 ;;
                1) STATE_SYS_BTN=0; _hhk_redraw=1 ;;
                0) _hhk_redraw=0 ;;
                *) STATE_SYS_BTN=0; _hhk_redraw=1 ;;
            esac
            ;;
        RIGHT)
            case "$STATE_SYS_BTN" in
                0) STATE_SYS_BTN=1; _hhk_redraw=1 ;;
                1) STATE_SYS_BTN=3; _hhk_redraw=1 ;;
                2) STATE_SYS_BTN=3; _hhk_redraw=1 ;;
                3) STATE_SYS_BTN=4; _hhk_redraw=1 ;;
                4) _hhk_redraw=0 ;;
                *) STATE_SYS_BTN=4; _hhk_redraw=1 ;;
            esac
            ;;
        ENTER)
            case "$STATE_SYS_BTN" in
                0)
                    STATE_HELP_MODE=0
                    STATE_FOCUS_AREA="system"
                    _sm__switch_view "services"
                    _sm__clear_screen
                    _hhk_redraw=1
                    ;;
                1)
                    STATE_HELP_MODE=0
                    STATE_FOCUS_AREA="system"
                    _sm__switch_view "scripts"
                    _sm__clear_screen
                    _hhk_redraw=1
                    ;;
                3)
                    STATE_HELP_MODE=0
                    STATE_FOCUS_AREA="system"
                    modals__clear_config_logs
                    _sm__clear_screen
                    _hhk_redraw=1
                    ;;
                4)
                    STATE_HELP_SCROLL_OFFSET=0
                    STATE_FOCUS_AREA="system"
                    _sm__clear_screen
                    _hhk_redraw=1
                    ;;
                *)
                    _hhk_redraw=0
                    ;;
            esac
            ;;
        *)
            _hhk_redraw=0
            ;;
    esac
}

_sm__execute_enter_action() {
    if [[ "$STATE_FOCUS_AREA" == "system" ]]; then
        case "$STATE_SYS_BTN" in
            0) _sm__switch_view "services" ;;
            1) _sm__switch_view "scripts" ;;
            2) STATE_SEARCH_MODE=1 ;;
            3)
                modals__clear_config_logs
                _sm__clear_screen
                ;;
            4) _sm__open_help_view ;;
        esac
        return 0
    fi

    if [[ "$STATE_FOCUS_AREA" != "services" ]]; then
        return 0
    fi

    if [[ "$STATE_CURRENT_VIEW" == "scripts" ]]; then
        if (( ${#STATE_VISIBLE_SCRIPTS[@]} > 0 )); then
            local s_idx="${STATE_VISIBLE_SCRIPTS[$STATE_SCRIPTS_ROW]}"
            scripts__run "${STATE_SCRIPTS_NAMES[$s_idx]}" "${STATE_SCRIPTS_PATHS[$s_idx]}"
            _sm__clear_screen
        fi
        return 0
    fi

    if (( ${#STATE_VISIBLE_SERVICES[@]} > 0 )); then
        local svc="${STATE_VISIBLE_SERVICES[$STATE_SELECTED_ROW]}"
        local a_state="${STATE_SVC_ACTIVE[$svc]:-unknown}"
        local u_state="${STATE_SVC_UNIT[$svc]:-unknown}"

        case "$STATE_SELECTED_BTN" in
            0)
                if [[ "$a_state" == "active" ]]; then
                    modals__execute_service_action "$svc" "stop"
                else
                    modals__execute_service_action "$svc" "start"
                fi
                _sm__clear_screen
                ;;
            1)
                modals__execute_service_action "$svc" "restart"
                _sm__clear_screen
                ;;
            2)
                if [[ "$u_state" == "enabled" ]]; then
                    modals__execute_service_action "$svc" "disable"
                else
                    modals__execute_service_action "$svc" "enable"
                fi
                _sm__clear_screen
                ;;
        esac
    fi
}

_sm__handle_nav_key() {
    local _hnk_key="$1"
    local -n _hnk_redraw="$2"
    local -n _hnk_quit="$3"

    _hnk_redraw=1

    case "$_hnk_key" in
        q|Q)
            _hnk_quit=1
            ;;
        h|H)
            _sm__open_help_view
            ;;
        c|C)
            modals__clear_config_logs
            _sm__clear_screen
            ;;
        d|D)
            STATE_INFO_MODE=$(( 1 - STATE_INFO_MODE ))
            ;;
        r|R)
            if [[ "$STATE_CURRENT_VIEW" == "scripts" ]]; then
                scripts__load
                state__set_status "Status: Scripts configuration refreshed."
            else
                data__refresh
                state__set_status "Status: Systemd cache and process metrics refreshed."
            fi
            ;;
        j|J)
            if [[ "$STATE_CURRENT_VIEW" == "services" ]] && (( ${#STATE_VISIBLE_SERVICES[@]} > 0 )); then
                modals__show_logs "${STATE_VISIBLE_SERVICES[$STATE_SELECTED_ROW]}"
                _sm__clear_screen
            else
                _hnk_redraw=0
            fi
            ;;
        i|I)
            if [[ "$STATE_CURRENT_VIEW" == "services" ]] && (( ${#STATE_VISIBLE_SERVICES[@]} > 0 )); then
                modals__show_status "${STATE_VISIBLE_SERVICES[$STATE_SELECTED_ROW]}"
                _sm__clear_screen
            else
                _hnk_redraw=0
            fi
            ;;
        f|F)
            STATE_SEARCH_MODE=1
            STATE_FOCUS_AREA="system"
            ;;
        ESC)
            if [[ -n "$STATE_SEARCH_QUERY" ]]; then
                STATE_SEARCH_QUERY=""
                _sm__apply_search_filters
                state__set_status "Status: Search filter cleared."
            elif [[ "$STATE_FOCUS_AREA" == "system" ]]; then
                if ! state__is_current_list_empty; then
                    STATE_FOCUS_AREA="services"
                else
                    _hnk_redraw=0
                fi
            fi
            ;;
        TAB)
            if [[ "$STATE_FOCUS_AREA" == "services" ]]; then
                STATE_FOCUS_AREA="system"
            elif ! state__is_current_list_empty; then
                STATE_FOCUS_AREA="services"
            else
                _hnk_redraw=0
            fi
            ;;
        HOME)
            if state__is_current_list_empty; then
                _hnk_redraw=0
            else
                STATE_FOCUS_AREA="services"
                if [[ "$STATE_CURRENT_VIEW" == "scripts" ]]; then
                    STATE_SCRIPTS_ROW=0
                else
                    STATE_SELECTED_ROW=0
                fi
            fi
            ;;
        END)
            if state__is_current_list_empty; then
                _hnk_redraw=0
            else
                STATE_FOCUS_AREA="services"
                if [[ "$STATE_CURRENT_VIEW" == "scripts" ]]; then
                    STATE_SCRIPTS_ROW=$(( ${#STATE_VISIBLE_SCRIPTS[@]} - 1 ))
                else
                    STATE_SELECTED_ROW=$(( ${#STATE_VISIBLE_SERVICES[@]} - 1 ))
                fi
            fi
            ;;
        UP)
            if state__is_current_list_empty; then
                _hnk_redraw=0
            elif [[ "$STATE_FOCUS_AREA" == "services" ]]; then
                if [[ "$STATE_CURRENT_VIEW" == "scripts" ]]; then
                    if (( STATE_SCRIPTS_ROW > 0 )); then
                        STATE_SCRIPTS_ROW=$(( STATE_SCRIPTS_ROW - 1 ))
                    else
                        STATE_FOCUS_AREA="system"
                        STATE_SYS_BTN=1
                    fi
                else
                    if (( STATE_SELECTED_ROW > 0 )); then
                        STATE_SELECTED_ROW=$(( STATE_SELECTED_ROW - 1 ))
                    else
                        STATE_FOCUS_AREA="system"
                        STATE_SYS_BTN=0
                    fi
                fi
            fi
            ;;
        DOWN)
            if state__is_current_list_empty; then
                _hnk_redraw=0
            elif [[ "$STATE_FOCUS_AREA" == "system" ]]; then
                STATE_FOCUS_AREA="services"
            elif [[ "$STATE_FOCUS_AREA" == "services" ]]; then
                if [[ "$STATE_CURRENT_VIEW" == "scripts" ]]; then
                    if (( STATE_SCRIPTS_ROW < ${#STATE_VISIBLE_SCRIPTS[@]} - 1 )); then
                        STATE_SCRIPTS_ROW=$(( STATE_SCRIPTS_ROW + 1 ))
                    fi
                else
                    if (( STATE_SELECTED_ROW < ${#STATE_VISIBLE_SERVICES[@]} - 1 )); then
                        STATE_SELECTED_ROW=$(( STATE_SELECTED_ROW + 1 ))
                    fi
                fi
            fi
            ;;
        p|P)
            STATE_FOCUS_AREA="system"
            if [[ "$STATE_CURRENT_VIEW" == "scripts" ]]; then
                STATE_SYS_BTN=1
            else
                STATE_SYS_BTN=0
            fi
            ;;
        LEFT)
            if [[ "$STATE_FOCUS_AREA" == "system" ]]; then
                if (( STATE_SYS_BTN > 0 )); then
                    STATE_SYS_BTN=$(( STATE_SYS_BTN - 1 ))
                fi
            elif [[ "$STATE_FOCUS_AREA" == "services" ]]; then
                if (( STATE_SELECTED_BTN > 0 )); then
                    STATE_SELECTED_BTN=$(( STATE_SELECTED_BTN - 1 ))
                fi
            fi
            ;;
        RIGHT)
            if [[ "$STATE_FOCUS_AREA" == "system" ]]; then
                if (( STATE_SYS_BTN < 4 )); then
                    STATE_SYS_BTN=$(( STATE_SYS_BTN + 1 ))
                fi
            elif [[ "$STATE_FOCUS_AREA" == "services" ]]; then
                if (( STATE_SELECTED_BTN < 2 )); then
                    STATE_SELECTED_BTN=$(( STATE_SELECTED_BTN + 1 ))
                fi
            fi
            ;;
        ENTER)
            _sm__execute_enter_action
            ;;
        s|S)
            if [[ "$STATE_CURRENT_VIEW" == "scripts" ]]; then
                _sm__switch_view "services"
            else
                _sm__switch_view "scripts"
            fi
            ;;
        a|A)
            if [[ "$STATE_CURRENT_VIEW" == "scripts" ]]; then
                scripts__add_prompt
                _sm__clear_screen
            elif (( ${#STATE_VISIBLE_SERVICES[@]} > 0 )); then
                data__add_to_user_config "${STATE_VISIBLE_SERVICES[$STATE_SELECTED_ROW]}"
                data__filter_services
            fi
            ;;
        x|X)
            if [[ "$STATE_CURRENT_VIEW" == "scripts" ]]; then
                if (( ${#STATE_VISIBLE_SCRIPTS[@]} > 0 )); then
                    local _hnk_s_idx="${STATE_VISIBLE_SCRIPTS[$STATE_SCRIPTS_ROW]}"
                    scripts__remove_from_config "${STATE_SCRIPTS_NAMES[$_hnk_s_idx]}"
                    if (( STATE_SCRIPTS_ROW >= ${#STATE_VISIBLE_SCRIPTS[@]} )) && (( ${#STATE_VISIBLE_SCRIPTS[@]} > 0 )); then
                        STATE_SCRIPTS_ROW=$(( ${#STATE_VISIBLE_SCRIPTS[@]} - 1 ))
                    fi
                fi
            elif (( ${#STATE_VISIBLE_SERVICES[@]} > 0 )); then
                data__remove_from_user_config "${STATE_VISIBLE_SERVICES[$STATE_SELECTED_ROW]}"
                if (( STATE_SELECTED_ROW >= ${#STATE_VISIBLE_SERVICES[@]} )) && (( ${#STATE_VISIBLE_SERVICES[@]} > 0 )); then
                    STATE_SELECTED_ROW=$(( ${#STATE_VISIBLE_SERVICES[@]} - 1 ))
                fi
                data__filter_services
            fi
            ;;
        *)
            _hnk_redraw=0
            ;;
    esac
}

# ==============================================================================
# MAIN ENTRY POINT
# ==============================================================================

main() {
    local cli_rc=0
    cli__parse "$0" "$@" || cli_rc=$?
    if (( cli_rc == 2 )); then
        return 0
    elif (( cli_rc != 0 )); then
        return "$cli_rc"
    fi

    # Pre-flight Terminal Check
    if [[ ! -t 0 || ! -t 1 ]]; then
        printf "Error: Standard input/output is not a terminal.\n" >&2
        return 1
    fi

    constants__init_paths \
        "$_CLI_OVERRIDE_CONFIG_FILE" \
        "$_CLI_OVERRIDE_LOG_FILE" \
        "$_CLI_OVERRIDE_SCRIPTS_CONFIG"

    _sm__install_traps

    data__load_services
    scripts__load
    data__refresh
    state__set_status "Status: Ready."

    # Enter alternate screen buffer and configure raw terminal only after
    # CLI parsing and pre-flight checks pass, right before the TUI loop.
    term__enter_tui_mode
    _sm__clear_screen

    local need_redraw=1
    local should_quit=0
    local key=""

    while (( should_quit == 0 )); do
        # Do not allow losing focus from action bar when a list is empty
        if [[ "$STATE_FOCUS_AREA" == "services" ]] && state__is_current_list_empty; then
            STATE_FOCUS_AREA="system"
            if [[ "$STATE_CURRENT_VIEW" == "scripts" ]]; then
                STATE_SYS_BTN=1
            else
                STATE_SYS_BTN=0
            fi
        fi

        if (( need_redraw == 1 )); then
            draw__ui
            need_redraw=0
        fi

        input__read_key key || break

        if (( STATE_SEARCH_MODE == 1 )); then
            _sm__handle_search_key "$key" need_redraw
            continue
        fi

        if (( STATE_HELP_MODE == 1 )); then
            _sm__handle_help_key "$key" need_redraw should_quit
            continue
        fi

        _sm__handle_nav_key "$key" need_redraw should_quit
    done
}

main "$@"
