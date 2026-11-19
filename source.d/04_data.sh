# ==============================================================================
# DATA LOADING, FILTERING & REFRESH
# ==============================================================================

# ==============================================================================
# DATA LOADING, FILTERING & REFRESH
# ==============================================================================

# Populate SYSCTRL_SERVICES from systemctl
_load_sysctrl_services() {
    SYSCTRL_SERVICES=()
    local unit_raw
    unit_raw=$(systemctl list-unit-files --type=service --state=enabled,disabled --no-legend --no-pager 2>/dev/null || true)
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" ]] && continue
        local unit_name="${line%% *}"
        [[ "$unit_name" == *@* ]] && continue
        unit_name="${unit_name%.service}"
        [[ -z "$unit_name" ]] && continue
        SYSCTRL_SERVICES+=("$unit_name")
    done <<< "$unit_raw"
}

# Populate USER_SERVICES from the config file
_load_user_services() {
    USER_SERVICES=()
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 0
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        USER_SERVICES+=("${line%.service}")
    done < "$CONFIG_FILE"
}

# Point SERVICES at the currently active list
_apply_list_mode() {
    if [[ "$LIST_MODE" == "user" ]] && (( ${#USER_SERVICES[@]} > 0 )); then
        SERVICES=("${USER_SERVICES[@]}")
    else
        LIST_MODE="system"
        SERVICES=("${SYSCTRL_SERVICES[@]}")
    fi
}

load_services() {
    _load_sysctrl_services
    _load_user_services

    # Startup rule: show user list first if non-empty, else systemctl
    if (( ${#USER_SERVICES[@]} > 0 )); then
        LIST_MODE="user"
    else
        LIST_MODE="system"
    fi

    _apply_list_mode
}

# Switch the active list (call with "user" or "system")
switch_list() {
    local target_mode="$1"
    if [[ "$target_mode" == "user" ]] && (( ${#USER_SERVICES[@]} == 0 )); then
        CURRENT_STATUS="Status: User config list is empty. Add services with [a]."
        return 0
    fi
    LIST_MODE="$target_mode"
    _apply_list_mode
    SELECTED_ROW=0
    SCROLL_OFFSET=0
    SEARCH_QUERY=""
    refresh_data
}

# Toggle between user and system list
toggle_list() {
    if [[ "$LIST_MODE" == "user" ]]; then
        switch_list "system"
        CURRENT_STATUS="Status: Switched to systemctl service list."
    else
        switch_list "user"
        if [[ "$LIST_MODE" == "user" ]]; then
            CURRENT_STATUS="Status: Switched to user config service list."
        fi
    fi
}

# Write current USER_SERVICES to the config file
_save_user_config() {
    mkdir -p "$CONFIG_DIR" 2>/dev/null || true
    : > "$CONFIG_FILE"
    for svc in "${USER_SERVICES[@]}"; do
        printf '%s\n' "$svc" >> "$CONFIG_FILE"
    done
}

# Add a service to the user config list (no duplicates)
add_to_user_config() {
    local svc="$1"
    # Duplicate check
    for existing in "${USER_SERVICES[@]+"${USER_SERVICES[@]}"}"; do
        if [[ "$existing" == "$svc" ]]; then
            CURRENT_STATUS="Status: '${svc}' is already in user config list."
            return 0
        fi
    done
    USER_SERVICES+=("$svc")
    _save_user_config
    audit_log "ADD_CONFIG" "$svc" "SUCCESS" "Added '${svc}' to user config"
    CURRENT_STATUS="Status: '${svc}' added to user config list."
}

# Remove a service from the user config list
remove_from_user_config() {
    local svc="$1"
    local new_list=()
    local found=0
    for existing in "${USER_SERVICES[@]+"${USER_SERVICES[@]}"}"; do
        if [[ "$existing" == "$svc" ]]; then
            found=1
        else
            new_list+=("$existing")
        fi
    done
    if (( found == 0 )); then
        CURRENT_STATUS="Status: '${svc}' not found in user config list."
        return 0
    fi
    USER_SERVICES=("${new_list[@]+"${new_list[@]}"}")
    _save_user_config
    audit_log "REMOVE_CONFIG" "$svc" "SUCCESS" "Removed '${svc}' from user config"
    CURRENT_STATUS="Status: '${svc}' removed from user config list."

    # If user list is now empty, auto-switch to system list
    if (( ${#USER_SERVICES[@]} == 0 )); then
        LIST_MODE="system"
        _apply_list_mode
        SELECTED_ROW=0
        SCROLL_OFFSET=0
        CURRENT_STATUS="Status: User config list is now empty. Switched to systemctl list."
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
# Queries the union of USER_SERVICES and SERVICES so that metadata is always
# populated regardless of which list is currently displayed.
refresh_data() {
    # Build a deduplicated union of both lists for the metadata query
    declare -A _seen_refresh=()
    local all_query=()
    for s in "${SERVICES[@]+"${SERVICES[@]}"}" "${USER_SERVICES[@]+"${USER_SERVICES[@]}"}"; do
        if [[ -z "${_seen_refresh[$s]+set}" ]]; then
            _seen_refresh["$s"]=1
            all_query+=("$s")
            SVC_ACTIVE_STATE["$s"]="unknown"
            SVC_UNIT_STATE["$s"]="unknown"
            SVC_DESCRIPTION["$s"]="Service metadata unavailable"
            SVC_PID["$s"]="0"
            CPU_USAGE["$s"]="0.0"
            MEM_USAGE["$s"]="0.0"
        fi
    done

    if [[ ${#all_query[@]} -gt 0 ]]; then
        local show_raw
        show_raw=$(systemctl show "${all_query[@]}" --property=Id,ActiveState,UnitFileState,Description,MainPID 2>/dev/null || true)

        declare -A block_props=()

        _commit_block() {
            local id="${block_props[Id]:-}"
            [[ -z "$id" ]] && return 0
            local clean_id="${id%.service}"
            local matched_svc=""
            for s in "${all_query[@]}"; do
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
        for s in "${all_query[@]}"; do
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

                for s in "${all_query[@]}"; do
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
