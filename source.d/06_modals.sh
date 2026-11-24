# ==============================================================================
# MODALS, PROMPTS & SERVICE ACTIONS
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

    systemctl status "$svc" --no-pager 2>&1 || true

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

    rm -f "$CONFIG_FILE" 2>/dev/null || true
    rm -f "$SCRIPTS_CONFIG_FILE" 2>/dev/null || true

    if (( FLAG_NO_LOG == 0 )); then
        rm -f "$LOG_FILE" 2>/dev/null || true
    fi

    load_services
    load_scripts
    refresh_data
    CURRENT_STATUS="Status: Config and log files deleted. Defaults re-initialized."
    audit_log "CLEAR" "CONFIG_AND_LOGS" "SUCCESS" "Deleted config and logs, reset to defaults"
}
