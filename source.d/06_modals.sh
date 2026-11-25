# shellcheck shell=bash
# ==============================================================================
# MODALS, PROMPTS & SERVICE ACTIONS
# ==============================================================================

_modals__do_confirm() {
    local prompt_msg="$1"
    printf '%s%s' "$TERM_CURSOR_HOME" "$TERM_CLEAR_SCREEN"

    ui__print_box_top
    ui__print_box_line "  CONFIRMATION REQUIRED" "$COLOR_WARN$COLOR_BOLD"
    ui__print_box_divider
    ui__print_box_line "  ${prompt_msg}" "$COLOR_TEXT$COLOR_BOLD"
    ui__print_box_line "  Press 'y' or 'Y' to confirm, or any other key to cancel." "$COLOR_MUTED"
    ui__print_box_bottom

    printf '\n%s%s%s ' "$COLOR_WARN" "  Confirmation [y/N]: " "$COLOR_RESET"
    local resp=""
    read -r resp || return 1
    [[ "$resp" =~ ^[yY]([eE][sS])?$ ]]
}

# Prompt the user for interactive confirmation inside a cooked terminal modal.
# Inputs: $1=confirmation prompt message
# Outputs: modal UI on stdout
# Returns: 0 if confirmed, 1 if cancelled
modals__confirm_prompt() {
    local prompt_msg="$1"
    term__with_cooked_terminal _modals__do_confirm "$prompt_msg"
}

_modals__view_logs() {
    local svc="$1"
    printf '%s%s' "$TERM_CURSOR_HOME" "$TERM_CLEAR_SCREEN"

    ui__print_box_top
    ui__print_box_line "  Journalctl Audit Logs: ${svc} (Last 30 lines)" "$COLOR_TITLE$COLOR_BOLD"
    ui__print_box_divider

    journalctl -u "$svc" -n 30 --no-pager 2>&1 || \
        printf '%s  Failed to retrieve journal logs for %s%s\n' "$COLOR_ERROR" "$svc" "$COLOR_RESET"

    printf '\n'
    ui__wait_modal_footer "  Press [Enter] to return to service manager..."
}

# Display recent journalctl logs for a service in a modal.
# Inputs: $1=service name
# Outputs: log viewer modal on stdout
# Returns: 0
modals__show_logs() {
    local svc="$1"
    term__with_cooked_terminal _modals__view_logs "$svc"
}

_modals__view_status() {
    local svc="$1"
    printf '%s%s' "$TERM_CURSOR_HOME" "$TERM_CLEAR_SCREEN"

    ui__print_box_top
    ui__print_box_line "  Systemctl Status Inspection: ${svc}" "$COLOR_TITLE$COLOR_BOLD"
    ui__print_box_divider

    systemctl status "$svc" --no-pager 2>&1 || true

    printf '\n'
    ui__wait_modal_footer "  Press [Enter] to return to service manager..."
}

# Display systemctl status output for a service in a modal.
# Inputs: $1=service name
# Outputs: status viewer modal on stdout
# Returns: 0
modals__show_status() {
    local svc="$1"
    term__with_cooked_terminal _modals__view_status "$svc"
}

_modals__do_systemctl_action() {
    local action="$1"
    local svc="$2"
    if (( EUID == 0 )); then
        systemctl "$action" "$svc"
    else
        sudo systemctl "$action" "$svc"
    fi
}

# Execute a systemctl lifecycle action (start/stop/restart/enable/disable) with audit logging.
# Inputs: $1=service name, $2=action
# Outputs: updates status bar, audit log, and refreshes service data
# Returns: 0
modals__execute_service_action() {
    local svc="$1"
    local action="$2"

    if [[ "$action" == "stop" || "$action" == "disable" ]]; then
        if ! modals__confirm_prompt "Are you sure you want to ${action} '${svc}'? [y/N]"; then
            state__set_status "Status: Action cancelled: '${action}' on '${svc}'."
            return 0
        fi
    fi

    local err_out=""
    local ret_code=0
    err_out=$(term__with_cooked_terminal _modals__do_systemctl_action "$action" "$svc" 2>&1) || ret_code=$?

    if (( ret_code == 0 )); then
        local past_part="${action}ed"
        if [[ "$action" == "stop" ]]; then
            past_part="stopped"
        fi
        state__set_status "Status: Success: '${svc}' ${past_part}."
        audit__log "$action" "$svc" "SUCCESS" "Executed ${action} on ${svc}"
    else
        state__set_status "Status: Error: Failed to ${action} '${svc}'"
        local first_err="${err_out%%$'\n'*}"
        audit__log "$action" "$svc" "FAILURE" "${first_err:-exit code $ret_code}"
    fi

    data__refresh
}

# Prompt user and delete config/log files, then re-initialize default data.
# Inputs: none
# Outputs: removes CONFIG_FILE, SCRIPTS_CONFIG_FILE, and LOG_FILE (unless --no-log), refreshes state
# Returns: 0
modals__clear_config_logs() {
    if ! modals__confirm_prompt "Delete config and log files? [y/N]"; then
        state__set_status "Status: Clear cancelled by user."
        return 0
    fi

    rm -f "$CONFIG_FILE" 2>/dev/null || true
    rm -f "$SCRIPTS_CONFIG_FILE" 2>/dev/null || true

    if (( _CLI_NO_LOG == 0 )); then
        rm -f "$LOG_FILE" 2>/dev/null || true
    fi

    data__load_services
    scripts__load
    data__refresh
    state__set_status "Status: Config and log files deleted. Defaults re-initialized."
    audit__log "CLEAR" "CONFIG_AND_LOGS" "SUCCESS" "Deleted config and logs, reset to defaults"
}
