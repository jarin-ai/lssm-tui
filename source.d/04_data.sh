# shellcheck shell=bash
# ==============================================================================
# DATA LOADING, FILTERING & REFRESH
# ==============================================================================

declare -A _DATA_PINNED_MAP=()

# Populate STATE_SYSCTRL_SERVICES from systemctl list-unit-files.
# Inputs: none
# Outputs: populates STATE_SYSCTRL_SERVICES
# Returns: 0
_data__load_sysctrl_services() {
    STATE_SYSCTRL_SERVICES=()
    local line="" unit_name=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" ]] && continue
        unit_name="${line%% *}"
        [[ "$unit_name" == *@* ]] && continue
        unit_name="${unit_name%.service}"
        [[ -z "$unit_name" ]] && continue
        STATE_SYSCTRL_SERVICES+=("$unit_name")
    done < <(systemctl list-unit-files --type=service --state=enabled,disabled --no-legend --no-pager 2>/dev/null || true)
}

# Sort STATE_USER_SERVICES in place in alphabetic order (case-insensitive with exact tie-break).
# Inputs: none (reads/modifies STATE_USER_SERVICES)
# Outputs: sorts STATE_USER_SERVICES in place
# Returns: 0
_data__sort_user_services() {
    local count=${#STATE_USER_SERVICES[@]}
    if (( count <= 1 )); then
        return 0
    fi

    local i=0 j=0
    local key="" key_lower="" cur="" cur_lower=""

    for (( i=1; i < count; i++ )); do
        key="${STATE_USER_SERVICES[i]}"
        key_lower="${key,,}"
        j=$(( i - 1 ))

        while (( j >= 0 )); do
            cur="${STATE_USER_SERVICES[j]}"
            cur_lower="${cur,,}"
            if [[ "$cur_lower" > "$key_lower" ]] || \
               [[ "$cur_lower" == "$key_lower" && "$cur" > "$key" ]]; then
                STATE_USER_SERVICES[j + 1]="$cur"
                j=$(( j - 1 ))
            else
                break
            fi
        done
        STATE_USER_SERVICES[j + 1]="$key"
    done
}

# Populate STATE_USER_SERVICES from CONFIG_FILE in sorted alphabetic order.
# Inputs: none (reads CONFIG_FILE)
# Outputs: populates STATE_USER_SERVICES and _DATA_PINNED_MAP
# Returns: 0
_data__load_user_services() {
    STATE_USER_SERVICES=()
    _DATA_PINNED_MAP=()
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 0
    fi

    local line="" svc=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        util__trim line
        [[ -z "$line" || "$line" == \#* ]] && continue
        svc="${line%.service}"
        if [[ -z "${_DATA_PINNED_MAP[$svc]+set}" ]]; then
            _DATA_PINNED_MAP["$svc"]=1
            STATE_USER_SERVICES+=("$svc")
        fi
    done < "$CONFIG_FILE"

    _data__sort_user_services
}

# Load both systemd unit list and user pinned services config.
# Inputs: none
# Outputs: updates STATE_SYSCTRL_SERVICES and STATE_USER_SERVICES
# Returns: 0
data__load_services() {
    _data__load_sysctrl_services
    _data__load_user_services
}

# Persist STATE_USER_SERVICES to CONFIG_FILE.
# Inputs: none (reads CONFIG_DIR, CONFIG_FILE, STATE_USER_SERVICES)
# Outputs: writes CONFIG_FILE
# Returns: 0
_data__save_user_config() {
    mkdir -p "$CONFIG_DIR" 2>/dev/null || true
    local svc=""
    {
        for svc in "${STATE_USER_SERVICES[@]+"${STATE_USER_SERVICES[@]}"}"; do
            printf '%s\n' "$svc"
        done
    } > "$CONFIG_FILE"
}

# Return 0 if the given service is pinned, 1 otherwise.
# Inputs: $1=service name
# Outputs: none
# Returns: 0 if pinned, 1 otherwise
data__is_pinned() {
    [[ -n "${_DATA_PINNED_MAP[$1]+set}" ]]
}

# Pin a service to the top of the services list and save config.
# Inputs: $1=service name
# Outputs: updates STATE_USER_SERVICES, _DATA_PINNED_MAP, CONFIG_FILE, status, audit log
# Returns: 0
data__add_to_user_config() {
    local svc="$1"
    if data__is_pinned "$svc"; then
        state__set_status "Status: '${svc}' is already pinned."
        return 0
    fi

    STATE_USER_SERVICES+=("$svc")
    _data__sort_user_services
    _DATA_PINNED_MAP["$svc"]=1
    _data__save_user_config
    audit__log "ADD_CONFIG" "$svc" "SUCCESS" "Pinned '${svc}'"
    state__set_status "Status: '${svc}' pinned to top."
}

# Unpin a service from user config.
# Inputs: $1=service name
# Outputs: updates STATE_USER_SERVICES, _DATA_PINNED_MAP, CONFIG_FILE, status, audit log
# Returns: 0
data__remove_from_user_config() {
    local svc="$1"
    if ! data__is_pinned "$svc"; then
        state__set_status "Status: '${svc}' is not pinned."
        return 0
    fi

    local -a new_list=()
    local existing=""
    for existing in "${STATE_USER_SERVICES[@]+"${STATE_USER_SERVICES[@]}"}"; do
        if [[ "$existing" != "$svc" ]]; then
            new_list+=("$existing")
        fi
    done

    STATE_USER_SERVICES=("${new_list[@]+"${new_list[@]}"}")
    unset '_DATA_PINNED_MAP[$svc]'
    _data__save_user_config
    audit__log "REMOVE_CONFIG" "$svc" "SUCCESS" "Unpinned '${svc}'"
    state__set_status "Status: '${svc}' unpinned."
}

# Build STATE_VISIBLE_SERVICES: matching pinned services first, then unpinned system services.
# Inputs: none (reads STATE_SEARCH_QUERY, STATE_USER_SERVICES, STATE_SYSCTRL_SERVICES, STATE_SVC_DESC)
# Outputs: updates STATE_VISIBLE_SERVICES, STATE_PINNED_COUNT, STATE_SELECTED_ROW
# Returns: 0
data__filter_services() {
    # shellcheck disable=SC2034
    STATE_VISIBLE_SERVICES=()
    STATE_PINNED_COUNT=0

    local query_lower="${STATE_SEARCH_QUERY,,}"
    local s="" desc=""

    # --- Pinned section ---
    for s in "${STATE_USER_SERVICES[@]+"${STATE_USER_SERVICES[@]}"}"; do
        if [[ -n "$query_lower" ]]; then
            desc="${STATE_SVC_DESC[$s]:-}"
            [[ "${s,,}" == *"$query_lower"* || "${desc,,}" == *"$query_lower"* ]] || continue
        fi
        # shellcheck disable=SC2034
        STATE_VISIBLE_SERVICES+=("$s")
        STATE_PINNED_COUNT=$(( STATE_PINNED_COUNT + 1 ))
    done

    # --- System section (exclude pinned) ---
    for s in "${STATE_SYSCTRL_SERVICES[@]+"${STATE_SYSCTRL_SERVICES[@]}"}"; do
        data__is_pinned "$s" && continue
        if [[ -n "$query_lower" ]]; then
            desc="${STATE_SVC_DESC[$s]:-}"
            [[ "${s,,}" == *"$query_lower"* || "${desc,,}" == *"$query_lower"* ]] || continue
        fi
        # shellcheck disable=SC2034
        STATE_VISIBLE_SERVICES+=("$s")
    done

    local visible_count=${#STATE_VISIBLE_SERVICES[@]}
    if (( visible_count == 0 )); then
        STATE_SELECTED_ROW=0
    elif (( STATE_SELECTED_ROW >= visible_count )); then
        STATE_SELECTED_ROW=$(( visible_count - 1 ))
    fi
}

# Commit one parsed systemctl show property block into service metadata maps.
# Inputs: $1=nameref to block associative array, $2=nameref to unit->service lookup map
# Outputs: updates STATE_SVC_ACTIVE, STATE_SVC_UNIT, STATE_SVC_DESC, STATE_SVC_PID; clears block map
# Returns: 0
_data__commit_unit_block() {
    local -n _dcub_block="$1"
    local -n _dcub_lookup="$2"

    local _dcub_id="${_dcub_block[Id]:-}"
    if [[ -z "$_dcub_id" ]]; then
        _dcub_block=()
        return 0
    fi

    local _dcub_clean_id="${_dcub_id%.service}"
    local _dcub_matched_svc="${_dcub_lookup[$_dcub_id]:-${_dcub_lookup[$_dcub_clean_id]:-}}"

    if [[ -n "$_dcub_matched_svc" ]]; then
        # shellcheck disable=SC2034
        STATE_SVC_ACTIVE["$_dcub_matched_svc"]="${_dcub_block[ActiveState]:-inactive}"
        # shellcheck disable=SC2034
        STATE_SVC_UNIT["$_dcub_matched_svc"]="${_dcub_block[UnitFileState]:-disabled}"
        STATE_SVC_DESC["$_dcub_matched_svc"]="${_dcub_block[Description]:-No description available}"
        STATE_SVC_PID["$_dcub_matched_svc"]="${_dcub_block[MainPID]:-0}"
    fi

    _dcub_block=()
}

# Query batched systemd unit properties and process metrics (CPU/RSS) for all services.
# Inputs: none
# Outputs: updates STATE_SVC_* and STATE_CPU_USAGE / STATE_MEM_USAGE, then calls data__filter_services
# Returns: 0
data__refresh() {
    local -A seen_refresh=()
    local -A unit_lookup=()
    local -a all_query=()
    local s=""

    for s in "${STATE_USER_SERVICES[@]+"${STATE_USER_SERVICES[@]}"}" \
             "${STATE_SYSCTRL_SERVICES[@]+"${STATE_SYSCTRL_SERVICES[@]}"}"; do
        if [[ -z "${seen_refresh[$s]+set}" ]]; then
            seen_refresh["$s"]=1
            all_query+=("$s")
            unit_lookup["$s"]="$s"
            # Passed by nameref to _data__commit_unit_block
            # shellcheck disable=SC2034
            unit_lookup["${s%.service}"]="$s"
            # shellcheck disable=SC2034
            STATE_SVC_ACTIVE["$s"]="unknown"
            # shellcheck disable=SC2034
            STATE_SVC_UNIT["$s"]="unknown"
            STATE_SVC_DESC["$s"]="Service metadata unavailable"
            STATE_SVC_PID["$s"]="0"
            # shellcheck disable=SC2034
            STATE_CPU_USAGE["$s"]="0.0"
            # shellcheck disable=SC2034
            STATE_MEM_USAGE["$s"]="0.0"
        fi
    done

    if (( ${#all_query[@]} > 0 )); then
        local -A block_props=()
        local line="" k="" v=""

        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%$'\r'}"
            if [[ -z "$line" ]]; then
                _data__commit_unit_block block_props unit_lookup
                continue
            fi
            if [[ "$line" == *"="* ]]; then
                k="${line%%=*}"
                v="${line#*=}"
                # Passed by nameref to _data__commit_unit_block
                # shellcheck disable=SC2034
                block_props["$k"]="$v"
            fi
        done < <(systemctl show "${all_query[@]}" \
            --property=Id,ActiveState,UnitFileState,Description,MainPID 2>/dev/null || true)
        _data__commit_unit_block block_props unit_lookup

        local pid_list="" pid=""
        local -A pid_to_svcs=()
        for s in "${all_query[@]}"; do
            pid="${STATE_SVC_PID[$s]:-0}"
            if [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 0 )); then
                if [[ -z "$pid_list" ]]; then
                    pid_list="$pid"
                else
                    pid_list="${pid_list},${pid}"
                fi
                pid_to_svcs["$pid"]="${pid_to_svcs[$pid]:-}${pid_to_svcs[$pid]:+ }${s}"
            fi
        done

        if [[ -n "$pid_list" ]]; then
            local ps_line="" r_pid="" r_cpu="" r_rss=""
            local mem_mb="" whole=0 frac=0
            local -a matched_svcs=()

            while IFS= read -r ps_line || [[ -n "$ps_line" ]]; do
                [[ -z "$ps_line" ]] && continue
                read -r r_pid r_cpu r_rss <<< "$ps_line" || continue
                [[ -z "${r_pid:-}" || ! "$r_pid" =~ ^[0-9]+$ ]] && continue

                mem_mb="0.0"
                if [[ "${r_rss:-}" =~ ^[0-9]+$ ]] && (( r_rss > 0 )); then
                    whole=$(( r_rss / 1024 ))
                    frac=$(( (r_rss * 10 / 1024) % 10 ))
                    mem_mb="${whole}.${frac}"
                fi

                if [[ -n "${pid_to_svcs[$r_pid]+set}" ]]; then
                    read -ra matched_svcs <<< "${pid_to_svcs[$r_pid]}"
                    for s in "${matched_svcs[@]}"; do
                        # shellcheck disable=SC2034
                        STATE_CPU_USAGE["$s"]="$r_cpu"
                        # shellcheck disable=SC2034
                        STATE_MEM_USAGE["$s"]="$mem_mb"
                    done
                fi
            done < <(ps -o pid=,%cpu=,rss= -p "$pid_list" 2>/dev/null || true)
        fi
    fi

    data__filter_services
}
